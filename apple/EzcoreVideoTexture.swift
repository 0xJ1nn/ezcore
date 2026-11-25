// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import CoreVideo
import Foundation

#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif

/// One external texture backed by a pool of IOSurface pixel buffers.
///
/// Three slots keep Flutter's last copied buffer intact while the emulator
/// writes the next frame: the runtime never blocks on the raster thread and a
/// slow reader gets the newest complete frame instead of a torn one. The
/// channel hands raw XRGB8888 frames to `publish`; a hardware-rendering core
/// writes straight into the buffer handed to `withLockedBuffer`.
final class EzcoreVideoTexture: NSObject, FlutterTexture {
    private enum SlotState: Equatable {
        case free
        case writing
        case ready
        case presented
    }

    private static let slotCount = 3
    private static let maxDimension = 8192

    private let lock = NSLock()
    private var slots: [CVPixelBuffer] = []
    private var states: [SlotState] = []
    private var width = 0
    private var height = 0
    private var ready: Int?
    private var presented: Int?
    private var writing: Int?
    private var textureId: Int64 = 0
    private var onFrame: ((Int64) -> Void)?

    /// The bridge binds the id returned by the texture registry and the
    /// registry's `textureFrameAvailable` callback after registration.
    func bind(textureId: Int64, frameAvailable: @escaping (Int64) -> Void) {
        self.textureId = textureId
        self.onFrame = frameAvailable
    }

    /// Flutter calls this on the raster thread. The returned buffer is
    /// retained; the caller releases it. Re-presenting the last buffer until a
    /// new frame arrives avoids blank frames between copies.
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        defer { lock.unlock() }
        if let index = presented, index < slots.count {
            return Unmanaged.passRetained(slots[index])
        }
        guard let index = ready, index < slots.count else { return nil }
        if let previous = presented, previous != index, previous < states.count {
            states[previous] = .free
        }
        states[index] = .presented
        presented = index
        ready = nil
        return Unmanaged.passRetained(slots[index])
    }

    /// Copies one XRGB8888 frame into a locked pool buffer and presents it.
    /// The source rows are tightly packed at four bytes per pixel; the
    /// destination may be row-padded by CoreVideo.
    @discardableResult
    func publish(_ bytes: UnsafeRawPointer, width: Int, height: Int) -> Bool {
        guard width > 0, height > 0,
              width <= Self.maxDimension, height <= Self.maxDimension else { return false }

        lock.lock()
        guard let index = acquireSlot(width: width, height: height),
              CVPixelBufferLockBaseAddress(slots[index], CVPixelBufferLockFlags(rawValue: 0)) == kCVReturnSuccess,
              let base = CVPixelBufferGetBaseAddress(slots[index]) else {
            lock.unlock()
            return false
        }
        let destinationStride = CVPixelBufferGetBytesPerRow(slots[index])
        let source = bytes.assumingMemoryBound(to: UInt8.self)
        let sourceStride = width * 4
        for row in 0..<height {
            var src = source.advanced(by: row * sourceStride)
            var dst = base.advanced(by: row * destinationStride).assumingMemoryBound(to: UInt8.self)
            for _ in 0..<width {
                dst[0] = src[0] // blue
                dst[1] = src[1] // green
                dst[2] = src[2] // red
                dst[3] = 0xFF   // XRGB8888 has no alpha
                src = src.advanced(by: 4)
                dst = dst.advanced(by: 4)
            }
        }
        CVPixelBufferUnlockBaseAddress(slots[index], CVPixelBufferLockFlags(rawValue: 0))
        commit(index)
        lock.unlock()
        onFrame?(textureId)
        return true
    }

    /// Lends the locked base address and row stride to the runtime so a
    /// hardware-rendering core can write the frame directly into the
    /// IOSurface. Presenting happens after the closure returns.
    @discardableResult
    func withLockedBuffer<R>(width: Int, height: Int,
                             _ body: (UnsafeMutableRawPointer, Int) -> R) -> R? {
        guard width > 0, height > 0,
              width <= Self.maxDimension, height <= Self.maxDimension else { return nil }

        lock.lock()
        guard let index = acquireSlot(width: width, height: height),
              CVPixelBufferLockBaseAddress(slots[index], CVPixelBufferLockFlags(rawValue: 0)) == kCVReturnSuccess,
              let base = CVPixelBufferGetBaseAddress(slots[index]) else {
            lock.unlock()
            return nil
        }
        let stride = CVPixelBufferGetBytesPerRow(slots[index])
        let result = body(base, stride)
        CVPixelBufferUnlockBaseAddress(slots[index], CVPixelBufferLockFlags(rawValue: 0))
        commit(index)
        lock.unlock()
        onFrame?(textureId)
        return result
    }

    /// Caller holds `lock`. A dimension change rebuilds the pool; otherwise a
    /// free slot is chosen, falling back to an unread ready frame (dropping it)
    /// rather than waiting for Flutter.
    private func acquireSlot(width: Int, height: Int) -> Int? {
        if slots.count != Self.slotCount || self.width != width || self.height != height {
            slots.removeAll()
            for _ in 0..<Self.slotCount {
                guard let buffer = Self.makeBuffer(width: width, height: height) else { return nil }
                slots.append(buffer)
            }
            states = Array(repeating: .free, count: Self.slotCount)
            self.width = width
            self.height = height
            ready = nil
            presented = nil
            writing = nil
        }
        var chosen: Int?
        for index in 0..<Self.slotCount where states[index] == .free {
            chosen = index
            break
        }
        if chosen == nil {
            for index in 0..<Self.slotCount where states[index] == .ready {
                chosen = index
                break
            }
        }
        guard let index = chosen else { return nil }
        states[index] = .writing
        writing = index
        return index
    }

    /// Caller holds `lock`.
    private func commit(_ index: Int) {
        guard index < states.count, states[index] == .writing else { return }
        states[index] = .ready
        ready = index
        writing = nil
    }

    private static func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let options: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA,
                                         options as CFDictionary, &buffer)
        return status == kCVReturnSuccess ? buffer : nil
    }
}

/// Installs the shared texture bridge on the `ezcore/video` channel.
///
/// The two runners supply the registry calls in their own Flutter APIs; the
/// channel, the pixel pool and the frame conversion stay in one source file
/// so iOS and macOS cannot drift apart.
final class EzcoreVideoTextureBridge: NSObject {
    private let channel: FlutterMethodChannel
    private let register: (EzcoreVideoTexture) -> Int64
    private let frameAvailable: (Int64) -> Void
    private let unregister: (Int64) -> Void
    private let lock = NSLock()
    private var textures: [Int64: EzcoreVideoTexture] = [:]

    init(messenger: FlutterBinaryMessenger,
         register: @escaping (EzcoreVideoTexture) -> Int64,
         frameAvailable: @escaping (Int64) -> Void,
         unregister: @escaping (Int64) -> Void) {
        self.register = register
        self.frameAvailable = frameAvailable
        self.unregister = unregister
        self.channel = FlutterMethodChannel(name: "ezcore/video",
                                            binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterError(code: "video", message: "Bridge unavailable", details: nil))
                return
            }
            self.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "create":
            let texture = EzcoreVideoTexture()
            let id = register(texture)
            guard id != 0 else {
                result(FlutterError(code: "video", message: "Texture registration failed", details: nil))
                return
            }
            texture.bind(textureId: id, frameAvailable: frameAvailable)
            lock.lock()
            textures[id] = texture
            lock.unlock()
            result(["textureId": id])

        case "frame":
            guard let args = call.arguments as? [String: Any],
                  let id = Self.int64(args["textureId"]),
                  let pixels = args["pixels"] as? FlutterStandardTypedData,
                  let width = Self.intValue(args["width"]),
                  let height = Self.intValue(args["height"]),
                  let texture = texture(for: id) else {
                result(FlutterError(code: "video", message: "Invalid frame", details: nil))
                return
            }
            let ok = pixels.data.withUnsafeBytes { raw -> Bool in
                guard let base = raw.baseAddress else { return false }
                return texture.publish(base, width: width, height: height)
            }
            result(ok)

        case "release":
            guard let args = call.arguments as? [String: Any],
                  let id = Self.int64(args["textureId"]) else {
                result(FlutterError(code: "video", message: "Missing texture id", details: nil))
                return
            }
            lock.lock()
            let removed = textures.removeValue(forKey: id)
            lock.unlock()
            guard removed != nil else {
                result(false)
                return
            }
            unregister(id)
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func texture(for id: Int64) -> EzcoreVideoTexture? {
        lock.lock()
        defer { lock.unlock() }
        return textures[id]
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let integer = value as? Int { return Int64(integer) }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let integer = value as? Int { return integer }
        return nil
    }
}

import AVFoundation
import Flutter
import GameController
import UIKit

/// Physical gamepads (MFi / PS / Xbox over Bluetooth) translated to the
/// canonical ezcore/gamepad vocabulary (see lib/services/gamepad.dart).
/// Poll-on-change: the profile handler diffs pressed state and emits only
/// transitions; sticks arrive pre-thresholded as directional codes.
final class GamepadBridge {
  private let channel: FlutterMethodChannel
  private var pressed: Set<String> = []
  private var observations: [NSObjectProtocol] = []

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    let center = NotificationCenter.default
    observations = [
      center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
        guard let self = self, let controller = note.object as? GCController else { return }
        self.attach(controller)
      },
      center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
        guard let self = self else { return }
        self.pressed.removeAll()
        self.channel.invokeMethod("connection", arguments: ["connected": false, "name": ""])
      },
    ]
    if let controller = GCController.controllers().first {
      attach(controller)
    }
  }

  private func attach(_ controller: GCController) {
    channel.invokeMethod("connection", arguments: ["connected": true, "name": controller.vendorName ?? "Controller"])
    controller.extendedGamepad?.valueChangedHandler = { [weak self, weak controller] _, _ in
      guard let self = self, let controller = controller else { return }
      self.poll(controller)
    }
    poll(controller)
  }

  private func poll(_ controller: GCController) {
    guard let pad = controller.extendedGamepad else { return }
    var now: Set<String> = []
    func set(_ code: String, _ down: Bool) { if down { now.insert(code) } }
    set("a", pad.buttonA.isPressed)
    set("b", pad.buttonB.isPressed)
    set("x", pad.buttonX.isPressed)
    set("y", pad.buttonY.isPressed)
    set("lb", pad.leftShoulder.isPressed)
    set("rb", pad.rightShoulder.isPressed)
    set("lt", pad.leftTrigger.isPressed)
    set("rt", pad.rightTrigger.isPressed)
    set("start", pad.buttonMenu.isPressed)
    set("select", pad.buttonOptions?.isPressed ?? false)
    set("l3", pad.leftThumbstickButton?.isPressed ?? false)
    set("r3", pad.rightThumbstickButton?.isPressed ?? false)
    stick(now: &now, x: pad.dpad.xAxis.value, y: pad.dpad.yAxis.value)
    stick(now: &now, x: pad.leftThumbstick.xAxis.value, y: pad.leftThumbstick.yAxis.value)
    stick(now: &now, x: pad.rightThumbstick.xAxis.value, y: pad.rightThumbstick.yAxis.value)
    for code in now.subtracting(pressed) {
      channel.invokeMethod("button", arguments: ["code": code, "pressed": true])
    }
    for code in pressed.subtracting(now) {
      channel.invokeMethod("button", arguments: ["code": code, "pressed": false])
    }
    pressed = now
  }

  private func stick(now: inout Set<String>, x: Float, y: Float) {
    if x > 0.5 { now.insert("right") } else if x < -0.5 { now.insert("left") }
    if y > 0.5 { now.insert("down") } else if y < -0.5 { now.insert("up") }
  }
}

/// Device PCM sink for the `ezcore/audio` channel (AVAudioEngine, stereo).
/// Mirrors the macOS sink: bounded 150 ms queue, generation-guarded
/// completion accounting, main-queue confinement.
final class PcmAudioSink {
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var format: AVAudioFormat?
  private var queued = 0
  private var generation = 0

  func start(rate: Double) throws {
    stop()
    guard rate.isFinite, rate >= 8000, rate <= 192000,
          let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
      throw NSError(domain: "ezcore.audio", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid sample rate"])
    }
    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    try AVAudioSession.sharedInstance().setActive(true)
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    try engine.start()
    player.play()
    self.engine = engine
    self.player = player
    self.format = format
  }

  func write(_ data: Data) throws {
    guard let player = player, let format = format,
          data.count % 4 == 0, data.count <= 262144 else {
      throw NSError(domain: "ezcore.audio", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid PCM or output not started"])
    }
    if data.isEmpty { return }
    let frames = data.count / 4
    guard queued + frames <= Int(format.sampleRate * 0.15) else { return }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frames)), let channels = buffer.floatChannelData else { return }
    buffer.frameLength = AVAudioFrameCount(frames)
    data.withUnsafeBytes { raw in
      let bytes = raw.bindMemory(to: UInt8.self)
      for f in 0..<frames {
        for c in 0..<2 {
          let i = f * 4 + c * 2
          let sample = Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i+1]) << 8)
          channels[c][f] = Float(sample) / 32768.0
        }
      }
    }
    queued += frames
    let current = generation
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self = self, self.generation == current else { return }
        self.queued = max(0, self.queued - frames)
      }
    }
  }

  func stop() {
    generation += 1
    player?.stop()
    engine?.stop()
    player = nil; engine = nil; format = nil; queued = 0
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let audio = PcmAudioSink()
  private var gamepad: GamepadBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "ezcore/audio",
                                       binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      do {
        switch call.method {
        case "start":
          guard let args = call.arguments as? [String: Any],
                let rate = args["sampleRate"] as? Double else {
            result(FlutterError(code: "audio", message: "Missing sample rate", details: nil)); return
          }
          try self.audio.start(rate: rate)
        case "write":
          guard let data = call.arguments as? FlutterStandardTypedData else {
            result(FlutterError(code: "audio", message: "Missing PCM", details: nil)); return
          }
          try self.audio.write(data.data)
        case "stop": self.audio.stop()
        default: result(FlutterMethodNotImplemented); return
        }
        result(nil)
      } catch {
        result(FlutterError(code: "audio", message: error.localizedDescription, details: nil))
      }
    }
    // Packaged native locations: cores copy into ezcore-cores/ at archive
    // time (scripts/release.sh); the runtime links statically, so Dart
    // binds the current process instead of dlopening a path.
    let native = FlutterMethodChannel(name: "ezcore/native",
                                      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    native.setMethodCallHandler { call, result in
      switch call.method {
      case "bundledCoresDir":
        result(Bundle.main.bundlePath + "/ezcore-cores")
      case "runtimeRef":
        result(["kind": "process"])
      default: result(FlutterMethodNotImplemented)
      }
    }
    let padChannel = FlutterMethodChannel(name: "ezcore/gamepad",
                                          binaryMessenger: engineBridge.applicationRegistrar.messenger())
    gamepad = GamepadBridge(channel: padChannel)
  }
}

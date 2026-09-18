import Cocoa
import FlutterMacOS
import GameController

/// Physical gamepads (MFi / PS / Xbox over Bluetooth/USB) translated to the
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

/// Security-scoped bookmarks for user ROM files outside the sandbox.
/// Imported paths are bookmarked at import time; the player holds access
/// only for the duration of a session open. Saves, states, covers and
/// staged cores live inside the sandbox and never need bookmarks.
final class BookmarkStore {
  private var active: [String: URL] = [:]
  private let defaults = UserDefaults.standard
  private func key(for path: String) -> String { "ezcore.bookmark." + path }

  @discardableResult
  func saveBookmark(path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    guard let data = try? url.bookmarkData(options: .withSecurityScope,
                                           includingResourceValuesForKeys: nil,
                                           relativeTo: nil) else { return false }
    defaults.set(data, forKey: key(for: path))
    return true
  }

  func startAccess(path: String) -> Bool {
    if active[path] != nil { return true }
    guard let data = defaults.data(forKey: key(for: path)) else { return false }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                             relativeTo: nil, bookmarkDataIsStale: &stale),
          url.startAccessingSecurityScopedResource() else { return false }
    if stale {
      if let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                           includingResourceValuesForKeys: nil,
                                           relativeTo: nil) {
        defaults.set(fresh, forKey: key(for: path))
      }
    }
    active[path] = url
    return true
  }

  func stopAccess(path: String) {
    active[path]?.stopAccessingSecurityScopedResource()
    active.removeValue(forKey: path)
  }
}

class MainFlutterWindow: NSWindow {
  private let audio = PcmAudio()
  private let bookmarks = BookmarkStore()
  private var audioChannel: FlutterMethodChannel?
  private var gamepad: GamepadBridge?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(name: "ezcore/audio", binaryMessenger: flutterViewController.engine.binaryMessenger)
    audioChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      do {
        switch call.method {
        case "start":
          guard let args = call.arguments as? [String: Any], let rate = args["sampleRate"] as? Double else {
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
      } catch { result(FlutterError(code: "audio", message: error.localizedDescription, details: nil)) }
    }

    let files = FlutterMethodChannel(name: "ezcore/files", binaryMessenger: flutterViewController.engine.binaryMessenger)
    files.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "files", message: "Missing path", details: nil)); return
      }
      switch call.method {
      case "saveBookmark": result(self.bookmarks.saveBookmark(path: path))
      case "startAccess": result(self.bookmarks.startAccess(path: path))
      case "stopAccess": self.bookmarks.stopAccess(path: path); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }

    let padChannel = FlutterMethodChannel(name: "ezcore/gamepad", binaryMessenger: flutterViewController.engine.binaryMessenger)
    gamepad = GamepadBridge(channel: padChannel)

    super.awakeFromNib()
  }
}

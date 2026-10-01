import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'gamepad_linux.dart';
import 'gamepad_windows.dart';

/// Physical gamepad input, normalized to one vocabulary.
///
/// Platform runners translate OS events (Android KeyEvent, GCController on
/// Apple platforms, XInput/evdev shims) into method calls on the
/// `ezcore/gamepad` channel:
///
/// ```
/// button     {code: <code>, pressed: <bool>}
/// connection {connected: <bool>, name: <String>}
/// ```
///
/// Codes: `a b x y up down left right lb rb lt rt start select l3 r3`.
/// Analog sticks arrive pre-thresholded as directional codes, so every
/// platform behaves identically downstream. [toRetroPad] is the single
/// mapping into RetroPad ids 0-15 (mirrors the keyboard map in spirit:
/// Z=B, X=A on keyboard; pad A/B/X/Y map to their RetroPad namesakes).
class GamepadService {
  GamepadService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('ezcore/gamepad');

  /// The one app-wide instance screens subscribe to. There must be only
  /// one: each instance claims the platform channel's handler (the last one
  /// wins, and disposing one cleared it for everybody) and, on Linux, opens
  /// the input devices again. Subscribe with [onButton]/[onConnection] and
  /// cancel the subscription; never dispose the shared instance.
  static final GamepadService shared = GamepadService();

  final MethodChannel _channel;
  bool _listening = false;
  String? connectedPad;
  WindowsXInputPoller? _winPoller;
  LinuxEvdevPads? _linuxPads;

  /// Forget every button the host believes this poller sent, WITHOUT
  /// emitting a release.
  ///
  /// Needed because the host can clear input behind the poller's back: the C
  /// runtime's `ezcore_reset` and the worker's pause path both drop held
  /// buttons, while the poller only emits on *transitions*. Without this,
  /// a code still held physically is present in both the previous and the
  /// current poll, so no event is ever re-sent and the core reads the
  /// control as released until the user re-presses it.
  ///
  /// Emitting nothing here is deliberate: the host already cleared its own
  /// state, so a release would be a lie and would also mask the re-press.
  /// A no-op on every backend that has no held-set of its own.
  void forgetHeld() {
    _winPoller?.forgetHeld();
    _linuxPads?.forgetHeld();
  }

  /// RetroPad id for a canonical [code], or null to ignore.
  static int? toRetroPad(String code) => switch (code) {
        'b' => 0,
        'y' => 1,
        'select' => 2,
        'start' => 3,
        'up' => 4,
        'down' => 5,
        'left' => 6,
        'right' => 7,
        'a' => 8,
        'x' => 9,
        'lb' => 10,
        'rb' => 11,
        'lt' => 12,
        'rt' => 13,
        'l3' => 14,
        'r3' => 15,
        _ => null,
      };

  /// Subscribes to button events. Returns a cancel function.
  void Function() onButton(void Function(GamepadEvent event) handler) {
    _ensureListening();
    final sub = _events().listen(handler);
    return _counted(sub.cancel);
  }

  /// Subscribes to connection changes. Returns a cancel function.
  void Function() onConnection(void Function(bool connected, String name) handler) {
    _ensureListening();
    final sub = _connections().listen((e) => handler(e.$1, e.$2));
    return _counted(sub.cancel);
  }

  /// Device polling runs only while someone is subscribed: the last cancel
  /// stops it, the next subscription starts it again.
  int _subscribers = 0;

  void Function() _counted(Future<void> Function() cancel) {
    _subscribers++;
    var done = false;
    return () {
      if (done) return;
      done = true;
      cancel();
      if (--_subscribers == 0) _stopListening();
    };
  }

  void _stopListening() {
    if (!_listening) return;
    _listening = false;
    _winPoller?.stop();
    _winPoller = null;
    _linuxPads?.stop();
    _linuxPads = null;
    _channel.setMethodCallHandler(null);
  }

  final _connectionCtrl =
      StreamController<(bool, String)>.broadcast(sync: true);

  Stream<(bool, String)> _connections() => _connectionCtrl.stream;

  final _buttonCtrl = StreamController<GamepadEvent>.broadcast(sync: true);

  Stream<GamepadEvent> _events() => _buttonCtrl.stream;

  void _ensureListening() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler(_onCall);
    // Desktop platforms without a Runner channel push: poll natively and
    // feed the same streams (mobile + macOS arrive over the channel).
    if (Platform.isWindows) {
      _winPoller = WindowsXInputPoller()
        ..start(_emitButton, _emitConnection, _emitAxis);
    } else if (Platform.isLinux) {
      _linuxPads = LinuxEvdevPads()
        ..start(_emitButton, _emitConnection, null, _emitAxis);
    }
  }

  /// Analog stick motion: [GamepadAxisEvent.axis] is lx / ly / rx / ry and
  /// the value -1..1 with down/right positive, after a small dead zone so a
  /// resting stick reads exactly centred.
  void Function() onAxis(void Function(GamepadAxisEvent event) handler) {
    _ensureListening();
    final sub = _axisCtrl.stream.listen(handler);
    return _counted(sub.cancel);
  }

  final _axisCtrl = StreamController<GamepadAxisEvent>.broadcast(sync: true);

  /// Dead zone as a fraction of full travel; values past it are rescaled so
  /// the stick still reaches full scale.
  static const axisDeadZone = 0.12;

  static double applyDeadZone(double v) {
    final a = v.abs();
    if (a <= axisDeadZone) return 0;
    return v.sign * ((a - axisDeadZone) / (1 - axisDeadZone)).clamp(0.0, 1.0);
  }

  void _emitAxis(String axis, double value) {
    if (!_axisCtrl.isClosed) {
      _axisCtrl.add(GamepadAxisEvent(axis, applyDeadZone(value)));
    }
  }

  void _emitButton(String code, bool pressed) {
    if (!_buttonCtrl.isClosed) _buttonCtrl.add(GamepadEvent(code, pressed));
  }

  void _emitConnection(bool connected, String name) {
    connectedPad = connected ? name : null;
    if (!_connectionCtrl.isClosed) _connectionCtrl.add((connected, name));
  }

  Future<void> _onCall(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    switch (call.method) {
      case 'button':
        final code = args['code'] as String?;
        final pressed = args['pressed'] as bool?;
        if (code != null && pressed != null) {
          _buttonCtrl.add(GamepadEvent(code, pressed));
        }
      case 'axis':
        // Native backends (Android, Apple) report sticks the same way.
        final axis = args['axis'] as String?;
        final value = (args['value'] as num?)?.toDouble();
        if (axis != null && value != null) _emitAxis(axis, value);
      case 'connection':
        final connected = args['connected'] as bool? ?? false;
        final name = args['name'] as String? ?? 'Controller';
        connectedPad = connected ? name : null;
        _connectionCtrl.add((connected, name));
    }
  }

  void dispose() {
    _winPoller?.stop();
    _linuxPads?.stop();
    _channel.setMethodCallHandler(null);
    _buttonCtrl.close();
    _connectionCtrl.close();
  }
}

/// A normalized physical-button transition.
class GamepadAxisEvent {
  const GamepadAxisEvent(this.axis, this.value);
  final String axis; // lx | ly | rx | ry
  final double value; // -1..1, down/right positive

  /// (stick, axis) as libretro indexes them: stick 0 left / 1 right,
  /// axis 0 x / 1 y.
  (int, int)? get retro => switch (axis) {
    'lx' => (0, 0),
    'ly' => (0, 1),
    'rx' => (1, 0),
    'ry' => (1, 1),
    _ => null,
  };
}

class GamepadEvent {
  const GamepadEvent(this.code, this.pressed);
  final String code;
  final bool pressed;

  /// Mapped RetroPad id, or null when the code is unmapped.
  int? get retroPadId => GamepadService.toRetroPad(code);
}

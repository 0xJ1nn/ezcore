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

  final MethodChannel _channel;
  bool _listening = false;
  String? connectedPad;
  WindowsXInputPoller? _winPoller;
  LinuxEvdevPads? _linuxPads;

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
    return sub.cancel;
  }

  /// Subscribes to connection changes. Returns a cancel function.
  void Function() onConnection(void Function(bool connected, String name) handler) {
    _ensureListening();
    final sub = _connections().listen((e) => handler(e.$1, e.$2));
    return sub.cancel;
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
        ..start(_emitButton, _emitConnection);
    } else if (Platform.isLinux) {
      _linuxPads = LinuxEvdevPads()
        ..start(_emitButton, _emitConnection);
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
class GamepadEvent {
  const GamepadEvent(this.code, this.pressed);
  final String code;
  final bool pressed;

  /// Mapped RetroPad id, or null when the code is unmapped.
  int? get retroPadId => GamepadService.toRetroPad(code);
}

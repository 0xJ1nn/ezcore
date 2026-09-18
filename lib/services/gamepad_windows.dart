import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import '../emu/native_mem.dart';

/// Windows physical gamepads over XInput (`xinput1_4.dll`, Win 8+).
///
/// Polls pads 0-3 every 16 ms and emits canonical vocab transitions
/// (see lib/services/gamepad.dart). No plugins, no native code — plain
/// dart:ffi, constructed only on Windows.
class WindowsXInputPoller {
  WindowsXInputPoller({this._lib});

  DynamicLibrary? _lib;
  Timer? _timer;
  final _lastDirs = <int, Set<String>>{};
  final _connected = <int>{};
  bool _running = false;

  static const _deadzone = 12000;

  /// Button mask bits mapped to canonical codes.
  static const buttonCodes = <int, String>{
    0x0001: 'up',
    0x0002: 'down',
    0x0004: 'left',
    0x0008: 'right',
    0x0010: 'start',
    0x0020: 'select',
    0x0040: 'l3',
    0x0080: 'r3',
    0x0100: 'lb',
    0x0200: 'rb',
    0x1000: 'a',
    0x2000: 'b',
    0x4000: 'x',
    0x8000: 'y',
  };

  /// Pure helper: pressed codes for a button mask + trigger/stick state.
  static Set<String> codesFor({
    required int buttons,
    required int leftTrigger,
    required int rightTrigger,
    required int lx,
    required int ly,
    required int rx,
    required int ry,
  }) {
    final out = <String>{};
    for (final entry in buttonCodes.entries) {
      if (buttons & entry.key != 0) out.add(entry.value);
    }
    if (leftTrigger > 30) out.add('lt');
    if (rightTrigger > 30) out.add('rt');
    _stick(out, lx, ly);
    _stick(out, rx, ry);
    return out;
  }

  static void _stick(Set<String> out, int x, int y) {
    if (x > _deadzone) {
      out.add('right');
    } else if (x < -_deadzone) {
      out.add('left');
    }
    // Y is up-positive in XInput.
    if (y > _deadzone) {
      out.add('up');
    } else if (y < -_deadzone) {
      out.add('down');
    }
  }

  late final int Function(int, Pointer<Void>) _getState = _libOf().lookupFunction<
      Int32 Function(Uint32, Pointer<Void>),
      int Function(int, Pointer<Void>)>('XInputGetState');

  DynamicLibrary _libOf() {
    var lib = _lib;
    if (lib != null) return lib;
    for (final name in ['xinput1_4.dll', 'xinput1_3.dll', 'xinput9_1_0.dll']) {
      try {
        lib = DynamicLibrary.open(name);
        break;
      } catch (_) {}
    }
    if (lib == null) throw StateError('XInput unavailable');
    _lib = lib;
    return lib;
  }

  void start(void Function(String code, bool pressed) onButton,
      void Function(bool connected, String name) onConnection) {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      for (var pad = 0; pad < 4; pad++) {
        _poll(pad, onButton, onConnection);
      }
    });
  }

  void _poll(int pad, void Function(String, bool) onButton,
      void Function(bool, String) onConnection) {
    final state = mallocBytes(16);
    try {
      final rc = _getState(pad, state.cast());
      if (rc != 0) {
        if (_connected.remove(pad)) {
          onConnection(false, '');
        }
        _lastDirs.remove(pad);
        return;
      }
      if (_connected.add(pad)) {
        onConnection(true, 'XInput Pad ${pad + 1}');
      }
      final view = state.cast<Uint8>().asTypedList(16);
      final data = ByteData.sublistView(view);
      final buttons = data.getUint16(4, Endian.little);
      final lt = view[6];
      final rt = view[7];
      final lx = data.getInt16(8, Endian.little);
      final ly = data.getInt16(10, Endian.little);
      final rx = data.getInt16(12, Endian.little);
      final ry = data.getInt16(14, Endian.little);
      final now = codesFor(
        buttons: buttons,
        leftTrigger: lt,
        rightTrigger: rt,
        lx: lx,
        ly: ly,
        rx: rx,
        ry: ry,
      );
      final was = _lastDirs[pad] ?? const <String>{};
      for (final code in now.difference(was)) {
        onButton(code, true);
      }
      for (final code in was.difference(now)) {
        onButton(code, false);
      }
      _lastDirs[pad] = now;
    } catch (_) {
      // A single bad poll must never kill the loop; next tick retries.
    } finally {
      freeBytes(state);
    }
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }
}

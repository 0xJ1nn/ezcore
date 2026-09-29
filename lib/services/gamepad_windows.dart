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

  /// Stick deadzone, in raw XInput axis units.
  ///
  /// An `XINPUT_GAMEPAD` stick axis is a signed 16-bit value, so full scale
  /// is 32767 (positive) / 32768 (negative). This is 8000, i.e. ~24.4% of
  /// full scale. That is the right ballpark for a thumbstick: it is wide
  /// enough to swallow resting drift and sensor noise in a worn pad, but
  /// narrow enough that the inner quarter of travel stays usable. The old
  /// value of 12000 was 36.6% — a third of the stick's travel dead on every
  /// side, which read as a hole in the middle of the stick.
  ///
  /// The comparison is strictly greater-than, so the boundary is exact:
  /// |axis| == 8000 registers nothing, 8001 does.
  static const int stickDeadzone = 8000;

  /// Analog trigger threshold, in raw XInput trigger units.
  ///
  /// `bLeftTrigger` / `bRightTrigger` are unsigned bytes, so full scale is
  /// 255. 64 is 25.1% of full scale — a deliberate quarter pull, which is
  /// where a real press becomes unambiguous while everything below it (rest
  /// value plus drift) stays silent. The old value of 30 was 11.8%: a
  /// trigger merely resting at 40 from ordinary drift read as permanently
  /// pressed. This runtime has no analog passthrough (see
  /// runtime/src/runtime.c, which rejects every non-RETRO_DEVICE_JOYPAD
  /// device), so a trigger can only ever be on or off here — the threshold
  /// has to do the noise rejection alone.
  ///
  /// Strictly greater-than: 64 does not fire, 65 does.
  static const int triggerThreshold = 64;

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
    if (leftTrigger > triggerThreshold) out.add('lt');
    if (rightTrigger > triggerThreshold) out.add('rt');
    _stick(out, lx, ly);
    _stick(out, rx, ry);
    return out;
  }

  /// Pure helper: emit a release for every code in [held] and return the
  /// now-empty set, so a pad that goes away mid-press cannot leave a
  /// direction stuck down for the rest of the session.
  ///
  /// Order-independent: callers that need determinism should pass a sorted
  /// set. Never throws for an empty or null-ish input; a pad that held
  /// nothing emits nothing.
  static Set<String> releaseHeld(
    Set<String> held,
    void Function(String code, bool pressed) onButton,
  ) {
    for (final code in held) {
      onButton(code, false);
    }
    return <String>{};
  }

  /// Pure helper: directions implied by one stick's raw XInput axes.
  ///
  /// Public and side-effect-free so the deadzone boundary can be asserted
  /// without hardware. Axes are raw int16 (-32768..32767); Y is up-positive
  /// in XInput. Deflection past [stickDeadzone] on an axis yields exactly one
  /// direction; within the deadzone it yields none. Diagonals are two codes,
  /// which is the pre-existing behaviour.
  static Set<String> stickCodes(int x, int y) {
    final out = <String>{};
    _stick(out, x, y);
    return out;
  }

  static void _stick(Set<String> out, int x, int y) {
    if (x > stickDeadzone) {
      out.add('right');
    } else if (x < -stickDeadzone) {
      out.add('left');
    }
    // Y is up-positive in XInput.
    if (y > stickDeadzone) {
      out.add('up');
    } else if (y < -stickDeadzone) {
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
        // The pad stopped responding: release anything we still believe is
        // held BEFORE dropping the record, otherwise a direction held at
        // unplug time stays pressed forever.
        final held = _lastDirs[pad];
        if (held != null && held.isNotEmpty) {
          releaseHeld(held, onButton);
        }
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

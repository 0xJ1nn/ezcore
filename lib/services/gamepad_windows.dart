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

  /// Pure helper: the transition decision for one poll tick, given what this
  /// poller last emitted ([was]) and what the pad reports now ([now]).
  /// Returns `(presses, releases)` — the codes to emit this tick, in that
  /// order — so the diff is testable without an XInput DLL.
  ///
  /// This is the exact arithmetic the poller loop performs; it is extracted,
  /// not redesigned. After [forgottenHeld] ([was] emptied) an unchanged
  /// physical press shows up in [presses] again, which is what re-syncs the
  /// host after it dropped our input.
  static (Set<String>, Set<String>) tickTransitions(
    Set<String> was,
    Set<String> now,
  ) =>
      (now.difference(was), was.difference(now));

  /// Pure helper: the "the host dropped this input behind our back" reset.
  /// Returns a copy of [lastDirs] with every pad's held set emptied and every
  /// key preserved.
  ///
  /// Emits NOTHING, deliberately: the host already cleared its own state, so a
  /// second release would be a lie, and a release here would also mask the
  /// re-press. Takes no callback to make that guarantee structural.
  static Map<int, Set<String>> forgottenHeld(Map<int, Set<String>> lastDirs) =>
      Map<int, Set<String>>.of(lastDirs)
        ..updateAll((_, _) => <String>{});

  /// Forgets every held code for every pad, so the next poll treats what the
  /// pad still reports as new and re-emits it as pressed.
  ///
  /// Needed because the host can clear input behind the poller's back: the C
  /// runtime's `ezcore_reset` memsets `input_buttons`, and pausing flushes
  /// every port. Without this the frontend still believes the code is held, so
  /// it appears in both `was` and `now`, `now.difference(was)` is empty, and
  /// nothing is ever re-sent — the core then reads a physically held control
  /// as released until the player re-presses it.
  ///
  /// CALLER — NOT WIRED HERE, seam unverified: the UI-isolate owner of
  /// `GamepadService` that calls `PlayerController.setPaused(...)` /
  /// `reset()`. `GamepadService` keeps the poller in a private `_winPoller`
  /// field, so that owner needs a route to this method (or `GamepadService`
  /// needs a `forgetHeld()` that no-ops off Windows). The worker isolate
  /// cannot be the caller: it holds no reference to the poller.
  void forgetHeld() {
    // Compute BEFORE mutating: in a Dart cascade the sections run left to
    // right, so `_lastDirs..clear()..addAll(forgottenHeld(_lastDirs))` would
    // evaluate the argument against an already-cleared map and add nothing.
    // Every pad's held set becomes empty, so the next poll sees the code in
    // `now` but not in `was` and re-emits it as a fresh press. Nothing is
    // emitted here: the host already cleared its own state, so a release
    // would be a lie and would also mask the re-press.
    final emptied = forgottenHeld(_lastDirs);
    _lastDirs
      ..clear()
      ..addAll(emptied);

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
      void Function(bool connected, String name) onConnection,
      [void Function(String stickAxis, double value)? onAxis]) {
    if (_running) return;
    _running = true;
    _onAxis = onAxis;
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
      // Analog values for cores that read sticks: XInput reports up as
      // positive, libretro down, so Y is inverted. Sent on change only.
      final axes = stickAxes(lx: lx, ly: ly, rx: rx, ry: ry);
      final last = _lastAxes[pad] ?? const <String, double>{};
      for (final e in axes.entries) {
        if (last[e.key] != e.value) _onAxis?.call(e.key, e.value);
      }
      _lastAxes[pad] = axes;
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
      final (presses, releases) = tickTransitions(was, now);
      for (final code in presses) {
        onButton(code, true);
      }
      for (final code in releases) {
        onButton(code, false);
      }
      _lastDirs[pad] = now;
    } catch (_) {
      // A single bad poll must never kill the loop; next tick retries.
    } finally {
      freeBytes(state);
    }
  }

  void Function(String stickAxis, double value)? _onAxis;
  final _lastAxes = <int, Map<String, double>>{};

  /// Pure helper: XInput thumbstick values as -1..1 with down/right
  /// positive (libretro's convention).
  static Map<String, double> stickAxes({
    required int lx,
    required int ly,
    required int rx,
    required int ry,
  }) {
    double n(int v) => (v / 32767).clamp(-1.0, 1.0);
    return {'lx': n(lx), 'ly': -n(ly), 'rx': n(rx), 'ry': -n(ry)};
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }
}

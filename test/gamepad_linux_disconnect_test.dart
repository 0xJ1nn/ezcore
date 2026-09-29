import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/gamepad_linux.dart';

/// Regression coverage for the Linux stuck-input-on-disconnect bug: when an
/// evdev node goes away (or errors) while a direction is held, `_pump`
/// used to discard the device without ever emitting `onButton(code, false)`,
/// leaving the core reading that direction as pressed for the rest of the
/// session.
///
/// These tests drive `LinuxEvdevPads.releaseOnDisconnect` directly — a pure
/// helper — so they need no `/dev/input/event*` node and no hardware.
void main() {
  test('disconnect releases every held button and stick direction', () {
    final emitted = <(String, bool)>[];
    // A pad holding a dpad button via a key code plus both stick axes
    // deflected, exactly as _EvdevDevice tracks them mid-session.
    final held = {'right', 'a', 'b'};
    final stickDirs = <String, String?>{
      'abs0': 'right',
      'abs1': null, // vertical axis centred: nothing to release
      'abs3': 'up',
    };

    final flushed = LinuxEvdevPads.releaseOnDisconnect(
      held,
      stickDirs,
      (code, pressed) => emitted.add((code, pressed)),
    );

    // Every code is flushed exactly once, with pressed == false.
    expect(emitted, hasLength(4));
    expect(emitted.toSet(), {
      ('a', false),
      ('b', false),
      ('right', false),
      ('up', false),
    });
    expect(emitted.every((e) => e.$2 == false), isTrue);
    // The null stick direction is never emitted as a code.
    expect(emitted.map((e) => e.$1), isNot(contains(null)));
    // Returned list is the flushed set, sorted for determinism.
    expect(flushed, ['a', 'b', 'right', 'up']);
    // Inputs are left intact (no surprise mutation of device state).
    expect(held, {'right', 'a', 'b'});
    expect(stickDirs, {'abs0': 'right', 'abs1': null, 'abs3': 'up'});
  });

  test('disconnect with nothing held emits nothing', () {
    final emitted = <(String, bool)>[];

    final flushed = LinuxEvdevPads.releaseOnDisconnect(
      const <String>{},
      const <String, String?>{'abs0': null, 'abs1': null},
      (code, pressed) => emitted.add((code, pressed)),
    );

    expect(emitted, isEmpty);
    expect(flushed, isEmpty);
  });

  test('a code in both the button and stick sets is released only once', () {
    // Stick directions are added to `held` too, so 'right' appears in both
    // collections; a naive two-loop flush would emit it twice.
    final emitted = <(String, bool)>[];
    final held = {'right', 'start'};
    final stickDirs = <String, String?>{'abs0': 'right', 'abs3': 'right'};

    LinuxEvdevPads.releaseOnDisconnect(
      held,
      stickDirs,
      (code, pressed) => emitted.add((code, pressed)),
    );

    expect(emitted, hasLength(2));
    expect(emitted.toSet(), {
      ('right', false),
      ('start', false),
    });
    expect(emitted.where((e) => e.$1 == 'right'), hasLength(1));
  });

  test('a full-face held set is fully flushed with no duplicates', () {
    final held = {
      'up', 'down', 'left', 'right',
      'start', 'select', 'l3', 'r3',
      'lb', 'rb', 'a', 'b', 'x', 'y',
      'lt', 'rt',
    };
    final emitted = <(String, bool)>[];

    final flushed = LinuxEvdevPads.releaseOnDisconnect(
      held,
      const <String, String?>{},
      (code, pressed) => emitted.add((code, pressed)),
    );

    expect(flushed, hasLength(held.length));
    final codes = emitted.map((e) => e.$1).toSet();
    expect(codes, held);
    expect(codes, hasLength(held.length)); // no code emitted twice
  });

  test('a pad that went away holding dpad-right flushes exactly that code', () {
    // The reported bug: user unplugs while holding 'right'.
    final emitted = <(String, bool)>[];

    final flushed = LinuxEvdevPads.releaseOnDisconnect(
      {'right'},
      const <String, String?>{'abs0': null, 'abs1': null},
      (code, pressed) => emitted.add((code, pressed)),
    );

    expect(emitted, [
      ('right', false),
    ]);
    expect(flushed, ['right']);
  });
}

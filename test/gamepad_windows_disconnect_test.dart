import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/gamepad_windows.dart';

/// Regression coverage for the stuck-input-on-disconnect bug: when an XInput
/// pad stops responding while a direction is held, the poller used to drop
/// `_lastDirs[pad]` without ever emitting `onButton(code, false)`, leaving the
/// core reading that direction as pressed for the rest of the session.
///
/// These tests drive `WindowsXInputPoller.releaseHeld` directly — a pure
/// helper — so they need no XInput DLL and no Windows host.
void main() {
  test('disconnect releases every held direction', () {
    final emitted = <(String, bool)>[];
    final held = {'left', 'right'};

    final remaining = WindowsXInputPoller.releaseHeld(
      held,
      (code, pressed) => emitted.add((code, pressed)),
    );

    // Exactly one release per held code, nothing else.
    expect(emitted, hasLength(2));
    expect(emitted.toSet(), {
      ('left', false),
      ('right', false),
    });
    // Every emission is a release, never a press.
    expect(emitted.every((e) => e.$2 == false), isTrue);
    // The helper hands back the now-empty set for _lastDirs to store/remove.
    expect(remaining, isEmpty);
    // The caller's set is left intact (no surprise mutation of the input).
    expect(held, {'left', 'right'});
  });

  test('disconnect with nothing held emits nothing', () {
    final emitted = <(String, bool)>[];

    final remaining = WindowsXInputPoller.releaseHeld(
      const <String>{},
      (code, pressed) => emitted.add((code, pressed)),
    );

    expect(emitted, isEmpty);
    expect(remaining, isEmpty);
  });

  test('a full-face held set is fully flushed with no duplicates', () {
    final held = {
      'up', 'down', 'left', 'right',
      'start', 'select', 'l3', 'r3',
      'lb', 'rb', 'a', 'b', 'x', 'y',
      'lt', 'rt',
    };
    final emitted = <(String, bool)>[];

    WindowsXInputPoller.releaseHeld(
      held,
      (code, pressed) => emitted.add((code, pressed)),
    );

    expect(emitted, hasLength(held.length));
    final codes = emitted.map((e) => e.$1).toSet();
    expect(codes, held);
    expect(codes, hasLength(held.length)); // no code emitted twice
  });

  test('releasing what a real mask reported held round-trips to nothing', () {
    // A pad reads as holding 'right' (mask 0x0008), then goes away.
    final was = WindowsXInputPoller.codesFor(
      buttons: 0x0008,
      leftTrigger: 0,
      rightTrigger: 0,
      lx: 0,
      ly: 0,
      rx: 0,
      ry: 0,
    );
    expect(was, {'right'});

    final emitted = <(String, bool)>[];
    final remaining = WindowsXInputPoller.releaseHeld(
      was,
      (code, pressed) => emitted.add((code, pressed)),
    );

    expect(emitted, [
      ('right', false),
    ]);
    expect(remaining, isEmpty);
  });
}

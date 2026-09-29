import 'package:ezcore/services/gamepad_windows.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the stale-held-set resync bug.
///
/// The poller emits only on TRANSITION, diffing against the previous poll's
/// set. The C runtime's `ezcore_reset` (and the worker's pause flush) clear
/// the host's `input_buttons` behind the frontend's back, so the frontend's
/// held set goes stale: the code is in BOTH `was` and `now`, the diff is empty,
/// and nothing is ever re-sent. The core then reads a physically held control
/// as released until the player releases and re-presses it.
///
/// The fix is `forgetHeld()` / `forgottenHeld()`: clear the frontend's held
/// set WITHOUT emitting (the host already released, so a second release would
/// be a lie), which makes the next identical poll a fresh press.
///
/// Pure helpers only — no XInput DLL, no Windows host, no hardware.
void main() {
  /// Mirrors what `WindowsXInputPoller._poll` does per tick, without the
  /// DLL: recompute `now`, diff against the stored set, store `now`.
  List<(String, bool)> poll(
    Map<int, Set<String>> lastDirs,
    int pad,
    Set<String> now,
  ) {
    final emitted = <(String, bool)>[];
    final was = lastDirs[pad] ?? const <String>{};
    final (presses, releases) = WindowsXInputPoller.tickTransitions(was, now);
    for (final code in presses) {
      emitted.add((code, true));
    }
    for (final code in releases) {
      emitted.add((code, false));
    }
    lastDirs[pad] = now;
    return emitted;
  }

  test('BUG: without forgetting, a held button is never re-sent', () {
    // Pad 0 reads as holding 'a' (mask 0x1000) and the frontend records it.
    final now = WindowsXInputPoller.codesFor(
      buttons: 0x1000,
      leftTrigger: 0,
      rightTrigger: 0,
      lx: 0,
      ly: 0,
      rx: 0,
      ry: 0,
    );
    expect(now, {'a'});
    final lastDirs = {0: now};

    // The host clears its input (ezcore_reset / pause flush). The player is
    // still physically holding 'a', so the pad keeps reporting it.
    final (presses, releases) =
        WindowsXInputPoller.tickTransitions(lastDirs[0]!, now);

    // Nothing to send: the transition was already emitted before the reset.
    expect(presses, isEmpty);
    expect(releases, isEmpty);
  });

  test('forgetHeld drops the held set so the next poll re-emits pressed', () {
    final now = WindowsXInputPoller.codesFor(
      buttons: 0x1000,
      leftTrigger: 0,
      rightTrigger: 0,
      lx: 0,
      ly: 0,
      rx: 0,
      ry: 0,
    );
    final lastDirs = {0: now};

    // The host dropped the input; the frontend is told to forget. No
    // callback is involved, so nothing can be emitted here.
    // Snapshot before clearing: a Dart cascade evaluates `clear()` first, so
    // the argument must be captured in a local.
    final next = WindowsXInputPoller.forgottenHeld(lastDirs);
    lastDirs
      ..clear()
      ..addAll(next);

    expect(lastDirs[0], isEmpty);
    expect(lastDirs.containsKey(0), isTrue);

    // Same physical state as before the reset.
    final emitted = poll(lastDirs, 0, now);
    expect(emitted, [('a', true)]);
    expect(lastDirs[0], {'a'});
  });

  test('forgetHeld emits NO spurious release, even for a full face', () {
    final held = {
      'up', 'down', 'left', 'right',
      'start', 'select', 'l3', 'r3',
      'lb', 'rb', 'a', 'b', 'x', 'y',
      'lt', 'rt',
    };
    final lastDirs = <int, Set<String>>{
      0: Set<String>.of(held),
      1: {'a'},
      2: {'b', 'start'},
    };

    final forgotten = WindowsXInputPoller.forgottenHeld(lastDirs);

    // Every pad key is preserved; every held set is emptied.
    expect(forgotten.keys.toSet(), unorderedEquals([0, 1, 2]));
    for (final codes in forgotten.values) {
      expect(codes, isEmpty);
    }
    // The caller's map and its sets are untouched (no surprise mutation).
    expect(lastDirs[0], unorderedEquals(held));
    expect(lastDirs[2], unorderedEquals(['b', 'start']));

    // Every code comes back as a press on the next poll — no release, ever.
    final emitted = <(String, bool)>[];
    for (final entry in forgotten.entries) {
      emitted.addAll(poll(forgotten, entry.key, entry.key == 0 ? held : lastDirs[entry.key]!));
    }
    expect(emitted, hasLength(held.length + 1 + 2));
    expect(emitted.every((e) => e.$2), isTrue);
  });

  test('forgetHeld on an empty poller is a no-op and safe', () {
    expect(WindowsXInputPoller.forgottenHeld(const {}), isEmpty);

    // The instance method is callable without an XInput DLL: the library is
    // resolved lazily on the first poll, so constructing and forgetting is
    // hardware-free.
    final poller = WindowsXInputPoller();
    poller.forgetHeld();
    poller.forgetHeld();
  });

  test('release and forget compose: released physically, no re-press', () {
    final lastDirs = <int, Set<String>>{0: {'left'}};

    // The host forgets our held set (reset/pause).
    // Snapshot before clearing: a Dart cascade evaluates `clear()` first, so
    // the argument must be captured in a local.
    final next = WindowsXInputPoller.forgottenHeld(lastDirs);
    lastDirs
      ..clear()
      ..addAll(next);

    // The player now genuinely lets go, so the pad reports nothing.
    final released = poll(lastDirs, 0, const <String>{});
    expect(released, isEmpty, reason: 'nothing held, nothing to release');
    expect(lastDirs[0], isEmpty);

    // And pressing again still works as a normal transition.
    expect(poll(lastDirs, 0, {'left'}), [('left', true)]);
  });
}

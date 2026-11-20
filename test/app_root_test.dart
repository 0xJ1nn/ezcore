import 'package:ezcore/main.dart';
import 'package:ezcore/services/ui_sounds.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shell owns two app-wide behaviours the design asks for: the persisted
/// accessibility preferences reach every screen, and keyboard select/back
/// reach the same cue bridge as the pad.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the root bridge applies text scale and reduced motion everywhere', (
    tester,
  ) async {
    final state = AppState.ephemeral();
    late MediaQueryData seen;
    await tester.pumpWidget(
      MaterialApp(
        home: AccessibilityBridge(
          state: state,
          child: Builder(
            builder: (context) {
              seen = MediaQuery.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(seen.textScaler.scale(100), 100);
    expect(seen.disableAnimations, isFalse);

    await state.setSetting('textScale', 130);
    await tester.pump();
    expect(seen.textScaler.scale(100), 130);

    await state.setSetting('reduceMotion', true);
    await tester.pump();
    expect(seen.disableAnimations, isTrue);

    await state.removeSetting('reduceMotion');
    await tester.pump();
    expect(seen.disableAnimations, isFalse);
  });

  test('the shell key hook publishes keyboard select and back cues', () async {
    final sounds = UiSounds(gameRunning: () => false)
      ..configure(enabled: false);
    final cues = <UiCue>[];
    sounds.events.listen((event) => cues.add(event.cue));

    KeyDownEvent down(LogicalKeyboardKey key, PhysicalKeyboardKey physical) =>
        KeyDownEvent(
          logicalKey: key,
          physicalKey: physical,
          timeStamp: Duration.zero,
        );

    shellKeyEvent(
      down(LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter),
      sounds,
    );
    shellKeyEvent(
      down(LogicalKeyboardKey.space, PhysicalKeyboardKey.space),
      sounds,
    );
    shellKeyEvent(
      down(LogicalKeyboardKey.escape, PhysicalKeyboardKey.escape),
      sounds,
    );
    shellKeyEvent(
      down(LogicalKeyboardKey.backspace, PhysicalKeyboardKey.backspace),
      sounds,
    );
    await Future<void>.delayed(Duration.zero);

    expect(cues, [UiCue.select, UiCue.select, UiCue.back, UiCue.back]);
  });
}

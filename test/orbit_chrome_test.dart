// The OS bar's status corner shows only what is true: the last input used
// and the clock. The hint row follows the same glyph state.
import 'package:ezcore/state/input_mode.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/hint_row.dart';
import 'package:ezcore/widgets/orbit_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('clock and the last input used', (t) async {
    final input = InputModeController();
    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: OrbitStatus(
            input: input,
            now: () => DateTime(2026, 10, 2, 9, 5),
          ),
        ),
      ),
    );
    expect(find.text('09:05'), findsOneWidget);
    expect(find.text('Keyboard'), findsOneWidget);

    input.notePad('Xbox Wireless Controller');
    await t.pump();
    expect(find.text('Xbox controller'), findsOneWidget);
    expect(find.text('Keyboard'), findsNothing);

    input.noteMouse();
    await t.pump();
    expect(find.text('Mouse'), findsOneWidget);
  });

  testWidgets('key hints list each key and what it does', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: const Scaffold(
          body: OrbitKeyHints(
            hints: [
              (['←', '→'], 'Browse'),
              (['1–4'], 'Switch space'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('1–4'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('hint row switches glyphs with the input', (t) async {
    final input = InputModeController();
    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: ListenableBuilder(
              listenable: input,
              builder: (context, _) =>
                  HintRow(hints: hintsForPage('library', input.glyphs)),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('[ ]'), findsOneWidget);

    input.notePad('PlayStation Controller');
    await t.pump();
    expect(find.text('✕'), findsOneWidget);
    expect(find.text('L1 R1'), findsOneWidget);
    expect(find.text('Enter'), findsNothing);

    input.notePad('Nintendo Switch Pro');
    await t.pump();
    expect(find.text('−'), findsOneWidget);
    expect(find.text('L R'), findsOneWidget);
  });

  test('pad family comes from the device name', () {
    expect(padFamilyForName('Xbox Wireless Controller'), PadFamily.xbox);
    expect(
      padFamilyForName('DualSense Wireless Controller'),
      PadFamily.playstation,
    );
    expect(
      padFamilyForName('Nintendo Switch Pro Controller'),
      PadFamily.nintendo,
    );
    expect(padFamilyForName(null), PadFamily.xbox);
  });
}

// Handoff §9: the reusable overlay kit. These tests lock the toast, dialog
// and options-sheet geometry, colour, motion, focus order and return values
// without depending on any screen wiring.
import 'package:ezcore/theme/symbols.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/orbit_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bare host with one button so the show helpers have a real context.
Widget _host(void Function(BuildContext) open) => MaterialApp(
  theme: Tokens.theme(),
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => open(context),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester t) async {
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 320));
}

void main() {
  group('toast', () {
    testWidgets('is a 52 px pill with a filled icon, message and Undo', (
      t,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Scaffold(
            body: Center(
              child: OrbitToast(
                message: 'Lanterns of Vell removed',
                icon: Symbols.delete,
                onUndo: () {},
                undoGlyph: 'Y',
              ),
            ),
          ),
        ),
      );

      expect(t.getSize(find.byType(OrbitToast)).height, 52);
      expect(find.text('Lanterns of Vell removed'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.text('Y'), findsOneWidget);
      final icon = t.widget<Icon>(find.byIcon(Symbols.delete));
      expect(icon.size, 21);
      expect(icon.fill, 1);
      final message = t.widget<Text>(find.text('Lanterns of Vell removed'));
      expect(message.style?.fontSize, 15);
      expect(message.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('rises 14 px, then hides itself after 2.6 s', (t) async {
      await t.pumpWidget(
        _host(
          (context) => showOrbitToast(
            context,
            message: 'Saved to slot one',
            icon: Symbols.save,
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pump();

      final start = t.getTopLeft(find.text('Saved to slot one')).dy;
      await t.pump(const Duration(milliseconds: 320));
      final end = t.getTopLeft(find.text('Saved to slot one')).dy;
      expect(start - end, closeTo(14, 0.5));

      await t.pump(const Duration(milliseconds: 2300));
      expect(find.text('Saved to slot one'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(find.text('Saved to slot one'), findsNothing);
    });

    testWidgets('stays 6 s with Undo and runs the callback', (t) async {
      var undone = 0;
      await t.pumpWidget(
        _host(
          (context) => showOrbitToast(
            context,
            message: 'Snapshot deleted',
            icon: Symbols.delete,
            onUndo: () => undone++,
            undoGlyph: 'Y',
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pump();

      await t.pump(const Duration(milliseconds: 2720));
      expect(find.text('Snapshot deleted'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 3400));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(find.text('Snapshot deleted'), findsNothing);

      await t.pumpWidget(
        _host(
          (context) => showOrbitToast(
            context,
            message: 'Snapshot deleted',
            icon: Symbols.delete,
            onUndo: () => undone++,
            undoGlyph: 'Y',
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pump();
      await t.tap(find.text('Undo'));
      await t.pump();
      expect(undone, 1);
      expect(find.text('Snapshot deleted'), findsNothing);
    });
  });

  group('dialog', () {
    testWidgets('is 600 wide, focuses the safe action, and returns false', (
      t,
    ) async {
      bool? result;
      await t.pumpWidget(
        _host((context) async {
          result = await showOrbitConfirmDialog(
            context,
            title: 'Remove Lanterns of Vell?',
            body:
                'It leaves your collection. The file stays in its folder and '
                'its snapshots stay in your time capsule.',
          );
        }),
      );
      await _open(t);

      expect(find.byType(OrbitDialog), findsOneWidget);
      expect(t.getSize(find.byType(OrbitDialog)).width, 600);
      expect(
        t
            .getSize(find.byKey(const ValueKey('orbit-dialog-action-Keep it')))
            .height,
        52,
      );
      expect(find.text('Remove Lanterns of Vell?'), findsOneWidget);
      expect(
        t.widget<ModalBarrier>(find.byType(ModalBarrier).last).color,
        Tokens.scrim.withValues(alpha: 0.72),
      );

      // Enter activates whatever has focus: the safe choice, not Remove.
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(result, isFalse);
      expect(find.byType(OrbitDialog), findsNothing);
    });

    testWidgets('danger action returns true', (t) async {
      bool? result;
      await t.pumpWidget(
        _host((context) async {
          result = await showOrbitConfirmDialog(
            context,
            title: 'Remove Lanterns of Vell?',
            body: 'The file stays in its folder.',
          );
        }),
      );
      await _open(t);
      await t.tap(find.text('Remove'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(result, isTrue);
    });

    testWidgets('error variant shakes -10, 8, -5, 3 px over 360 ms', (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Scaffold(
            body: Center(
              child: OrbitDialog(
                title: 'Game stopped',
                body: 'A recovered snapshot is ready.',
                icon: Symbols.error,
                tone: OrbitDialogTone.danger,
                error: true,
                actions: const [
                  OrbitDialogAction(
                    label: 'Got it',
                    kind: OrbitDialogActionKind.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final x0 = t.getTopLeft(find.text('Game stopped')).dx;

      await t.pump(const Duration(milliseconds: 72)); // 20%
      expect(
        t.getTopLeft(find.text('Game stopped')).dx - x0,
        closeTo(-10, 0.5),
      );
      await t.pump(const Duration(milliseconds: 72)); // 40%
      expect(t.getTopLeft(find.text('Game stopped')).dx - x0, closeTo(8, 0.5));
      await t.pump(const Duration(milliseconds: 72)); // 60%
      expect(t.getTopLeft(find.text('Game stopped')).dx - x0, closeTo(-5, 0.5));
      await t.pump(const Duration(milliseconds: 72)); // 80%
      expect(t.getTopLeft(find.text('Game stopped')).dx - x0, closeTo(3, 0.5));
      await t.pump(const Duration(milliseconds: 72)); // 100%
      expect(t.getTopLeft(find.text('Game stopped')).dx - x0, closeTo(0, 0.5));
    });
  });

  group('options sheet', () {
    testWidgets('is 560 wide with 54 px rows, a danger row and 0.6 scrim', (
      t,
    ) async {
      Object? selected;
      await t.pumpWidget(
        _host((context) async {
          selected = await showOrbitOptionsSheet<String>(
            context,
            title: 'Lanterns of Vell',
            subtitle: 'Nintendo DS · 64.0 MB',
            items: const [
              OrbitSheetItem(
                label: 'Resume',
                icon: Symbols.playArrow,
                value: 'resume',
              ),
              OrbitSheetItem(
                label: 'Details and snapshots',
                icon: Symbols.info,
                value: 'details',
              ),
              OrbitSheetItem(
                label: 'Remove from collection',
                icon: Symbols.delete,
                value: 'remove',
                danger: true,
              ),
            ],
          );
        }),
      );
      await _open(t);

      expect(find.byType(OrbitOptionsSheet), findsOneWidget);
      expect(t.getSize(find.byType(OrbitOptionsSheet)).width, 560);
      expect(
        t.getSize(find.byKey(const ValueKey('orbit-sheet-row-Resume'))).height,
        54,
      );
      expect(
        t
            .getSize(
              find.byKey(
                const ValueKey('orbit-sheet-row-Remove from collection'),
              ),
            )
            .height,
        54,
      );
      expect(
        t.widget<ModalBarrier>(find.byType(ModalBarrier).last).color,
        Tokens.scrim.withValues(alpha: 0.6),
      );

      // The first row owns focus on open, so it carries the lit surface.
      final resume = t.widget<AnimatedContainer>(
        find.byKey(const ValueKey('orbit-sheet-row-Resume')),
      );
      expect(
        (resume.decoration! as BoxDecoration).color,
        Color.alphaBlend(Tokens.text.withValues(alpha: 0.14), Tokens.toastBg),
      );
      final danger = t.widget<AnimatedContainer>(
        find.byKey(const ValueKey('orbit-sheet-row-Remove from collection')),
      );
      expect(
        (danger.decoration! as BoxDecoration).color,
        Tokens.danger.withValues(alpha: 0.08),
      );

      await t.tap(find.text('Resume'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(selected, 'resume');
      expect(find.byType(OrbitOptionsSheet), findsNothing);
    });

    testWidgets('Escape closes and returns null', (t) async {
      Object? selected = 'not-null';
      await t.pumpWidget(
        _host((context) async {
          selected = await showOrbitOptionsSheet<String>(
            context,
            title: 'Aurora Run',
            items: const [
              OrbitSheetItem(
                label: 'Resume',
                icon: Symbols.playArrow,
                value: 'resume',
              ),
            ],
          );
        }),
      );
      await _open(t);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(selected, isNull);
    });
  });
}

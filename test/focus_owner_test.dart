// T19: one focus owner. Each acceptance rule from handoff §4.1 has a test
// here — pointer-writes-focus, per-screen memory, the rail boundary, the dock
// return, modal trap and B, the safe confirm, key repeat, the stick dead zone,
// edge bump and the glyph switch within one input event.
import 'package:flutter/gestures.dart' show PointerDeviceKind;

import 'package:ezcore/state/input_mode.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/focus_glow.dart';
import 'package:ezcore/widgets/orbit_dialog.dart';
import 'package:ezcore/widgets/pad_navigator.dart';
import 'package:ezcore/services/gamepad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final owner = FocusOwner.shared;

  setUp(() {
    InputMode.shared.reset();
    owner.reset();
  });
  tearDown(() {
    owner.reset();
    InputMode.shared.reset();
  });

  Widget region(FocusNode node, String label) => Focus(
        focusNode: node,
        child: SizedBox(
          width: 120,
          height: 60,
          child: Center(child: Text(label)),
        ),
      );

  group('one owner', () {
    testWidgets('pointer hover writes to the same focus and shows one ring', (
      t,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(() => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic);
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Scaffold(
            body: Row(
              children: [
                FocusGlow(
                  focusId: 'first',
                  onTap: () {},
                  child: SizedBox(width: 80, height: 60),
                ),
                FocusGlow(
                  focusId: 'second',
                  onTap: () {},
                  child: SizedBox(width: 80, height: 60),
                ),
              ],
            ),
          ),
        ),
      );

      int rings() => t
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .where((c) {
            final border = (c.decoration as BoxDecoration?)?.border as Border?;
            return border?.top.color == Tokens.accentHi;
          })
          .length;

      expect(rings(), 0);
      // A mouse moving over the second tile is the only highlight that
      // appears: hover no longer owns a separate visual state.
      final second = t.widget<FocusGlow>(
        find.byWidgetPredicate((w) => w is FocusGlow && w.focusId == 'second'),
      );
      expect(second.focusId, 'second');
      final center = t.getCenter(
        find.byWidgetPredicate((w) => w is FocusGlow && w.focusId == 'second'),
      );
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await t.pump();
      await mouse.moveTo(center);
      await t.pump();
      expect(rings(), 1);
      await mouse.removePointer();
    });

    testWidgets('arrow keys move the one focus and switch glyphs in one event', (
      t,
    ) async {
      final first = FocusNode(debugLabel: 'left');
      final second = FocusNode(debugLabel: 'right');
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Focus(
            canRequestFocus: false,
            onKeyEvent: (node, event) => owner.onKey(event),
            child: Scaffold(
              body: Row(children: [region(first, 'A'), region(second, 'B')]),
            ),
          ),
        ),
      );
      first.requestFocus();
      await t.pump();
      InputMode.shared.notePad('DualSense');
      expect(InputMode.shared.glyph(OrbitAction.select), '✕');

      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(second));
      expect(InputMode.shared.glyph(OrbitAction.select), 'Enter',
          reason: 'the key press itself switched the hint set');
      owner.stopRepeat();
    });

    testWidgets('every rail destination restores its remembered focus', (t) async {
      final library = FocusNode(debugLabel: 'library item');
      final settings = FocusNode(debugLabel: 'settings item');
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Scaffold(
            body: Column(children: [region(library, 'L'), region(settings, 'S')]),
          ),
        ),
      );

      library.requestFocus();
      await t.pump();
      owner.remember(library);
      owner.setScreen('settings');
      await t.pump();
      settings.requestFocus();
      await t.pump();
      owner.remember(settings);

      owner.setScreen('library');
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(library));
      owner.setScreen('settings');
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(settings));
      // Coming back from the rail is the same path.
      owner.setScreen('library');
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(library));
    });

    testWidgets('left at the first column goes to the rail; right returns', (
      t,
    ) async {
      final rail = FocusNode(debugLabel: 'rail');
      final first = FocusNode(debugLabel: 'first column');
      final second = FocusNode(debugLabel: 'second column');
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Scaffold(
            body: Column(children: [
              // Offstage to directional traversal: the only way here is the
              // owner's explicit left-at-the-wall hand-off.
              Focus(focusNode: rail, child: const SizedBox.shrink()),
              Row(children: [region(first, 'A'), region(second, 'B')]),
            ]),
          ),
        ),
      );
      owner.attachRail(rail);
      first.requestFocus();
      await t.pump();
      owner.remember(first);

      expect(owner.move(TraversalDirection.left), isTrue);
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(rail));
      expect(owner.move(TraversalDirection.right), isTrue);
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(first));

      // A normal right inside the row still works.
      expect(owner.move(TraversalDirection.right), isTrue);
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(second));
      owner.detachRail(rail);
    });

    testWidgets('down to the dock and back lands on the selected cover', (
      t,
    ) async {
      final selected = FocusNode(debugLabel: 'selected cover');
      final firstCover = FocusNode(debugLabel: 'first cover');
      final dock = FocusNode(debugLabel: 'dock');
      final scope = FocusScopeNode(debugLabel: 'dock scope');
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Scaffold(
            body: Column(children: [
              Row(children: [region(firstCover, '1'), region(selected, '2')]),
              // A separate scope: a plain "up" cannot cross back into the
              // shelf, so the owner must aim at the selected cover itself.
              FocusScope(
                node: scope,
                child: region(dock, 'dock'),
              ),
            ]),
          ),
        ),
      );
      owner.setSelectedCover(selected);
      selected.requestFocus();
      await t.pump();
      owner.remember(selected);

      expect(owner.move(TraversalDirection.down), isTrue);
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(dock));
      expect(owner.move(TraversalDirection.up), isTrue);
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(selected),
          reason: 'the selected cover, not the first one');
    });

    testWidgets('a modal traps focus until it closes', (t) async {
      final opener = FocusNode(debugLabel: 'opener');
      final safe = FocusNode(debugLabel: 'safe button');
      final scope = FocusScopeNode(debugLabel: 'modal scope');
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Scaffold(
            body: Column(children: [
              region(opener, 'screen'),
              FocusScope(node: scope, child: region(safe, 'modal')),
            ]),
          ),
        ),
      );
      opener.requestFocus();
      await t.pump();
      owner.remember(opener);
      owner.openModal(opener: opener, scope: scope, safeFocus: safe);
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(safe));
      // A direction aimed at the screen below cannot escape the popup.
      owner.move(TraversalDirection.right, from: opener);
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(safe));
      owner.closeModal();
      await t.pump();
      expect(FocusManager.instance.primaryFocus, same(opener));
    });

    testWidgets('B closes a popup and returns focus to its opener', (t) async {
      final opener = FocusNode(debugLabel: 'opener');
      void Function(GamepadEvent)? send;
      final nav = GlobalKey<NavigatorState>();
      Future<void> open() => showOrbitDialog<int>(
            t.element(find.byType(OpenButton)),
            title: 'Title',
            body: 'Body',
            actions: const [
              OrbitDialogAction(label: 'OK', value: 1),
            ],
          );

      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          navigatorKey: nav,
          navigatorObservers: [focusRouteObserver],
          builder: (context, child) => PadNavigator(
            navigatorKey: nav,
            subscribe: (handler) {
              send = handler;
              return () {};
            },
            child: child!,
          ),
          home: Scaffold(
            body: Focus(
              focusNode: opener,
              child: OpenButton(open: open),
            ),
          ),
        ),
      );
      opener.requestFocus();
      await t.pump();
      owner.remember(opener);

      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(owner.modalOpen, isTrue, reason: 'the popup is a PopupRoute');

      send!(const GamepadEvent('b', true));
      await t.pumpAndSettle();
      expect(owner.modalOpen, isFalse);
      expect(FocusManager.instance.primaryFocus, same(opener),
          reason: 'B restored the focus of the element that opened it');
    });

    testWidgets('a confirm dialog focuses the non-destructive button', (
      t,
    ) async {
      Future<void> open() => showOrbitConfirmDialog(
            t.element(find.byType(OpenButton)),
            title: 'Remove this game?',
            body: 'It stays on your device.',
            confirmLabel: 'Remove',
            cancelLabel: 'Keep it',
          ).then((_) {});

      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Scaffold(body: OpenButton(open: open)),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();

      final safe = t.widget<AnimatedContainer>(
        find.byKey(const ValueKey('orbit-dialog-action-Keep it')),
      );
      final danger = t.widget<AnimatedContainer>(
        find.byKey(const ValueKey('orbit-dialog-action-Remove')),
      );
      expect((safe.decoration as BoxDecoration).boxShadow, isNotNull,
          reason: 'the safe button carries the focus halo');
      expect((danger.decoration as BoxDecoration).boxShadow, isNull,
          reason: 'the destructive button is not focused');
    });
  });

  group('repeat, sticks and edges', () {
    testWidgets('a held direction repeats after 380 ms then every 110 ms', (
      t,
    ) async {
      var moves = 0;
      final repeater = KeyRepeater(() => moves++);
      addTearDown(repeater.stop);
      repeater.start();
      expect(moves, 0);
      await t.pump(const Duration(milliseconds: 379));
      expect(moves, 0);
      await t.pump(const Duration(milliseconds: 1));
      expect(moves, 1);
      await t.pump(const Duration(milliseconds: 109));
      expect(moves, 1);
      await t.pump(const Duration(milliseconds: 1));
      expect(moves, 2);
      await t.pump(const Duration(milliseconds: 110));
      expect(moves, 3);
      repeater.stop();
      await t.pump(const Duration(milliseconds: 500));
      expect(moves, 3);
    });

    test('the analogue dead zone is 0.55', () {
      expect(FocusOwner.analogDeadZone, 0.55);
      expect(FocusOwner.directionFromStick(0.4, 0.3), isNull);
      expect(FocusOwner.directionFromStick(0.54, 0), isNull);
      expect(FocusOwner.directionFromStick(0.56, 0), TraversalDirection.right);
      expect(FocusOwner.directionFromStick(-0.8, 0), TraversalDirection.left);
      expect(FocusOwner.directionFromStick(0, -0.7), TraversalDirection.up);
      expect(FocusOwner.directionFromStick(0, 0.9), TraversalDirection.down);
    });

    test('the edge bump nudge measures 6-8 px over 140 ms', () {
      expect(FocusOwner.edgeNudge, inInclusiveRange(6, 8));
      expect(FocusOwner.edgeDuration, const Duration(milliseconds: 140));
    });

    testWidgets('an edge bump nudges the focused tile toward the wall', (
      t,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Scaffold(
            body: FocusGlow(
              focusId: 'edge',
              onTap: () {},
              child: const SizedBox(width: 80, height: 60),
            ),
          ),
        ),
      );
      Offset translation() {
        final transform = t.widget<Transform>(
          find.descendant(
            of: find.byType(FocusGlow),
            matching: find.byType(Transform),
          ).first,
        );
        final v = transform.transform.getTranslation();
        return Offset(v.x, v.y);
      }

      expect(translation(), Offset.zero);
      owner.edge.value = const EdgeSignal('edge', TraversalDirection.right, 1);
      await t.pump();
      // Just before the 140 ms is up, the nudge is at its full 7 px.
      await t.pump(const Duration(milliseconds: 139));
      expect(translation().dx, inInclusiveRange(6, FocusOwner.edgeNudge));
    });
  });

  group('glyphs follow the last input event', () {
    test('each family maps the seven actions (§4.3)', () {
      InputMode.shared.noteKeyboard();
      expect(InputMode.shared.glyphSet, OrbitGlyphSet.keyboard);
      expect(InputMode.shared.glyph(OrbitAction.select), 'Enter');
      expect(InputMode.shared.glyph(OrbitAction.back), 'Esc');
      expect(InputMode.shared.glyph(OrbitAction.options), 'Q');
      expect(InputMode.shared.glyph(OrbitAction.details), 'E');
      expect(InputMode.shared.glyph(OrbitAction.pause), 'P');
      expect(InputMode.shared.glyph(OrbitAction.switchSystem), '[ ]');
      expect(InputMode.shared.glyph(OrbitAction.changeLook), 'V');

      InputMode.shared.notePad('Xbox Wireless Controller');
      expect(InputMode.shared.glyph(OrbitAction.select), 'A');
      expect(InputMode.shared.glyph(OrbitAction.back), 'B');
      expect(InputMode.shared.glyph(OrbitAction.options), 'X');
      expect(InputMode.shared.glyph(OrbitAction.details), 'Y');

      InputMode.shared.notePad('DualSense Wireless Controller');
      expect(InputMode.shared.glyph(OrbitAction.select), '✕');
      expect(InputMode.shared.glyph(OrbitAction.back), '○');
      expect(InputMode.shared.glyph(OrbitAction.options), '□');
      expect(InputMode.shared.glyph(OrbitAction.details), '△');
      expect(InputMode.shared.glyph(OrbitAction.changeLook), 'CREATE');

      InputMode.shared.notePad('Nintendo Switch Pro Controller');
      expect(InputMode.shared.glyph(OrbitAction.select), 'A',
          reason: 'Nintendo confirms with the east button');
      expect(InputMode.shared.glyph(OrbitAction.back), 'B');
      expect(InputMode.shared.glyph(OrbitAction.options), 'Y');
      expect(InputMode.shared.glyph(OrbitAction.details), 'X');
      expect(InputMode.shared.glyph(OrbitAction.pause), '+');
      expect(InputMode.shared.glyph(OrbitAction.changeLook), '−');
    });

    test('one input event switches the set immediately', () {
      InputMode.shared.notePad('DualSense');
      InputMode.shared.noteKeyboard();
      expect(InputMode.shared.glyph(OrbitAction.select), 'Enter');
      // One pad event — no connection change, no extra frame — is enough.
      InputMode.shared.notePadActivity();
      expect(InputMode.shared.glyph(OrbitAction.select), '✕');
      InputMode.shared.notePointer();
      expect(InputMode.shared.glyph(OrbitAction.select), 'Enter');
    });
  });
}

/// A tiny button used by the modal tests: it opens a popup through the real
/// Navigator so the route observer sees it.
class OpenButton extends StatelessWidget {
  const OpenButton({super.key, required this.open});
  final Future<void> Function() open;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => open(),
        child: const Text('open'),
      );
}

// External controllers: remappable buttons, Select+Start for the pause
// menu, and a controller that can drive every menu.
import 'package:ezcore/services/gamepad.dart';
import 'package:ezcore/services/pad_mapping.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/widgets/pad_navigator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PadMapping', () {
    test('defaults press the natural RetroPad input', () {
      final m = PadMapping(AppState.ephemeral());
      expect(m.retroIdFor('b'), 0);
      expect(m.retroIdFor('a'), 8);
      expect(m.retroIdFor('lb'), 10);
      expect(m.retroIdFor('rt'), 13);
      expect(m.retroIdFor('guide'), isNull);
      expect(m.isDefault, isTrue);
    });

    test('assigning swaps, so no input is left unreachable', () async {
      final state = AppState.ephemeral();
      final m = PadMapping(state);
      await m.assign('a', 'b'); // controller A now presses RetroPad B
      expect(m.current['a'], 'b');
      expect(m.current['b'], 'a', reason: 'the old B button takes A');
      expect(m.isDefault, isFalse);
      // Only what changed is saved.
      expect(state.settings[padMappingKey], {'a': 'b', 'b': 'a'});
    });

    test('reset returns to the defaults', () async {
      final m = PadMapping(AppState.ephemeral());
      await m.assign('x', 'start');
      await m.reset();
      expect(m.isDefault, isTrue);
    });

    test('bad saved entries are ignored; bad assignments refused', () async {
      final state = AppState.ephemeral();
      await state.setSetting(padMappingKey, {'a': 'turbo', 'warp': 'b', 'x': 7});
      final m = PadMapping(state);
      expect(m.isDefault, isTrue);
      expect(() => m.assign('a', 'turbo'), throwsArgumentError);
    });
  });

  group('PadChord (Select + Start)', () {
    test('opens the menu once and swallows its own presses', () {
      final c = PadChord();
      expect(c.feed('select', true), ChordResult.pass);
      expect(c.feed('start', true), ChordResult.openMenu);
      expect(c.feed('start', false), ChordResult.swallow);
      expect(c.feed('start', true), ChordResult.swallow,
          reason: 'still part of the same chord');
      expect(c.feed('start', false), ChordResult.swallow);
      expect(c.feed('select', false), ChordResult.swallow);
      // Chord over: buttons reach the game again.
      expect(c.feed('start', true), ChordResult.pass);
      expect(c.feed('a', true), ChordResult.pass);
    });

    test('Start alone is just Start', () {
      final c = PadChord();
      expect(c.feed('start', true), ChordResult.pass);
      expect(c.feed('start', false), ChordResult.pass);
    });
  });

  group('PadNavigator', () {
    late void Function(GamepadEvent) send;
    void Function() subscribe(void Function(GamepadEvent) h) {
      send = h;
      return () {};
    }

    void press(String code) => send(GamepadEvent(code, true));

    Future<List<String>> pump(WidgetTester t) async {
      final taps = <String>[];
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(MaterialApp(
        navigatorKey: nav,
        builder: (c, child) =>
            PadNavigator(navigatorKey: nav, subscribe: subscribe, child: child!),
        home: Scaffold(
          body: Column(children: [
            TextButton(onPressed: () => taps.add('first'), child: const Text('first')),
            TextButton(onPressed: () => taps.add('second'), child: const Text('second')),
          ]),
        ),
      ));
      return taps;
    }

    testWidgets('the d-pad moves focus and A chooses', (t) async {
      final taps = await pump(t);
      press('down'); // nothing focused yet -> first control
      await t.pump();
      press('a');
      await t.pump();
      expect(taps, ['first']);
      press('down');
      await t.pump();
      press('a');
      await t.pump();
      expect(taps, ['first', 'second']);
    });

    testWidgets('B goes back', (t) async {
      await pump(t);
      final ctx = t.element(find.text('first'));
      Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('detail'))));
      await t.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      press('b');
      await t.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
    });

    testWidgets('while a game has the controller, menus ignore it',
        (t) async {
      final taps = await pump(t);
      padNavigationEnabled.value = false;
      addTearDown(() => padNavigationEnabled.value = true);
      press('down');
      press('a');
      await t.pump();
      expect(taps, isEmpty);
    });
  });

  test('there is one shared pad service', () {
    expect(identical(GamepadService.shared, GamepadService.shared), isTrue);
  });
}

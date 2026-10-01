// On-screen controls as data (ezcore.controls/1). The format is the contract
// a core package will ship against, so it is validated strictly; the
// built-in layouts are held to the same rules plus geometry a player can
// actually use; and the touch layer is driven with real pointer events.
import 'dart:convert';

import 'package:ezcore/controls/builtin_layouts.dart';
import 'package:ezcore/controls/control_layout.dart';
import 'package:ezcore/controls/control_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> minimal() => {
  'format': 'ezcore.controls/1',
  'id': 'demo',
  'name': 'Demo',
  'systems': ['gb'],
  'orientation': 'portrait',
  'screen': {'x': 0, 'y': 0, 'w': 1, 'h': 0.5},
  'controls': [
    {'id': 'a', 'type': 'button', 'input': 'a', 'x': 0.6, 'y': 0.6, 'w': 0.2, 'h': 0.2},
  ],
};

void main() {
  group('format validation', () {
    test('a minimal layout parses', () {
      final r = ControlLayout.parse(minimal());
      expect(r.errors, isEmpty);
      expect(r.layout!.controls.single.input, 'a');
    });

    List<String> errorsWith(void Function(Map<String, dynamic>) mutate) {
      final m = jsonDecode(jsonEncode(minimal())) as Map<String, dynamic>;
      mutate(m);
      return ControlLayout.parse(m).errors;
    }

    test('unknown fields are rejected, never ignored', () {
      expect(errorsWith((m) => m['script'] = 'alert(1)'), isNotEmpty);
      expect(errorsWith((m) => (m['controls'] as List).first['onPress'] = 'x'),
          isNotEmpty);
      expect(errorsWith((m) => m['shell'] = {'image': 'http://x/y.png'}),
          isNotEmpty);
    });

    test('only known inputs can be pressed', () {
      expect(errorsWith((m) => (m['controls'] as List).first['input'] = 'turbo'),
          isNotEmpty);
    });

    test('geometry must stay inside the player area', () {
      expect(errorsWith((m) => (m['controls'] as List).first['x'] = 0.95),
          isNotEmpty);
      expect(errorsWith((m) => (m['controls'] as List).first['w'] = 0),
          isNotEmpty);
      expect(errorsWith((m) => (m['screen'] as Map)['h'] = 1.5), isNotEmpty);
    });

    test('ids, labels, counts and formats are bounded', () {
      expect(errorsWith((m) => m['format'] = 'ezcore.controls/2'), isNotEmpty);
      expect(errorsWith((m) => m['id'] = '../escape'), isNotEmpty);
      expect(
          errorsWith((m) => (m['controls'] as List).first['label'] = 'x' * 13),
          isNotEmpty);
      expect(
          errorsWith((m) => m['controls'] = [
                for (var i = 0; i < 65; i++)
                  {'id': 'c$i', 'type': 'button', 'input': 'a', 'x': 0, 'y': 0, 'w': 0.01, 'h': 0.01},
              ]),
          isNotEmpty);
      expect(
          errorsWith((m) => (m['controls'] as List).add(
              {'id': 'a', 'type': 'button', 'input': 'b', 'x': 0, 'y': 0.8, 'w': 0.1, 'h': 0.1})),
          contains(contains('duplicate')));
    });
  });

  group('built-in layouts', () {
    final all = allBuiltinLayouts();

    test('every one is valid in the shipped format (round trip)', () {
      for (final l in all) {
        final r = ControlLayout.parse(jsonDecode(jsonEncode(l.toJson())));
        expect(r.errors, isEmpty, reason: l.id);
      }
    });

    test('no two controls overlap, and none covers the picture', () {
      for (final l in all) {
        final rects = [
          for (final c in l.controls) (c.id, c.rect.resolve(1000, 1000)),
        ];
        final screen = l.screen.rect.resolve(1000, 1000);
        for (var i = 0; i < rects.length; i++) {
          expect(rects[i].$2.overlaps(screen), isFalse,
              reason: '${l.id}: ${rects[i].$1} covers the picture');
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].$2.overlaps(rects[j].$2), isFalse,
                reason: '${l.id}: ${rects[i].$1} overlaps ${rects[j].$1}');
          }
        }
      }
    });

    test('every one has a Menu control, so touch can always leave a game', () {
      for (final l in all) {
        expect(l.controls.where((c) => c.input == 'menu'), hasLength(1),
            reason: l.id);
      }
    });

    test('families pick the right shape', () {
      final ds = builtinLayout('nds', portrait: true);
      expect(ds.screen.split, 2);
      expect(ds.shell.hinge, isNotNull);
      expect(builtinLayout('nds', portrait: false).screen.arrange, 'side');
      final psx = builtinLayout('psx', portrait: true);
      expect(psx.controls.map((c) => c.label), containsAll(['×', '○', 'L2']));
      expect(builtinLayout('no_such_system', portrait: true).id,
          'generic_portrait');
      expect(
        identical(builtinLayout('gba', portrait: true),
            builtinLayout('gba', portrait: true)),
        isTrue,
        reason: 'per-frame rebuilds must not look like a layout change',
      );
    });
  });

  group('picture placement', () {
    test('a single screen keeps its aspect inside the box', () {
      const s = ScreenSpec(rect: NormRect(0, 0, 1, 0.5));
      final r = pictureRects(s, const Size(400, 800), 256 / 240).single;
      expect(r.width / r.height, closeTo(256 / 240, 0.001));
      expect(r.width, lessThanOrEqualTo(400));
      expect(r.height, lessThanOrEqualTo(400));
    });

    test('a DS frame splits into two 4:3 screens, stacked or side by side',
        () {
      const stacked = ScreenSpec(
          rect: NormRect(0, 0, 1, 1), split: 2, arrange: 'stacked', gap: 0.05);
      final rs = pictureRects(stacked, const Size(300, 500), 256 / 384);
      expect(rs, hasLength(2));
      expect(rs[0].width / rs[0].height, closeTo(256 / 192, 0.001));
      expect(rs[1].top, greaterThan(rs[0].bottom));
      const side = ScreenSpec(
          rect: NormRect(0, 0, 1, 1), split: 2, arrange: 'side', gap: 0.05);
      final rl = pictureRects(side, const Size(800, 300), 256 / 384);
      expect(rl[1].left, greaterThan(rl[0].right));
    });
  });

  group('touch', () {
    final layout = ControlLayout.parse({
      ...minimal(),
      'controls': [
        {'id': 'dpad', 'type': 'dpad', 'x': 0.0, 'y': 0.5, 'w': 0.4, 'h': 0.4},
        {'id': 'b', 'type': 'button', 'input': 'b', 'x': 0.5, 'y': 0.6, 'w': 0.2, 'h': 0.2},
        {'id': 'a', 'type': 'button', 'input': 'a', 'x': 0.75, 'y': 0.6, 'w': 0.2, 'h': 0.2},
        {'id': 'menu', 'type': 'button', 'input': 'menu', 'x': 0.4, 'y': 0.0, 'w': 0.2, 'h': 0.05},
      ],
    }).layout!;

    Future<List<String>> pump(WidgetTester t, List<String> events,
        List<String> host) async {
      t.view.physicalSize = const Size(400, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(MaterialApp(
        home: ControlOverlay(
          layout: layout,
          onInput: (i, p) => events.add('$i:${p ? 'down' : 'up'}'),
          onHostInput: host.add,
        ),
      ));
      return events;
    }

    Offset at(double x, double y) => Offset(x * 400, y * 800);

    testWidgets('a tap presses and releases a button', (t) async {
      final ev = <String>[];
      await pump(t, ev, []);
      final g = await t.startGesture(at(0.85, 0.7));
      await g.up();
      expect(ev, ['a:down', 'a:up']);
    });

    testWidgets('sliding from B to A hands the press over', (t) async {
      final ev = <String>[];
      await pump(t, ev, []);
      final g = await t.startGesture(at(0.6, 0.7));
      await g.moveTo(at(0.85, 0.7));
      await g.up();
      expect(ev, ['b:down', 'b:up', 'a:down', 'a:up']);
    });

    testWidgets('two fingers hold two buttons at once', (t) async {
      final ev = <String>[];
      await pump(t, ev, []);
      final g1 = await t.startGesture(at(0.6, 0.7), pointer: 1);
      final g2 = await t.startGesture(at(0.85, 0.7), pointer: 2);
      expect(ev, ['b:down', 'a:down']);
      await g1.up();
      expect(ev.last, 'b:up');
      await g2.up();
      expect(ev.last, 'a:up');
    });

    testWidgets('the d-pad reads diagonals and rolls between directions',
        (t) async {
      final ev = <String>[];
      await pump(t, ev, []);
      // D-pad box: x 0..160, y 400..720 → square of 160 centred at (80,560).
      final g = await t.startGesture(const Offset(30, 510)); // up-left
      expect(ev, containsAll(['up:down', 'left:down']));
      ev.clear();
      await g.moveTo(const Offset(130, 510)); // up-right
      expect(ev, containsAll(['left:up', 'right:down']));
      expect(ev, isNot(contains('up:up')), reason: 'up stays held');
      await g.up();
    });

    testWidgets('Menu is a host action, sent once, never to the core',
        (t) async {
      final ev = <String>[];
      final host = <String>[];
      await pump(t, ev, host);
      final g = await t.startGesture(at(0.5, 0.02));
      await g.moveTo(at(0.52, 0.03));
      await g.up();
      expect(host, ['menu']);
      expect(ev, isEmpty);
    });
  });
}

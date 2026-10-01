// The game page: play or resume, saves with readable names, core choice,
// favourite and remove. And visible keyboard/controller focus on tiles.
import 'dart:convert';

import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/game_detail_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/focus_glow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

CoreManifest core(String id) => CoreManifest(
  id: id,
  name: id.toUpperCase(),
  version: '1',
  license: 'MIT',
  systems: const ['gba'],
  extensions: const ['gba'],
  cheatFamilies: const [],
  cheatsSupported: false,
  delivery: const {},
  artifacts: const {'x': 'p'},
);

void main() {
  Future<AppState> pump(WidgetTester t,
      {List<String> slots = const [], Size size = const Size(1280, 900)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final s = AppState.ephemeral();
    for (final c in [core('alpha'), core('beta')]) {
      s.registry.loadCatalog({c.id: jsonEncode(c.toJson())});
      s.registry.install(c, expectedSha256: 'p');
    }
    s.games = const [
      GameEntry(id: 'g', title: 'Metroid Fusion', system: 'gba',
          filePath: '/games/fusion.gba', extension: 'gba', coreId: 'alpha',
          lastPlayedMs: 1758000000000),
    ];
    for (final slot in slots) {
      await s.saves.upload('g', slot, Uint8List.fromList([1, 2, 3]));
    }
    await t.pumpWidget(MaterialApp(
      theme: Tokens.theme(),
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GameDetailScreen(gameId: 'g', state: s))),
          child: const Text('open'),
        ),
      )),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return s;
  }

  test('saves get readable names', () {
    expect(saveName('auto'), 'Automatic');
    expect(saveName('slot0'), 'Quick save');
    expect(saveName('slot-142233'), 'Saved 14:22:33');
    expect(saveName('custom'), 'custom');
  });

  testWidgets('no saves: Play, and an explanation', (t) async {
    await pump(t);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Resume'), findsNothing);
    expect(find.textContaining('No saves yet'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('an automatic save offers Resume and Play from start',
      (t) async {
    await pump(t, slots: ['auto', 'slot0', 'slot-101500']);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Play from start'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('Quick save'), findsOneWidget);
    expect(find.text('Saved 10:15:00'), findsOneWidget);
  });

  for (final size in const [Size(390, 844), Size(844, 390), Size(1280, 900)]) {
    testWidgets('no overflow at $size', (t) async {
      await pump(t, slots: ['auto', 'slot0'], size: size);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('deleting a save asks first', (t) async {
    final s = await pump(t, slots: ['slot0']);
    await t.tap(find.byTooltip('Delete save'));
    await t.pumpAndSettle();
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Delete'));
    await t.pumpAndSettle();
    expect(await s.saves.list('g'), isEmpty);
    expect(find.text('Quick save'), findsNothing);
  });

  testWidgets('choosing another core is remembered', (t) async {
    final s = await pump(t);
    await t.tap(find.textContaining('ALPHA'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('BETA').last);
    await t.pumpAndSettle();
    expect(s.games.single.coreId, 'beta');
  });

  testWidgets('favourite toggles; remove asks and keeps the file', (t) async {
    final s = await pump(t);
    await t.tap(find.byTooltip('Add to favourites'));
    await t.pump();
    expect(s.games.single.favorite, isTrue);
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove from library'));
    await t.pumpAndSettle();
    expect(find.textContaining('is not deleted'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Remove'));
    await t.pumpAndSettle();
    expect(s.games, isEmpty);
  });

  testWidgets('keyboard focus shows a ring and Enter activates', (t) async {
    var taps = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: FocusGlow(
            onTap: () => taps++,
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      ),
    ));
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    final box = t.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final border = (box.decoration as BoxDecoration).border as Border;
    expect(border.top.color, Tokens.accentHi, reason: 'focus ring visible');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(taps, 1);
  });
}

// Cheats screen: Orbit §8.8. The list and code panel present the real
// entries; validation blocks invalid codes; every action stays available.
import 'dart:convert';

import 'package:ezcore/models/cheat.dart';
import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/cheats_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

CoreManifest _core() => const CoreManifest(
  id: 'ds',
  name: 'DualScreen',
  version: '1.0.0',
  license: 'GPL-3.0',
  systems: ['nds'],
  extensions: ['nds'],
  cheatFamilies: ['nds_actionreplay'],
  cheatsSupported: true,
  delivery: {'macos': 'bundled'},
  artifacts: {'macos-arm64': 'p'},
);

const _cheats = [
  CheatEntry(
    index: 0,
    desc: 'Infinite health',
    code: '94000130 FCFF0000\n02123A4C 00000063\nD2000000 00000000',
    enabled: true,
  ),
  CheatEntry(
    index: 1,
    desc: 'Max gold',
    code: '0212F1B0 0098967F',
    enabled: true,
  ),
  CheatEntry(
    index: 2,
    desc: 'Walk through walls',
    code: '94000130 FDFF0000\n1210A6C2 00000001\nD2000000 00000000',
  ),
  CheatEntry(
    index: 3,
    desc: 'All maps unlocked',
    code: '94000130 FFFB0000\nZZ0012G8 00000001',
  ),
];

void main() {
  Future<AppState> pump(
    WidgetTester t, {
    Size size = const Size(1440, 900),
    List<CheatEntry> cheats = _cheats,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final state = AppState.ephemeral();
    final core = _core();
    state.registry.loadCatalog({core.id: jsonEncode(core.toJson())});
    state.registry.install(core, expectedSha256: 'p');
    state.games = const [
      GameEntry(
        id: 'g',
        title: 'Lanterns of Vell',
        system: 'nds',
        filePath: '/Games/g.nds',
        extension: 'nds',
        coreId: 'ds',
      ),
    ];
    state.cheatsByGame['g'] = cheats;

    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: CheatsScreen(gameId: 'g', state: state),
      ),
    );
    await t.pumpAndSettle();
    return state;
  }

  testWidgets('header, rows and the focused code panel match the design',
      (t) async {
    await pump(t);
    expect(find.text('CHEATS · NINTENDO DS'), findsOneWidget);
    expect(find.text('Lanterns of Vell'), findsOneWidget);
    expect(find.text('Infinite health'), findsOneWidget);
    expect(find.text('All maps unlocked'), findsOneWidget);
    expect(find.text('Action Replay DS · On'), findsNWidgets(2));
    expect(find.text('Action Replay DS · Off'), findsOneWidget);
    expect(find.text('Invalid code · can’t be turned on'), findsOneWidget);

    // The first row is focused, so its code fills the panel.
    expect(find.text('Action Replay DS'), findsOneWidget);
    expect(find.text('3 lines'), findsOneWidget);
    expect(
      find.text('94000130 FCFF0000\n02123A4C 00000063\nD2000000 00000000'),
      findsOneWidget,
    );
    expect(
      find.text('Import .cht file'),
      findsOneWidget,
    );
    expect(find.text('Add a code'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
  });

  testWidgets('a valid row toggles its code', (t) async {
    final state = await pump(t);
    expect(state.cheatsFor('g')[1].enabled, isTrue);
    await t.tap(find.text('Max gold'));
    await t.pumpAndSettle();
    expect(state.cheatsFor('g')[1].enabled, isFalse);
    expect(find.text('Action Replay DS · Off'), findsNWidgets(2));
  });

  testWidgets('keyboard activation toggles the focused row', (t) async {
    final state = await pump(t);
    // The first row autofocuses, as the design's focused halo shows.
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(state.cheatsFor('g')[0].enabled, isFalse);
  });

  testWidgets('an invalid code shows the error and cannot be enabled',
      (t) async {
    final state = await pump(t);
    await t.tap(find.text('All maps unlocked'));
    await t.pumpAndSettle();

    expect(state.cheatsFor('g')[3].enabled, isFalse);
    expect(
      find.textContaining('isn’t a valid Action Replay code'),
      findsOneWidget,
    );
    expect(find.text('2 lines'), findsOneWidget);
  });

  testWidgets('delete asks first and keeps the safe default', (t) async {
    final state = await pump(t);
    await t.longPress(find.text('Max gold'));
    await t.pumpAndSettle();
    expect(find.text('Delete Max gold?'), findsOneWidget);

    await t.tap(find.text('Keep'));
    await t.pumpAndSettle();
    expect(state.cheatsFor('g'), hasLength(4));

    await t.longPress(find.text('Max gold'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Delete'));
    await t.pumpAndSettle();
    expect(state.cheatsFor('g'), hasLength(3));
    expect(find.text('Max gold'), findsNothing);
  });

  testWidgets('empty state offers import and add', (t) async {
    await pump(t, cheats: const []);
    expect(find.text('No cheats for this game'), findsOneWidget);
    expect(
      find.text('Import a .cht file you have, or type a code.\n'
          'Nothing is looked up online.'),
      findsOneWidget,
    );
    expect(find.text('Import file'), findsOneWidget);
    expect(find.text('Add a code'), findsOneWidget);
    expect(find.text('Export'), findsNothing);
  });

  for (final size in const [Size(390, 844), Size(844, 390), Size(820, 1180)]) {
    testWidgets('fits $size', (t) async {
      await pump(t, size: size);
      expect(t.takeException(), isNull);
    });
  }
}

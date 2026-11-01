// The Cores screen (layout option A): cores named by the systems they play,
// an honest status, a trust label, and every action in the detail view.
import 'dart:convert';
import 'dart:io';

import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/core_manager_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CoreManifest core(
  String id,
  List<String> systems, {
  Map<String, String>? delivery,
  bool bios = false,
}) => CoreManifest(
  id: id,
  name: id[0].toUpperCase() + id.substring(1),
  version: '1.0',
  license: 'GPL-2.0-or-later',
  systems: systems,
  extensions: const ['bin'],
  cheatFamilies: const [],
  cheatsSupported: false,
  delivery: delivery ?? {Platform.operatingSystem: 'bundled'},
  artifacts: const {'x': 'pin'},
  biosRequired: bios,
  biosFiles: bios ? const ['scph1001.bin'] : const [],
);

void main() {
  AppState mk() {
    final s = AppState.ephemeral();
    final cores = [
      core('advancebit', ['gba', 'gb']),
      core('geometry1', ['psx'], bios: true),
      core(
        'dreamarc',
        ['dc'],
        delivery: {Platform.operatingSystem: 'download'},
      ),
      core('superfx', ['snes'], delivery: {Platform.operatingSystem: 'absent'}),
    ];
    s.registry.loadCatalog({
      for (final c in cores) c.id: jsonEncode(c.toJson()),
    });
    s.registry.install(cores[0], expectedSha256: 'pin');
    s.registry.install(cores[1], expectedSha256: 'pin');
    s.registry.addUserPackage(core('bluemsx', ['msx']));
    s.games = const [
      GameEntry(
        id: 'g',
        title: 'T',
        system: 'gb',
        filePath: '/t.gb',
        extension: 'gb',
        coreId: 'advancebit',
      ),
    ];
    return s;
  }

  Future<AppState> pump(
    WidgetTester t,
    Size size, {
    ValueChanged<String>? onBrowse,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final s = mk();
    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: CoreManagerScreen(state: s, onBrowseCore: onBrowse),
        ),
      ),
    );
    await t.pump();
    return s;
  }

  for (final size in const [Size(1280, 800), Size(390, 844), Size(844, 390)]) {
    testWidgets('card grid: no overflow at $size', (t) async {
      await pump(t, size);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Available'));
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('the Installed and Available tabs swap the card grid', (t) async {
    await pump(t, const Size(1280, 800));
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Game Boy Advance, Game Boy'), findsWidgets);
    await t.tap(find.text('Available'));
    await t.pump();
    expect(find.text('Game Boy Advance, Game Boy'), findsNothing);
    expect(find.text('Dreamcast'), findsWidgets);
  });

  testWidgets('cards name the console art they represent', (t) async {
    await pump(t, const Size(1280, 800));
    expect(find.text('CONSOLE ART\nadvancebit.webp'), findsWidgets);
  });

  testWidgets('cores are named by system, with status and trust', (t) async {
    await pump(t, const Size(1280, 800));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Game Boy Advance, Game Boy'), findsWidgets);
    expect(find.text('Ready · needs BIOS files'), findsOneWidget);
    // The detail panel opens on the first card and shows its Verified pill.
    expect(find.text('Verified'), findsOneWidget);
    // Trust is a detail-panel property, not card decoration.
    expect(find.text('Unverified'), findsNothing);
    await t.tap(find.text('msx'));
    await t.pump();
    expect(find.text('Unverified'), findsOneWidget, reason: 'user package');

    await t.tap(find.text('Available'));
    await t.pump();
    expect(find.text('Not installed · ready to install'), findsWidgets);
    expect(find.text('Not available on this device'), findsWidgets);
    expect(find.text('Install core from file'), findsOneWidget);
  });

  test('titles drop repeats and cap long lists', () {
    expect(
      coreTitle(core('cardcon', ['pce', 'tg16'])),
      'PC Engine / TurboGrafx-16',
    );
    expect(
      coreTitle(core('many', ['genesis', 'sms', 'gg', 'sg1000', 'scd'])),
      endsWith(' +2'),
    );
    expect(coreTitle(core('one', ['nds'])), 'Nintendo DS');
    expect(
      coreTitle(core('gb', ['gba', 'gb'])),
      'Game Boy Advance, Game Boy',
      reason: 'containing a name is not being that system',
    );
    expect(
      coreTitle(core('nes', ['nes', 'fds'])),
      'Nintendo Entertainment System',
      reason: 'the Disk System is an NES add-on, not a second system',
    );
  });

  testWidgets('wide screens show the detail beside the list', (t) async {
    String? browsed;
    await pump(t, const Size(1280, 800), onBrowse: (id) => browsed = id);
    await t.tap(find.text('PlayStation').first);
    await t.pump();
    expect(find.textContaining('scph1001.bin'), findsOneWidget);
    await t.tap(find.text('Show games'));
    await t.pump();
    expect(browsed, 'geometry1');
  });

  testWidgets('phone portrait turns the grid into a list of rows', (t) async {
    await pump(t, const Size(390, 844));
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
    // The 56 px rows carry the placeholder thumb without its technical label.
    expect(find.textContaining('CONSOLE ART'), findsNothing);
    expect(find.text('Game Boy Advance, Game Boy'), findsOneWidget);
    expect(find.text('Ready'), findsWidgets);
    // Installed / Available pills stay under the title on phones.
    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('phones open the detail as a bottom sheet', (t) async {
    await pump(t, const Size(390, 844));
    expect(find.text('Show games'), findsNothing);
    await t.tap(find.text('Game Boy Advance, Game Boy'));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Show games'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('phone rows swap with the Installed / Available tabs', (t) async {
    await pump(t, const Size(390, 844));
    expect(find.text('Ready'), findsWidgets);
    await t.tap(find.text('Available'));
    await t.pump();
    expect(find.text('Game Boy Advance, Game Boy'), findsNothing);
    expect(find.text('Dreamcast'), findsOneWidget);
    expect(find.text('Not installed · ready to install'), findsWidgets);
  });

  testWidgets('removing asks first and keeps games', (t) async {
    final s = await pump(t, const Size(1280, 800));
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(find.textContaining('Your games and saves stay'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Remove'));
    await t.pumpAndSettle();
    expect(s.registry.isInstalled('advancebit'), isFalse);
    expect(s.games, hasLength(1));
  });
}

// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

// T06: the four measured library looks, the V cycle, the shared selection,
// the look toast and the phone's look picker (design §8.1, Devices 4a/4b).
import 'dart:convert';

import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/home_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/collection_view.dart' show libraryViewKey;
import 'package:ezcore/widgets/cover_flow.dart';
import 'package:ezcore/widgets/game_dock.dart';
import 'package:ezcore/widgets/library_looks/grid_look.dart';
import 'package:ezcore/widgets/library_looks/library_cover.dart';
import 'package:ezcore/widgets/library_looks/list_look.dart';
import 'package:ezcore/widgets/library_looks/shelf_look.dart';
import 'package:ezcore/widgets/library_looks/wall_look.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _games = <GameEntry>[
  GameEntry(
    id: 'lanterns',
    title: 'Lanterns of Vell',
    system: 'nds',
    filePath: '/l.nds',
    extension: 'nds',
    coreId: 'dualscreen',
    year: 2008,
    lastPlayedMs: 1000,
    favorite: true,
    stateCount: 4,
    fileSize: 64 << 20,
  ),
  GameEntry(
    id: 'aurora',
    title: 'Aurora Run',
    system: 'gba',
    filePath: '/a.gba',
    extension: 'gba',
    coreId: 'advancebit',
    year: 2003,
    lastPlayedMs: 2000,
  ),
  GameEntry(
    id: 'starfall',
    title: 'Starfall Courier',
    system: 'gba',
    filePath: '/s.gba',
    extension: 'gba',
    coreId: 'advancebit',
    year: 2004,
    lastPlayedMs: 3000,
  ),
  GameEntry(
    id: 'turbo',
    title: 'Turbo Meadow',
    system: 'nes',
    filePath: '/t.nes',
    extension: 'nes',
    coreId: 'nesbyte',
    year: 1989,
    lastPlayedMs: 4000,
  ),
  GameEntry(
    id: 'cinder',
    title: 'Cinder & Moss',
    system: 'gb',
    filePath: '/c.gb',
    extension: 'gb',
    coreId: 'pocketbit',
    year: 1995,
    lastPlayedMs: 5000,
  ),
  GameEntry(
    id: 'tidal',
    title: 'Tidal Arcana',
    system: 'snes',
    filePath: '/t.sfc',
    extension: 'sfc',
    coreId: 'nesbyte',
    year: 1995,
    lastPlayedMs: 6000,
  ),
  GameEntry(
    id: 'iron',
    title: 'Ironvale 64',
    system: 'n64',
    filePath: '/i.z64',
    extension: 'z64',
    coreId: 'rcp64',
    year: 1999,
    lastPlayedMs: 7000,
  ),
  GameEntry(
    id: 'orbit',
    title: 'Quiet Orbit',
    system: 'psp',
    filePath: '/o.iso',
    extension: 'iso',
    coreId: 'portcomp',
    year: 2007,
    lastPlayedMs: 8000,
  ),
  GameEntry(
    id: 'comet',
    title: 'Pocket Comet',
    system: 'gbc',
    filePath: '/p.gbc',
    extension: 'gbc',
    coreId: 'pocketbit',
    year: 2000,
    lastPlayedMs: 9000,
    fileSize: 2 << 20,
  ),
  GameEntry(
    id: 'glass',
    title: 'Glasswing',
    system: 'psx',
    filePath: '/g.cue',
    extension: 'cue',
    coreId: 'geometry1',
    year: 1998,
  ),
  GameEntry(
    id: 'neon',
    title: 'Neon Harbor',
    system: 'dc',
    filePath: '/n.cdi',
    extension: 'cdi',
    coreId: 'dreamarc',
    year: 2000,
  ),
];

CoreManifest _core(String id, {List<String> biosFiles = const []}) =>
    CoreManifest(
      id: id,
      name: id,
      version: '1.0.0',
      license: 'GPL-2.0',
      systems: const ['nds'],
      extensions: const ['nds'],
      cheatFamilies: const [],
      cheatsSupported: false,
      delivery: const {'linux': 'bundled'},
      artifacts: const {'linux-x64': 'test-pin'},
      biosFiles: biosFiles,
    );

void main() {
  Future<AppState> pump(
    WidgetTester t, {
    Size size = const Size(1440, 900),
    String? look,
    List<GameEntry> library = _games,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final s = AppState.ephemeral()..games = List.of(library);
    for (final core in [
      _core('dualscreen'),
      _core('advancebit'),
      _core('nesbyte'),
      _core('pocketbit'),
      _core('nesbyte'),
      _core('rcp64'),
      _core('portcomp'),
      _core('geometry1', biosFiles: const ['scph5501.bin']),
    ]) {
      s.registry.loadCatalog({core.id: jsonEncode(core.toJson())});
      s.registry.install(core, expectedSha256: 'test-pin');
    }
    if (look != null) await s.setSetting(libraryViewKey, look);
    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: HomeScreen(state: s)),
      ),
    );
    await t.pump();
    if (look != null) await t.pumpAndSettle();
    return s;
  }

  testWidgets('V cycles all five looks and persists the choice', (t) async {
    final s = await pump(t);
    expect(find.byType(CoverFlow), findsOneWidget);
    const cycle = ['shelf', 'wall', 'grid', 'list', '3d'];
    for (final value in cycle) {
      await t.sendKeyEvent(LogicalKeyboardKey.keyV);
      await t.pump();
      expect(s.settings[libraryViewKey], value, reason: 'after V');
    }
    expect(s.settings.containsKey('libraryView'), isFalse);
  });

  testWidgets('each look uses its measured geometry', (t) async {
    await pump(t, look: 'shelf');
    expect(find.byType(ShelfLook), findsOneWidget);
    expect(find.text('Handhelds'), findsOneWidget);
    expect(find.text('Home consoles'), findsOneWidget);

    await pump(t, look: 'wall');
    expect(find.byType(WallLook), findsOneWidget);
    final cover = t.widget<LibraryCover>(find.byType(LibraryCover).first);
    // The prototype's CSS measures Wall covers at 156×208.
    expect(cover.width, 156);
    expect(cover.height, 208);

    await pump(t, look: 'grid');
    expect(find.byType(GridLook), findsOneWidget);
    final grid = t.widget<GridView>(find.byType(GridView).first);
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 8);
    expect(delegate.mainAxisSpacing, 24);

    await pump(t, look: 'list');
    expect(find.byType(ListLook), findsOneWidget);
    expect(find.text('SNAPSHOTS'), findsOneWidget);
    expect(find.text('2.0 MB'), findsOneWidget);
    // The tile's focus ring sits outside the measured 64 px row.
    final firstRow = find
        .descendant(
          of: find.byType(LookTile).first,
          matching: find.byType(Container),
        )
        .first;
    expect(t.getSize(firstRow).height, 64);
  });

  testWidgets('the selected game is shared across looks', (t) async {
    final s = await pump(t, look: 'grid');
    final aurora = find.byWidgetPredicate(
      (w) => w is LibraryCover && w.gameId == 'aurora',
    );
    await t.tap(aurora.first);
    await t.pump();
    String dockTitle() => t
        .widgetList<Text>(
          find.descendant(
            of: find.byType(GameDock),
            matching: find.byType(Text),
          ),
        )
        .map((w) => w.data)
        .whereType<String>()
        .firstWhere((d) => _games.any((g) => g.title == d), orElse: () => '');
    expect(dockTitle(), 'Aurora Run');
    await s.setSetting(libraryViewKey, 'list');
    await t.pump();
    expect(find.byType(ListLook), findsOneWidget);
    expect(dockTitle(), 'Aurora Run');
  });

  testWidgets('switching look shows the small Library look toast', (t) async {
    final s = await pump(t);
    await s.setSetting(libraryViewKey, 'shelf');
    await t.pump();
    expect(find.text('Library look: Shelf'), findsOneWidget);
  });

  testWidgets('missing core and BIOS get the design badges', (t) async {
    await pump(t, look: 'grid');
    expect(find.text('Needs core'), findsOneWidget);
    expect(find.text('Needs BIOS'), findsOneWidget);
  });

  testWidgets("the phone opens the five-look picker sheet", (t) async {
    final s = await pump(t, size: const Size(390, 844), look: 'list');
    expect(find.byType(ListLook), findsOneWidget);
    await t.tap(find.byTooltip('View options'));
    await t.pumpAndSettle();
    expect(find.text('Library look'), findsOneWidget);
    expect(find.text('Same games, five ways to browse.'), findsOneWidget);
    for (final label in ['3D shelf', 'Shelf', 'Wall', 'Grid', 'List']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await t.tap(find.text('Grid'));
    await t.pumpAndSettle();
    expect(s.settings[libraryViewKey], 'grid');
  });

  /// The design's never-played games run Hollow Spire, Glasswing, Neon Harbor;
  /// a plain recency sort leaves them alphabetical instead.
  final withSpire = <GameEntry>[
    ..._games,
    const GameEntry(
      id: 'spire',
      title: 'Hollow Spire',
      system: 'snes',
      filePath: '/h.sfc',
      extension: 'sfc',
      coreId: 'nesbyte',
      year: 1994,
    ),
  ];

  testWidgets('Wall and Grid list Hollow Spire before Glasswing', (t) async {
    for (final look in ['wall', 'grid']) {
      await pump(t, look: look, library: withSpire);
      final ids = t
          .widgetList<LibraryCover>(find.byType(LibraryCover))
          .map((w) => w.gameId)
          .toList();
      expect(
        ids.indexOf('spire'),
        lessThan(ids.indexOf('glass')),
        reason: look,
      );
      expect(ids.indexOf('glass'), lessThan(ids.indexOf('neon')), reason: look);
    }
  });

  testWidgets('the List look says Last week for a seven-day-old game', (
    t,
  ) async {
    final sevenDays =
        DateTime.now().millisecondsSinceEpoch - 7 * 24 * 3600 * 1000;
    await pump(
      t,
      look: 'list',
      library: [
        GameEntry(
          id: 'old',
          title: 'Old Game',
          system: 'nes',
          filePath: '/o.nes',
          extension: 'nes',
          coreId: 'nesbyte',
          lastPlayedMs: sevenDays,
        ),
      ],
    );
    expect(find.text('Last week'), findsOneWidget);
    expect(find.text('1 wk ago'), findsNothing);
  });

  testWidgets('the phone look picker has no sort footer', (t) async {
    await pump(t, size: const Size(390, 844), look: 'list');
    await t.tap(find.byTooltip('View options'));
    await t.pumpAndSettle();
    expect(find.textContaining('Sort:'), findsNothing);
  });

  testWidgets('the phone header keeps sorting outside the picker', (t) async {
    await pump(t, size: const Size(390, 844), look: 'grid');
    final title = t.getCenter(find.text('Library'));
    final gesture = await t.startGesture(title);
    await t.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await t.pumpAndSettle();
    expect(find.text('Sort: A–Z'), findsOneWidget);
  });
}

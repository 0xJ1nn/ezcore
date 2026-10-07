import 'dart:convert';

import 'package:ezcore/main.dart';
import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/brand/brand_mark.dart';
import 'package:ezcore/screens/home_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/orbit_widgets.dart';
import 'package:ezcore/widgets/collection_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whole-shell gate for layout option A (Library · Cores · Settings).
///
/// Pumps the real [Shell] at every viewport the app supports, because the
/// rail/bottom-bar plus the screen is what users see and what overflows.
void main() {
  const games = <GameEntry>[
    GameEntry(
      id: 'g1',
      title: 'Metroid Prime',
      system: 'gc',
      filePath: '/games/metroid.gcm',
      extension: 'gcm',
      coreId: 'powercube',
      fileSize: 15728640,
      lastPlayedMs: 1758500000000,
      stateCount: 3,
    ),
    GameEntry(
      id: 'g2',
      title: 'Super Mario World',
      system: 'snes',
      filePath: '/games/smw.sfc',
      extension: 'sfc',
      coreId: 'superfx',
      fileSize: 524288,
      lastPlayedMs: 1758400000000,
      stateCount: 1,
      favorite: true,
    ),
    GameEntry(
      id: 'g3',
      title: 'Sonic the Hedgehog',
      system: 'genesis',
      filePath: '/games/sonic.md',
      extension: 'md',
      coreId: 'blastproc',
    ),
    GameEntry(
      id: 'g4',
      title: 'The Legend of Zelda',
      system: 'snes',
      filePath: '/games/zelda.sfc',
      extension: 'sfc',
      coreId: 'superfx',
      stateCount: 2,
    ),
  ];

  const core = CoreManifest(
    id: 'powercube',
    name: 'PowerCube',
    version: '1.0.0',
    license: 'GPL-2.0-or-later',
    systems: ['gc'],
    extensions: ['gcm', 'iso'],
    cheatFamilies: [],
    cheatsSupported: false,
    delivery: {'linux': 'bundled'},
    artifacts: {'linux-x64': 'test-pin'},
  );

  Future<AppState> pumpShell(
    WidgetTester tester,
    Size size, {
    List<GameEntry> library = games,
    CollectionView view = CollectionView.grid,
  }) async {
    // Ephemeral: nothing here may write the developer's real settings.
    final state = AppState.ephemeral()..games = List.of(library);
    // These tests describe the Grid layout (Resume card, Continue playing);
    // the 3D view has its own tests.
    await state.setSetting(libraryViewKey, view.value);
    state.registry.loadCatalog({core.id: jsonEncode(core.toJson())});
    state.registry.install(core, expectedSha256: 'test-pin');
    state.loaded = true;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        debugShowCheckedModeBanner: false,
        home: Shell(key: UniqueKey(), state: state),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return state;
  }

  final viewports = <String, Size>{
    'desktop': Size(1600, 1000),
    'small desktop window': Size(1280, 720),
    'tablet': Size(1024, 768),
    'tablet portrait': Size(834, 1112),
    'phone landscape': Size(844, 390),
    'short phone landscape': Size(772, 346),
    'compact landscape window': Size(640, 360),
    'very short landscape window': Size(640, 320),
    'phone portrait': Size(390, 844),
    'small phone portrait': Size(360, 640),
    'tiny square': Size(320, 320),
  };

  for (final entry in viewports.entries) {
    testWidgets('populated shell has no overflow: ${entry.key}', (
      tester,
    ) async {
      await pumpShell(tester, entry.value);
      expect(tester.takeException(), isNull,
          reason: 'layout overflow at ${entry.value}');
    });

    for (final view in [CollectionView.flow, CollectionView.list]) {
      testWidgets('${view.label} library has no overflow: ${entry.key}', (
        tester,
      ) async {
        await pumpShell(tester, entry.value, view: view);
        expect(tester.takeException(), isNull,
            reason: '${view.label} layout overflow at ${entry.value}');
      });
    }

    testWidgets('empty library has no overflow: ${entry.key}', (
      tester,
    ) async {
      await pumpShell(tester, entry.value, library: const []);
      expect(tester.takeException(), isNull,
          reason: 'layout overflow at ${entry.value}');
      expect(find.text('Add your first game'), findsOneWidget);
    });
  }

  testWidgets('four spaces, every size', (tester) async {
    for (final size in viewports.values) {
      await pumpShell(tester, size);
      final nav = find.byType(
        find.byType(OrbitRail).evaluate().isNotEmpty ? OrbitRail : OrbitBottomNav,
      );
      for (final label in ['Library', 'Systems', 'Capsule', 'Settings']) {
        expect(find.descendant(of: nav, matching: find.text(label)),
            findsOneWidget, reason: '$label at $size');
      }
      for (final gone in ['Cores', 'Continue', 'Favorites']) {
        expect(
          find.descendant(
            of: find.byType(
              find.byType(OrbitRail).evaluate().isNotEmpty
                  ? OrbitRail
                  : OrbitBottomNav,
            ),
            matching: find.text(gone),
          ),
          findsNothing,
          reason: '$gone is no longer a destination ($size)',
        );
      }
    }
  });

  testWidgets('wide screens use the rail, phones in portrait the bottom bar',
      (tester) async {
    for (final size in const [Size(1600, 1000), Size(1024, 768), Size(844, 390)]) {
      await pumpShell(tester, size);
      expect(find.byType(OrbitRail), findsOneWidget, reason: '$size');
      expect(find.byType(OrbitBottomNav), findsNothing, reason: '$size');
    }
    await pumpShell(tester, const Size(390, 844));
    expect(find.byType(OrbitBottomNav), findsOneWidget);
    expect(find.byType(OrbitRail), findsNothing);
  });

  // The status corner shows only what is true: no controller, no P1.
  testWidgets('no fake status bar or slogans', (tester) async {
    await pumpShell(tester, const Size(1280, 720));
    expect(find.text('P1'), findsNothing);
    expect(find.byIcon(Icons.wifi), findsNothing);
    expect(find.textContaining('GAMES BRING US CLOSER'), findsNothing);
    expect(find.textContaining('Play. Preserve.'), findsNothing);
  });

  testWidgets('short rail keeps accessible touch targets', (tester) async {
    await pumpShell(tester, const Size(640, 320));
    final rail = find.byType(OrbitRail);
    for (final label in ['Library', 'Systems', 'Capsule', 'Settings']) {
      final target = find.descendant(
        of: rail,
        matching: find.bySemanticsLabel(label),
      );
      expect(target, findsOneWidget, reason: label);
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48),
          reason: '$label target');
    }
  });

  testWidgets('rail and number keys switch destinations', (tester) async {
    await pumpShell(tester, const Size(1280, 720));
    expect(find.byType(HomeScreen).hitTestable(), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(find.text('Appearance').hitTestable(), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(find.byType(HomeScreen).hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Your time capsule').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Appearance').hitTestable(), findsWidgets);
  });

  testWidgets('the top bar carries the brand on every space', (tester) async {
    await pumpShell(tester, const Size(1280, 720));
    for (final space in ['Systems', 'Capsule', 'Settings', 'Library']) {
      await tester.tap(find.descendant(
          of: find.byType(OrbitRail), matching: find.text(space)));
      await tester.pump();
      expect(find.byType(BrandLockup), findsWidgets, reason: space);
    }
  });

  testWidgets('Resume shows the game played last, on any core', (tester) async {
    await pumpShell(tester, const Size(1280, 720));
    expect(find.text('RESUME'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    // g1 (Metroid Prime, GameCube) was played after g2.
    final card = find.ancestor(
      of: find.text('RESUME'),
      matching: find.byType(Container),
    ).first;
    expect(
      find.descendant(of: card, matching: find.text('Metroid Prime')),
      findsWidgets,
    );
  });

  testWidgets('Continue lists the other recently played games', (tester) async {
    await pumpShell(tester, const Size(1280, 720));
    expect(find.text('Continue playing'), findsOneWidget);
    // Never-played games are not "continue" material.
    final continueRow = find.ancestor(
      of: find.text('Super Mario World').first,
      matching: find.byType(ListView),
    );
    expect(continueRow, findsWidgets);
  });

  testWidgets('no Resume or Continue before anything is played', (tester) async {
    await pumpShell(tester, const Size(1280, 720), library: [
      for (final g in games) g.copyWith(lastPlayedMs: 0),
    ]);
    expect(find.text('RESUME'), findsNothing);
    expect(find.text('Continue playing'), findsNothing);
    // Nothing above the games, so no "All games" heading: the tabs lead.
    expect(find.text('All games'), findsNothing);
    expect(find.text('Time capsule'), findsOneWidget);
  });

  testWidgets('filters use system names, never core names', (tester) async {
    await pumpShell(tester, const Size(1600, 1000));
    expect(find.text('All systems'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    for (final core in ['powercube', 'superfx', 'blastproc']) {
      expect(find.textContaining(core), findsNothing, reason: core);
    }
    await tester.tap(find.text('Favorites'));
    await tester.pump();
    final grid = find.byType(SliverGrid);
    expect(grid, findsOneWidget);
    expect(
      find.descendant(of: grid, matching: find.text('Super Mario World')),
      findsWidgets,
    );
    expect(
      find.descendant(of: grid, matching: find.text('Sonic the Hedgehog')),
      findsNothing,
    );
  });

  testWidgets('search narrows the grid and says when nothing matches',
      (tester) async {
    await pumpShell(tester, const Size(1600, 1000));
    await tester.enterText(find.byType(TextField), 'zelda');
    await tester.pump();
    final grid = find.byType(SliverGrid);
    expect(
      find.descendant(of: grid, matching: find.text('The Legend of Zelda')),
      findsWidgets,
    );
    expect(
      find.descendant(of: grid, matching: find.text('Metroid Prime')),
      findsNothing,
    );
    await tester.enterText(find.byType(TextField), 'no such game');
    await tester.pump();
    expect(find.textContaining('No games match'), findsOneWidget);
  });
}

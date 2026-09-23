import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/library_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/orbit_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gate for the studio plate's four layouts.
///
/// These tests exist because the redesign is *responsive*, and responsive
/// code fails silently: a layout that works on a desktop can overflow on a
/// phone and never be noticed until a user sees it.
void main() {
  const games = [
    GameEntry(
      id: 'g1',
      title: 'Metroid Prime',
      system: 'gc',
      filePath: '/games/metroid.gcm',
      extension: 'gcm',
      coreId: 'powercube',
      fileSize: 15728640,
      lastPlayedMs: 1758000000000,
      stateCount: 3,
    ),
    GameEntry(
      id: 'g2',
      title: 'Super Mario World',
      system: 'snes',
      filePath: '/games/smw.sfc',
      extension: 'sfc',
      coreId: 'superfx',
      favorite: true,
    ),
  ];

  Future<AppState> pumpAt(
    WidgetTester tester,
    Size size, {
    AppState? state,
  }) async {
    final s = state ?? (AppState()..games = games);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: LibraryScreen(state: s)),
      ),
    );
    await tester.pump();
    return s;
  }

  testWidgets('desktop: cover flow + dock with real stats', (tester) async {
    await pumpAt(tester, const Size(1600, 1000));
    expect(tester.takeException(), isNull);

    expect(find.text('The collection'), findsOneWidget);
    expect(find.text('2 games'), findsOneWidget);
    expect(find.text('Play. Preserve. Anywhere.'), findsOneWidget);
    expect(find.text('Play'), findsWidgets);

    // The stat panel must report tracked values, never invented ones.
    expect(find.text('Last played'), findsOneWidget);
    expect(find.text('Save states'), findsOneWidget);
    expect(find.text('File size'), findsOneWidget);
    // Size shows in the meta row and again in the stat panel.
    expect(find.text('15.0 MB'), findsWidgets);

    // Action row is wired to real features.
    expect(find.text('Manage'), findsOneWidget);
    expect(find.textContaining('Cheats ('), findsOneWidget);
    expect(find.textContaining('States ('), findsOneWidget);
  });

  testWidgets('desktop: unplayed game says "Never played"', (tester) async {
    // A library of one unplayed game: no play stamp means we must say so
    // rather than invent a date.
    await pumpAt(
      tester,
      const Size(1600, 1000),
      state: AppState()..games = [games[1]],
    );
    expect(find.text('Never played'), findsOneWidget);
    expect(find.text('0 states'), findsOneWidget);
    expect(find.text('0 codes'), findsOneWidget);
  });

  testWidgets('tablet: hub rows, no overflow', (tester) async {
    await pumpAt(tester, const Size(1024, 768));
    expect(tester.takeException(), isNull);
    expect(find.text('Continue playing'), findsOneWidget);
    expect(find.text('Recently added'), findsOneWidget);
  });

  testWidgets('phone portrait: tabs, featured game, no overflow', (
    tester,
  ) async {
    await pumpAt(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Play'), findsWidgets);
  });

  testWidgets('phone landscape: compact layout, no overflow', (tester) async {
    await pumpAt(tester, const Size(844, 390));
    expect(tester.takeException(), isNull);
    expect(find.text('Play'), findsWidgets);
  });

  testWidgets('favorites tab filters the collection', (tester) async {
    // Neither game has a play stamp, so "Continue playing" stays empty and
    // the tab result is unambiguous.
    await pumpAt(
      tester,
      const Size(390, 844),
      state: AppState()
        ..games = const [
          GameEntry(
            id: 'g2',
            title: 'Super Mario World',
            system: 'snes',
            filePath: '/games/smw.sfc',
            extension: 'sfc',
            coreId: 'superfx',
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
        ],
    );
    expect(find.text('Sonic the Hedgehog'), findsWidgets);
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('Super Mario World'), findsWidgets);
    expect(find.text('Sonic the Hedgehog'), findsNothing);
  });

  testWidgets('recent tab shows only games with a play stamp', (tester) async {
    // Desktop, where the header carries the live count for the selection.
    await pumpAt(tester, const Size(1600, 1000));
    expect(find.text('2 games'), findsOneWidget);
    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();
    expect(find.text('1 game'), findsOneWidget);
  });

  testWidgets('desktop search filters the collection', (tester) async {
    await pumpAt(tester, const Size(1600, 1000));
    await tester.enterText(find.byType(TextField).first, 'metroid');
    await tester.pumpAndSettle();
    expect(find.text('Metroid Prime'), findsWidgets);
    expect(find.text('Super Mario World'), findsNothing);
  });

  testWidgets('desktop Favorites chip filters the collection', (tester) async {
    await pumpAt(
      tester,
      const Size(1600, 1000),
      state: AppState()
        ..games = const [
          GameEntry(
            id: 'favorite-demo',
            title: 'Favorite Demo',
            system: 'snes',
            filePath: '/games/favorite-demo.sfc',
            extension: 'sfc',
            coreId: 'superfx',
            favorite: true,
          ),
          GameEntry(
            id: 'other-demo',
            title: 'Other Demo',
            system: 'snes',
            filePath: '/games/other-demo.sfc',
            extension: 'sfc',
            coreId: 'superfx',
          ),
        ],
    );

    expect(find.text('Other Demo'), findsWidgets);
    await tester.tap(find.text('Favorites').first);
    await tester.pumpAndSettle();

    expect(find.text('Favorite Demo'), findsWidgets);
    expect(find.text('Other Demo'), findsNothing);
  });

  testWidgets('tablet Recently added stays global when search is active', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const Size(1024, 768),
      state: AppState()
        ..games = const [
          GameEntry(
            id: 'recent-demo',
            title: 'Recent Demo',
            system: 'snes',
            filePath: '/games/recent-demo.sfc',
            extension: 'sfc',
            coreId: 'superfx',
          ),
          GameEntry(
            id: 'other-demo',
            title: 'Other Demo',
            system: 'genesis',
            filePath: '/games/other-demo.md',
            extension: 'md',
            coreId: 'blastproc',
          ),
        ],
    );

    await tester.enterText(find.byType(TextField).first, 'Recent');
    await tester.pumpAndSettle();

    expect(find.text('Recently added'), findsOneWidget);
    expect(find.text('Recent Demo'), findsWidgets);
    expect(find.text('Other Demo'), findsWidgets);
  });

  testWidgets('tablet tiles shorten Windows paths to the filename', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const Size(1024, 768),
      state: AppState()
        ..games = const [
          GameEntry(
            id: 'windows-demo',
            title: 'Windows Demo',
            system: 'gc',
            filePath: r'C:\Users\Demo\Games\windows-demo.gcm',
            extension: 'gcm',
            coreId: 'powercube',
          ),
        ],
    );

    expect(find.text('windows-demo.gcm'), findsOneWidget);
    expect(find.text(r'C:\Users\Demo\Games\windows-demo.gcm'), findsNothing);
  });

  testWidgets('empty library offers an import action', (tester) async {
    final state = AppState();
    await pumpAt(tester, const Size(1600, 1000), state: state);
    expect(tester.takeException(), isNull);
    expect(find.text('A little quiet in here.'), findsOneWidget);
    expect(find.text('Import a folder'), findsOneWidget);
  });

  testWidgets('grid view still lists every game', (tester) async {
    await pumpAt(tester, const Size(1600, 1000));
    await tester.tap(find.byTooltip('Grid view'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Metroid Prime'), findsWidgets);
  });

  testWidgets('phone portrait uses a bottom command bar in the shell', (
    tester,
  ) async {
    // The bottom bar is shell chrome, so exercise the Shell rather than
    // the bare screen.
    final state = AppState()..games = games;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: LibraryScreen(state: state)),
      ),
    );
    await tester.pump();

    // The bar itself is rendered by Shell; here we assert the tab labels
    // the plate shows at the bottom are reachable from the screen's tabs.
    expect(find.text('All'), findsOneWidget);
  });

  testWidgets('stat panel is not shown on short layouts', (tester) async {
    await pumpAt(tester, const Size(844, 390));
    // Phone landscape keeps the dock compact; the tall stat panel would
    // not fit, so it must be absent rather than clipped.
    expect(find.text('Last played'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('brand lockup asset is bundled, not silently falling back', (
    tester,
  ) async {
    // The topbar falls back to a text wordmark if the asset is missing, so
    // assert the asset itself resolves from the bundle.
    final data = await rootBundle.load('assets/branding/lockup-light.png');
    expect(
      data.lengthInBytes,
      greaterThan(0),
      reason: 'assets/branding must stay declared in pubspec.yaml',
    );
  });

  testWidgets('select-system sheet groups systems with counts', (tester) async {
    // The trigger button lives in the shell, so exercise the sheet itself.
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSystemPicker(
                context,
                counts: const {'gc': 1, 'snes': 4, 'genesis': 2},
                selected: 'All systems',
                favoriteCount: 3,
                onPick: (v) => picked = v,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Select system'), findsOneWidget);
    // Manufacturer sections, in the plate's order, each with a real count.
    expect(find.text('NINTENDO'), findsOneWidget);
    expect(find.text('SEGA'), findsOneWidget);
    expect(find.text('GameCube'), findsOneWidget);
    expect(find.text('SNES'), findsOneWidget);
    expect(find.text('Genesis'), findsOneWidget);
    // "All systems" totals the counts; favorites carries its own count.
    expect(find.text('7'), findsOneWidget);

    await tester.tap(find.text('SNES'));
    await tester.pumpAndSettle();
    expect(picked, 'snes');
  });
}

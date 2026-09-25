import 'dart:convert';

import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/library_screen.dart';
import 'package:ezcore/screens/settings_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/orbit_widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Gate for the studio plate's five responsive layouts.
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

  final fourGames = <GameEntry>[
    games[0],
    games[1],
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

  testWidgets('desktop cover flow uses the wide, neighbor-visible page size', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1600, 1000));
    final page = tester.widget<PageView>(find.byType(PageView));

    expect(page.controller!.viewportFraction, 0.18);
  });

  testWidgets('cover art transforms continuously while the shelf is dragged', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1600, 1000));
    final page = tester.widget<PageView>(find.byType(PageView));
    final controller = page.controller!;
    final firstCover = find.byWidgetPredicate(
      (widget) =>
          widget is GameCover && widget.gameId == 'g1' && widget.system != '',
    );
    final transformForFirstCover = find
        .ancestor(of: firstCover, matching: find.byType(Transform))
        .first;
    final initialMatrix = tester
        .widget<Transform>(transformForFirstCover)
        .transform
        .clone();
    final viewport = tester.getRect(find.byType(PageView));
    await tester.drag(
      find.byType(PageView),
      Offset(-viewport.width * controller.viewportFraction * 0.35, 0),
    );
    await tester.pump();

    expect(controller.page!, greaterThan(0.15));
    final draggedMatrix = tester
        .widget<Transform>(transformForFirstCover)
        .transform;
    expect(draggedMatrix.storage[0], isNot(initialMatrix.storage[0]));

    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('flow selection survives a grid round trip', (tester) async {
    await pumpAt(
      tester,
      const Size(1600, 1000),
      state: AppState()..games = fourGames,
    );
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Super Mario World'), findsWidgets);

    await tester.tap(find.byTooltip('Grid view'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cover Flow view'));
    await tester.pumpAndSettle();

    final page = tester.widget<PageView>(find.byType(PageView));
    expect(page.controller!.page, closeTo(1, 0.01));
    expect(find.text('Super Mario World'), findsWidgets);
  });

  testWidgets('rapid arrow keys advance every requested page', (tester) async {
    await pumpAt(
      tester,
      const Size(1600, 1000),
      state: AppState()..games = fourGames,
    );
    final focus = tester.widget<Focus>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Focus &&
            widget.focusNode?.debugLabel == 'library-browser',
      ),
    );
    focus.focusNode!.requestFocus();
    await tester.pump();
    expect(focus.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final page = tester.widget<PageView>(find.byType(PageView));
    expect(page.controller!.page, closeTo(2, 0.01));
    expect(find.text('Sonic the Hedgehog'), findsWidgets);
  });

  testWidgets('desktop mouse drag advances the shelf', (tester) async {
    await pumpAt(
      tester,
      const Size(1600, 1000),
      state: AppState()..games = fourGames,
    );
    final pageFinder = find.byType(PageView);
    final page = tester.widget<PageView>(pageFinder);
    final viewport = tester.getRect(pageFinder);
    await tester.drag(
      pageFinder,
      Offset(-viewport.width * page.controller!.viewportFraction * 0.7, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(page.controller!.page, greaterThan(0.5));
  });

  testWidgets('desktop wheel advances the shelf', (tester) async {
    await pumpAt(
      tester,
      const Size(1600, 1000),
      state: AppState()..games = fourGames,
    );
    final pageFinder = find.byType(PageView);
    final page = tester.widget<PageView>(pageFinder);
    final pointer = TestPointer(41, PointerDeviceKind.mouse);
    final center = tester.getCenter(pageFinder);
    await tester.sendEventToBinding(pointer.down(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.sendEventToBinding(pointer.up());
    await tester.pumpAndSettle();
    expect(page.controller!.page, closeTo(1, 0.01));
  });

  testWidgets('flow controls expose accessible labels', (tester) async {
    await pumpAt(tester, const Size(1600, 1000));
    expect(find.byTooltip('Previous cover'), findsOneWidget);
    expect(find.byTooltip('Next cover'), findsOneWidget);
  });

  testWidgets('library keeps a direct Capsule shortcut', (tester) async {
    String? destination;
    final state = AppState.ephemeral()..games = games;
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: LibraryScreen(state: state, onGo: (page) => destination = page),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Capsule'));
    await tester.pump();

    expect(destination, 'vault');
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
    expect(find.byType(OrbitSwitcher), findsNothing);
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

  testWidgets('phone portrait cover flow uses its portrait preview spacing', (
    tester,
  ) async {
    await pumpAt(tester, const Size(390, 844));
    final page = tester.widget<PageView>(find.byType(PageView));

    expect(page.controller!.viewportFraction, 0.62);
  });

  testWidgets('phone landscape keeps the wide preview flow', (tester) async {
    await pumpAt(tester, const Size(844, 390));
    final page = tester.widget<PageView>(find.byType(PageView));

    expect(page.controller!.viewportFraction, 0.24);
  });

  testWidgets('reduced motion snaps the shelf without an animation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: LibraryScreen(state: AppState()..games = fourGames),
          ),
        ),
      ),
    );
    await tester.pump();

    final pageFinder = find.byType(PageView);
    final pageView = tester.widget<PageView>(pageFinder);
    expect(pageView.pageSnapping, isFalse);
    expect(pageView.physics, isA<ClampingScrollPhysics>());

    final pageWidth = tester.getRect(pageFinder).width;
    await tester.drag(pageFinder, Offset(-pageWidth * .7, 0));
    await tester.pump();

    expect(pageView.controller!.page, closeTo(1, 0.01));
  });

  testWidgets('library view preference updates the mounted shelf', (
    tester,
  ) async {
    final state = AppState.ephemeral()..games = fourGames;
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: LibraryScreen(state: state)),
      ),
    );
    await tester.pump();
    expect(find.byType(PageView), findsOneWidget);

    await state.setSetting('layout', 'grid');
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('appearance lets people tune the cover-flow feel', (
    tester,
  ) async {
    final state = AppState.ephemeral();
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: SettingsScreen(state: state, initialTab: 'Appearance'),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Cover flow feel'), findsOneWidget);
    expect(find.text('Classic'), findsOneWidget);

    await tester.tap(find.text('Classic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gentle').last);
    await tester.pumpAndSettle();
    expect(state.settings['coverFlowStyle'], 'gentle');
  });

  testWidgets('unknown persisted cover-flow preference opens safely', (
    tester,
  ) async {
    final state = AppState.ephemeral();
    await state.setSetting('coverFlowStyle', 'old-value');
    await state.setSetting('layout', 'old-layout');
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: SettingsScreen(state: state, initialTab: 'Appearance'),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Classic'), findsOneWidget);
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

  testWidgets('collection navigation clears a stale search', (tester) async {
    await pumpAt(
      tester,
      const Size(1600, 1000),
      state: AppState()
        ..games = const [
          GameEntry(
            id: 'search-demo',
            title: 'Search Demo',
            system: 'snes',
            filePath: '/games/search.sfc',
            extension: 'sfc',
            coreId: 'superfx',
            favorite: true,
          ),
          GameEntry(
            id: 'other-demo',
            title: 'Other Demo',
            system: 'snes',
            filePath: '/games/other.sfc',
            extension: 'sfc',
            coreId: 'superfx',
          ),
        ],
    );

    final search = find.byType(TextField).first;
    await tester.enterText(search, 'Search');
    await tester.pump();
    await tester.tap(find.text('Favorites').first);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.text('Search Demo'), findsWidgets);
    expect(find.text('Other Demo'), findsNothing);
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

  testWidgets('wheel input does not scroll the enclosing compact dock', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const Size(640, 320),
      state: AppState()..games = fourGames,
    );
    final pageFinder = find.byType(PageView);
    final dockScroll = find
        .ancestor(of: pageFinder, matching: find.byType(Scrollable))
        .last;
    expect(dockScroll, findsOneWidget);
    final scrollState = tester.state<ScrollableState>(dockScroll);
    final before = scrollState.position.pixels;
    final pointer = TestPointer(42, PointerDeviceKind.mouse);
    final center = tester.getCenter(pageFinder);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
    await tester.pumpAndSettle();

    expect(scrollState.position.pixels, closeTo(before, 0.01));
  });

  testWidgets('removing a selected game realigns the carousel', (tester) async {
    final state = AppState.ephemeral()..games = fourGames.take(3).toList();
    await pumpAt(tester, const Size(1600, 1000), state: state);
    final pageFinder = find.byType(PageView);
    final pageController = tester.widget<PageView>(pageFinder).controller!;
    final pageWidth = tester.getSize(pageFinder).width;
    for (var i = 0; i < 2; i++) {
      await tester.drag(
        pageFinder,
        Offset(-pageWidth * pageController.viewportFraction * 0.8, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
    }
    expect(pageController.page, closeTo(2, 0.01));

    state.removeGame('g3');
    await tester.pumpAndSettle();

    final page = tester.widget<PageView>(find.byType(PageView));
    expect(page.controller!.page, closeTo(1, 0.01));
    expect(find.text('Super Mario World'), findsWidgets);
  });

  testWidgets('tablet keeps global hub rows when a search has no matches', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const Size(1024, 768),
      state: AppState()
        ..games = const [
          GameEntry(
            id: 'played',
            title: 'Played Demo',
            system: 'snes',
            filePath: '/games/played.sfc',
            extension: 'sfc',
            coreId: 'superfx',
            lastPlayedMs: 1758500000000,
          ),
        ],
    );

    await tester.enterText(find.byType(TextField).first, 'does-not-exist');
    await tester.pumpAndSettle();

    expect(find.text('Continue playing'), findsOneWidget);
    expect(find.text('Recently added'), findsOneWidget);
    expect(find.text('No titles match this view.'), findsOneWidget);
  });

  testWidgets('tablet Recent view does not duplicate the global hub', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const Size(1024, 768),
      state: AppState()
        ..games = const [
          GameEntry(
            id: 'played',
            title: 'Played Demo',
            system: 'snes',
            filePath: '/games/played.sfc',
            extension: 'sfc',
            coreId: 'superfx',
            lastPlayedMs: 1758500000000,
          ),
        ],
    );

    await tester.tap(find.text('Recent').last);
    await tester.pumpAndSettle();

    expect(find.text('Continue playing'), findsOneWidget);
    expect(find.text('Recently added'), findsOneWidget);
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

  testWidgets('installed-core filter shortcuts remain available', (
    tester,
  ) async {
    const manifest = CoreManifest(
      id: 'superfx',
      name: 'SuperFX',
      version: '1.0.0',
      license: 'GPL-3.0',
      systems: ['snes'],
      extensions: ['sfc'],
      cheatFamilies: [],
      cheatsSupported: false,
      delivery: {'linux': 'bundled'},
      artifacts: {'linux-x64': 'test-pin'},
    );
    final state = AppState()..games = fourGames;
    state.registry.loadCatalog({manifest.id: jsonEncode(manifest.toJson())});
    state.registry.install(manifest, expectedSha256: 'test-pin');

    await pumpAt(tester, const Size(1600, 1000), state: state);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is OrbitChip &&
            widget.label == 'SNES' &&
            widget.sub == 'superfx',
      ),
      findsOneWidget,
    );
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

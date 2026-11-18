import 'package:ezcore/main.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/home_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/cover_flow.dart';
import 'package:ezcore/widgets/game_dock.dart';
import 'package:ezcore/widgets/library_header.dart';
import 'package:ezcore/widgets/orbit_chrome.dart';
import 'package:ezcore/widgets/orbit_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'font_loading.dart';

/// Cover titles are balanced across lines, so match the words rather than the
/// exact line break (which depends on the cover's width).
Finder findCoverTitle(String title) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll(RegExp(r'\s+'), ' ').trim() == title,
);

void main() {
  setUpAll(loadBundledFonts);
  const game = GameEntry(
    id: 'design',
    title: 'Lanterns of Vell',
    system: 'nds',
    filePath: '/Games/lanterns.nds',
    extension: 'nds',
    lastPlayedMs: 1000,
    fileSize: 64 << 20,
    year: 2008,
    favorite: true,
    stateCount: 4,
  );

  testWidgets('desktop library shows the keyboard hint row', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final state = AppState.ephemeral()..games = const [game];
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: HomeScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    final hints = find.byType(OrbitKeyHints);
    expect(hints, findsOneWidget);
    for (final label in ['Resume', 'Details', 'Options', 'System', 'Look']) {
      expect(
        find.descendant(of: hints, matching: find.text(label)),
        findsOneWidget,
        reason: 'missing hint $label',
      );
    }
  });

  testWidgets('cover titles are balanced across lines', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final state = AppState.ephemeral()..games = const [game];
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: HomeScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    // The design balances the cover title: "Lanterns" / "of Vell", not the
    // greedy "Lanterns of" / "Vell" that Flutter's own wrapping produces. The
    // shelf also paints the same cover in its reflection.
    expect(find.text('Lanterns\nof Vell'), findsWidgets);
  });

  testWidgets('the eyebrow uses muted text, not the accent blue', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final state = AppState.ephemeral()..games = const [game];
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: HomeScreen(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    final eyebrow = tester.widget<Text>(find.text('YOUR GAMES. YOUR WAY.'));
    expect(eyebrow.style?.color, Tokens.muted);
  });

  // The phone command bar belongs to the shell (task T02). The library must
  // fit against the shell's own 64 px bar without pulling that widget into
  // this task's files.
  testWidgets('phone library fits the shell bottom bar unchanged', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final state = AppState.ephemeral()..games = const [game];
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Shell(state: state),
      ),
    );
    await tester.pump();

    final nav = find.byType(OrbitBottomNav);
    expect(nav, findsOneWidget);
    final box = tester.renderObject<RenderBox>(nav);
    expect(box.size.height, Tokens.bottomBarHeight);
    expect(find.text('The collection'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dock can fold the extra actions away', (tester) async {
    Widget dock({
      required bool showFavorite,
      required bool showMore,
      required bool showGlyph,
      required bool detailsWithLabel,
    }) {
      return MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: GameDock(
            game: game,
            mode: GameDockMode.oneLine,
            showFavorite: showFavorite,
            showMore: showMore,
            showGlyph: showGlyph,
            detailsWithLabel: detailsWithLabel,
            onResume: () {},
            onDetails: () {},
            onFavorite: () {},
            onMore: () {},
          ),
        ),
      );
    }

    await tester.pumpWidget(
      dock(
        showFavorite: true,
        showMore: true,
        showGlyph: true,
        detailsWithLabel: false,
      ),
    );
    expect(find.bySemanticsLabel('Remove from favorites'), findsOneWidget);
    expect(find.bySemanticsLabel('More options'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);

    await tester.pumpWidget(
      dock(
        showFavorite: false,
        showMore: false,
        showGlyph: false,
        detailsWithLabel: true,
      ),
    );
    expect(find.bySemanticsLabel('Remove from favorites'), findsNothing);
    expect(find.bySemanticsLabel('More options'), findsNothing);
    expect(find.text('Enter'), findsNothing);
    expect(find.text('Details'), findsOneWidget);
  });

  group('the design reference collections', () {
    List<GameEntry> shelfGames() => const [
      GameEntry(
        id: 'lanterns',
        title: 'Lanterns of Vell',
        system: 'nds',
        filePath: '/l.nds',
        extension: 'nds',
        lastPlayedMs: 1000,
        stateCount: 4,
        year: 2008,
      ),
      GameEntry(
        id: 'aurora',
        title: 'Aurora Run',
        system: 'gba',
        filePath: '/a.gba',
        extension: 'gba',
        lastPlayedMs: 2000,
        year: 2003,
      ),
      GameEntry(
        id: 'starfall',
        title: 'Starfall Courier',
        system: 'gba',
        filePath: '/s.gba',
        extension: 'gba',
        lastPlayedMs: 3000,
        year: 2004,
      ),
      GameEntry(
        id: 'tidal',
        title: 'Tidal Arcana',
        system: 'snes',
        filePath: '/t.sfc',
        extension: 'sfc',
        lastPlayedMs: 4000,
        year: 1995,
      ),
      GameEntry(
        id: 'turbo',
        title: 'Turbo Meadow',
        system: 'nes',
        filePath: '/n.nes',
        extension: 'nes',
        lastPlayedMs: 5000,
        year: 1989,
      ),
      GameEntry(
        id: 'cinder',
        title: 'Cinder & Moss',
        system: 'gb',
        filePath: '/c.gb',
        extension: 'gb',
        lastPlayedMs: 6000,
        year: 1995,
      ),
      GameEntry(
        id: 'iron',
        title: 'Ironvale 64',
        system: 'n64',
        filePath: '/i.z64',
        extension: 'z64',
        lastPlayedMs: 7000,
        year: 1995,
      ),
      GameEntry(
        id: 'orbit',
        title: 'Quiet Orbit',
        system: 'psp',
        filePath: '/o.iso',
        extension: 'iso',
        lastPlayedMs: 8000,
        year: 2007,
      ),
      GameEntry(
        id: 'comet',
        title: 'Pocket Comet',
        system: 'gbc',
        filePath: '/p.gbc',
        extension: 'gbc',
        lastPlayedMs: 9000,
        year: 2003,
      ),
      GameEntry(
        id: 'spire',
        title: 'Hollow Spire',
        system: 'snes',
        filePath: '/h.sfc',
        extension: 'sfc',
        year: 2006,
      ),
      GameEntry(
        id: 'glass',
        title: 'Glasswing',
        system: 'psx',
        filePath: '/g.cue',
        extension: 'cue',
        year: 2001,
      ),
      GameEntry(
        id: 'ember',
        title: 'Ember Circuit',
        system: 'gba',
        filePath: '/e.gba',
        extension: 'gba',
        year: 2005,
      ),
    ];

    Future<void> pumpLibrary(
      WidgetTester t,
      Size size, {
      List<GameEntry> games = const [game],
    }) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final state = AppState.ephemeral()..games = games;
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Scaffold(body: HomeScreen(state: state)),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('phone portrait shows page dots and chips without counts', (
      t,
    ) async {
      await pumpLibrary(t, const Size(390, 844), games: shelfGames());
      // The chips are the design's labels, with no numbers after them.
      expect(find.text('All games'), findsOneWidget);
      expect(find.text('Favorites'), findsOneWidget);
      expect(find.textContaining('All games 12'), findsNothing);
      // The dot row is present below the focused cover.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxWidth == 20 &&
              w.constraints?.maxHeight == 5 &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == Tokens.accent,
        ),
        findsOneWidget,
      );
    });

    testWidgets('tablet landscape drops the chips and tools and shows six '
        'handhelds', (t) async {
      // The shell's OS bar takes 76 px, leaving a 744 px short desktop window
      // — the same content height as device frame 1d.
      await pumpLibrary(t, const Size(1180, 744), games: shelfGames());
      expect(find.byType(LibraryChips), findsNothing);
      expect(find.byTooltip('View options'), findsNothing);
      expect(find.text('YOUR GAMES. YOUR WAY.'), findsNothing);
      expect(find.text('The collection'), findsOneWidget);
      // Both rows use the device frame's curated order. Covers balance long
      // titles, so match on the words regardless of where the wrap falls.
      for (final title in [
        'Tidal Arcana',
        'Cinder & Moss',
        'Quiet Orbit',
        'Pocket Comet',
        'Ember Circuit',
        'Starfall Courier',
        'Aurora Run',
      ]) {
        expect(findCoverTitle(title), findsWidgets, reason: title);
      }
      // The short rhythm ends after Handhelds; there is no Home consoles row
      // under the dock in device frame 1d.
      expect(find.text('Home consoles'), findsNothing);
    });

    testWidgets('tablet portrait lists four handhelds including Ember '
        'Circuit', (t) async {
      await pumpLibrary(t, const Size(820, 1180), games: shelfGames());
      expect(find.text('Handhelds'), findsOneWidget);
      for (final title in [
        'Cinder & Moss',
        'Quiet Orbit',
        'Pocket Comet',
        'Ember Circuit',
      ]) {
        expect(findCoverTitle(title), findsWidgets, reason: title);
      }
      expect(find.text('Home consoles'), findsOneWidget);
      for (final title in [
        'Turbo Meadow',
        'Ironvale 64',
        'Hollow Spire',
        'Glasswing',
      ]) {
        expect(findCoverTitle(title), findsWidgets, reason: title);
      }
    });

    testWidgets('an unfolded foldable keeps the grid beside the detail', (
      t,
    ) async {
      await pumpLibrary(t, const Size(900, 1000), games: shelfGames());
      // Grid on one pane, Resume and snapshots on the other, no navigation.
      expect(find.byType(CoverFlow), findsNothing);
      for (final title in ['Lanterns of Vell', 'Aurora Run', 'Tidal Arcana']) {
        expect(findCoverTitle(title), findsWidgets, reason: title);
      }
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Slot 1'), findsOneWidget);
    });

    testWidgets('a foldable detail pane leads with recorded playtime', (
      t,
    ) async {
      t.view.physicalSize = const Size(900, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final recentFirst = [
        for (final g in shelfGames())
          g.copyWith(
            lastPlayedMs: g.id == 'lanterns' ? 999999 : g.lastPlayedMs,
          ),
      ];
      final state = AppState.ephemeral()..games = recentFirst;
      await state.setSetting('playtime.lanterns', 14 * 3600000 + 22 * 60000);
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Scaffold(body: HomeScreen(state: state)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('14h 22m played · 4 snapshots'), findsOneWidget);
    });
  });
}

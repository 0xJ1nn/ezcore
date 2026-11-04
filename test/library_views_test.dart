// The library's three views (3D, Grid, List): the 3D shelf opens on the game
// played last and carries one action; the switch is remembered; keyboard and
// controller browse the shelf.
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/game_detail_screen.dart';
import 'package:ezcore/screens/home_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/collection_view.dart';
import 'package:ezcore/widgets/cover_flow.dart';
import 'package:ezcore/widgets/game_dock.dart';
import 'package:ezcore/widgets/library_header.dart';
import 'package:ezcore/widgets/pad_navigator.dart';
import 'package:ezcore/services/gamepad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const games = <GameEntry>[
    GameEntry(
      id: 'a',
      title: 'Alpha Quest',
      system: 'gba',
      filePath: '/a.gba',
      extension: 'gba',
      coreId: 'advancebit',
      lastPlayedMs: 1758400000000,
    ),
    GameEntry(
      id: 'b',
      title: 'Beta Run',
      system: 'nes',
      filePath: '/b.nes',
      extension: 'nes',
      coreId: 'nesbyte',
      lastPlayedMs: 1758500000000,
    ),
    GameEntry(
      id: 'c',
      title: 'Gamma Zone',
      system: 'snes',
      filePath: '/c.sfc',
      extension: 'sfc',
      coreId: 'superfx',
    ),
  ];

  // A second Game Boy Advance game, never played: sorting by system puts it
  // right after Alpha Quest, which no other order does.
  const zeta = GameEntry(
    id: 'z',
    title: 'Zeta Strike',
    system: 'gba',
    filePath: '/z.gba',
    extension: 'gba',
    coreId: 'advancebit',
  );

  final navKey = GlobalKey<NavigatorState>();
  void Function(GamepadEvent)? pad;

  Future<AppState> pump(
    WidgetTester t, {
    CollectionView? view,
    Size size = const Size(1280, 800),
    List<GameEntry> library = games,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final s = AppState.ephemeral()..games = List.of(library);
    if (view != null) await s.setSetting(libraryViewKey, view.value);
    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        navigatorKey: navKey,
        builder: (context, child) => PadNavigator(
          navigatorKey: navKey,
          subscribe: (cb) {
            pad = cb;
            return () => pad = null;
          },
          child: child!,
        ),
        home: Scaffold(body: HomeScreen(state: s)),
      ),
    );
    await t.pump();
    return s;
  }

  /// Puts keyboard focus on the shelf itself.
  Future<void> focusShelf(WidgetTester t) async {
    final focus = t.widget<Focus>(
      find
          .descendant(of: find.byType(CoverFlow), matching: find.byType(Focus))
          .first,
    );
    focus.focusNode!.requestFocus();
    await t.pump();
  }

  /// The title in the game dock.
  String barTitle(WidgetTester t) {
    final bar = find.byType(GameDock);
    final texts = t.widgetList<Text>(
      find.descendant(of: bar, matching: find.byType(Text)),
    );
    return texts
        .map((x) => x.data)
        .whereType<String>()
        .firstWhere((d) => [...games, zeta].any((g) => g.title == d));
  }

  /// Sort through the View chip's menu.
  Future<void> chooseSort(WidgetTester t, String label) async {
    await t.tap(find.byTooltip('View options'));
    await t.pumpAndSettle();
    await t.tap(find.text(label));
    await t.pumpAndSettle();
  }

  testWidgets('3D is the default view', (t) async {
    await pump(t);
    expect(find.byType(CoverFlow), findsOneWidget);
  });

  testWidgets('3D opens on the game played last, and offers Resume', (t) async {
    await pump(t, view: CollectionView.flow);
    expect(barTitle(t), 'Beta Run');
    expect(
      find.descendant(of: find.byType(GameDock), matching: find.text('Resume')),
      findsOneWidget,
    );
    // No separate Resume card or Continue row in 3D: the shelf is both.
    expect(find.text('RESUME'), findsNothing);
    expect(find.text('Continue playing'), findsNothing);
  });

  testWidgets('3D: arrow keys browse; a game never played offers to play it', (
    t,
  ) async {
    await pump(t, view: CollectionView.flow);
    await t.tap(find.byType(CoverFlow));
    await t.pumpAndSettle();
    // The tap on the front cover opened its page; come back.
    expect(find.byType(GameDetailScreen), findsOneWidget);
    navKey.currentState!.pop();
    await t.pumpAndSettle();
    await focusShelf(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(barTitle(t), 'Alpha Quest');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(barTitle(t), 'Gamma Zone');
    expect(
      find.descendant(of: find.byType(GameDock), matching: find.text('Play')),
      findsOneWidget,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(barTitle(t), 'Alpha Quest');
  });

  testWidgets('3D: the d-pad browses the shelf and A opens the game', (
    t,
  ) async {
    await pump(t, view: CollectionView.flow);
    await focusShelf(t);
    pad!(const GamepadEvent('right', true));
    await t.pumpAndSettle();
    expect(barTitle(t), 'Alpha Quest');
    pad!(const GamepadEvent('a', true));
    await t.pumpAndSettle();
    expect(find.byType(GameDetailScreen), findsOneWidget);
  });

  testWidgets('the d-pad still moves focus out of the search box', (t) async {
    await pump(t, view: CollectionView.grid);
    await t.tap(find.byType(TextField));
    await t.pump();
    final before = FocusManager.instance.primaryFocus;
    pad!(const GamepadEvent('right', true));
    await t.pump();
    expect(FocusManager.instance.primaryFocus, isNot(same(before)));
  });

  testWidgets('a filter brings the shelf back to the front', (t) async {
    await pump(t, view: CollectionView.flow);
    // Test text is wide (Ahem): scroll the chip row to it.
    final snesChip = find.descendant(
      of: find.byType(LibraryChips),
      matching: find.text('SNES'),
    );
    await t.dragUntilVisible(
      snesChip,
      find
          .ancestor(
            of: find.byType(LibraryChips),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(-120, 0),
    );
    await t.pumpAndSettle();
    await t.tap(snesChip);
    await t.pumpAndSettle();
    expect(barTitle(t), 'Gamma Zone');
  });

  testWidgets('the view switch is remembered', (t) async {
    // Tall enough that the list rows below Resume and Continue are built.
    final s = await pump(t, size: const Size(1280, 1600));
    await t.tap(find.byTooltip('List'));
    await t.pump();
    expect(s.settings[libraryViewKey], 'list');
    expect(find.byType(CoverFlow), findsNothing);
    expect(find.byKey(const Key('library-all-games')), findsOneWidget);
    expect(find.textContaining('Not played yet'), findsOneWidget);
    await t.tap(find.byTooltip('Grid'));
    await t.pump();
    expect(s.settings[libraryViewKey], 'grid');
  });

  testWidgets('an unknown stored view falls back instead of failing', (
    t,
  ) async {
    expect(CollectionView.fromSetting('carousel'), CollectionView.grid);
    expect(
      CollectionView.fromSetting(null, fallback: CollectionView.flow),
      CollectionView.flow,
    );
    expect(CollectionView.fromSetting('3d'), CollectionView.flow);
  });

  testWidgets('3D: the page dots follow the shelf', (t) async {
    final semantics = t.ensureSemantics();
    await pump(t, view: CollectionView.flow);
    await focusShelf(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(barTitle(t), 'Alpha Quest');
    expect(find.bySemanticsLabel(RegExp('Game 2 of 3')), findsOneWidget);
    semantics.dispose();
  });

  group('the library bar, on every device', () {
    const sizes = <String, Size>{
      'desktop': Size(1600, 1000),
      'tablet': Size(1024, 768),
      'tablet portrait': Size(834, 1112),
      'phone landscape': Size(844, 390),
      'very short window': Size(640, 320),
      'phone portrait': Size(390, 844),
      'small phone': Size(360, 640),
    };
    for (final view in CollectionView.values) {
      for (final e in sizes.entries) {
        testWidgets('${view.label}, ${e.key}: search, views, add and tabs', (
          t,
        ) async {
          await pump(t, view: view, size: e.value);
          expect(t.takeException(), isNull);
          // Search is a field on desktop and a round button everywhere else.
          expect(
            find.byType(LibrarySearchField).evaluate().isNotEmpty ||
                find.byTooltip('Search').evaluate().isNotEmpty,
            isTrue,
          );
          expect(find.byTooltip('View options'), findsOneWidget);
          // A look switch on wide screens; the View menu covers phones.
          if (find.byType(LibraryLookSwitch).evaluate().isNotEmpty) {
            expect(find.byType(LibraryLookSwitch), findsOneWidget);
          }
          // The test font is wide, so the later chips are reached by
          // scrolling the chip row, as a thumb would.
          if (find.byType(LibraryChips).evaluate().isNotEmpty) {
            final chips = find
                .ancestor(
                  of: find.byType(LibraryChips),
                  matching: find.byType(Scrollable),
                )
                .first;
            for (final chip in ['All games', 'Favorites']) {
              final target = find.descendant(
                of: find.byType(LibraryChips),
                matching: find.text(chip),
              );
              await t.dragUntilVisible(target, chips, const Offset(-80, 0));
              expect(target, findsWidgets, reason: chip);
            }
          }
        });
      }
    }
  });

  testWidgets('sorting starts the shelf at the first game in the new order', (
    t,
  ) async {
    await pump(t, view: CollectionView.flow);
    expect(barTitle(t), 'Beta Run');
    await chooseSort(t, 'Sort: A–Z');
    expect(barTitle(t), 'Alpha Quest');
  });

  testWidgets('nothing played still shows the collection, ready to play', (
    t,
  ) async {
    await pump(
      t,
      view: CollectionView.flow,
      library: [for (final g in games) g.copyWith(lastPlayedMs: 0)],
    );
    // No Continue row or Resume card, but the shelf and its Play action stay.
    expect(find.text('Continue playing'), findsNothing);
    expect(
      find.descendant(of: find.byType(GameDock), matching: find.text('Play')),
      findsOneWidget,
    );
  });

  testWidgets('Favorites is there before you have any, and says how', (
    t,
  ) async {
    await pump(t, view: CollectionView.grid);
    await t.tap(find.text('Favorites'));
    await t.pumpAndSettle();
    expect(find.textContaining('Tap ♡ on a game'), findsOneWidget);
  });

  testWidgets('sort by system: games grouped by system', (t) async {
    await pump(t, view: CollectionView.flow, library: [...games, zeta]);
    await chooseSort(t, 'Sort: By system');
    expect(barTitle(t), 'Alpha Quest');
    await focusShelf(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    // Zeta Strike is the other Game Boy Advance game, so it comes next.
    expect(barTitle(t), 'Zeta Strike');
  });

  testWidgets('sort by system: Grid and List get a heading per system', (
    t,
  ) async {
    for (final view in [CollectionView.grid, CollectionView.list]) {
      // Tall enough that the grouped games below Resume and Continue build.
      await pump(
        t,
        view: view,
        size: const Size(1280, 1600),
        library: [...games, zeta],
      );
      await chooseSort(t, 'Sort: By system');
      final headings = find.bySemanticsLabel(
        RegExp(r'^Game Boy Advance, 2 games$'),
      );
      expect(headings, findsOneWidget, reason: view.label);
    }
  });

  testWidgets('the look switcher offers all five looks', (t) async {
    await pump(t, view: CollectionView.flow);
    for (final label in ['3D shelf', 'Shelf', 'Wall', 'Grid', 'List']) {
      expect(find.byTooltip(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('Q opens the options sheet for the selected game', (t) async {
    await pump(t, view: CollectionView.flow);
    await focusShelf(t);
    await t.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await t.pumpAndSettle();
    // The design's five rows, in order, with Resume focused first.
    expect(find.text('Resume'), findsWidgets);
    expect(find.text('Details and snapshots'), findsOneWidget);
    // Beta Run is not a favorite yet, so the row offers to add it.
    expect(find.text('Add to favorites'), findsOneWidget);
    expect(find.text('Cheats'), findsOneWidget);
    expect(find.text('Remove from collection'), findsOneWidget);
  });

  testWidgets('removal asks first, then Undo restores the game', (t) async {
    final s = await pump(t, view: CollectionView.flow);
    await t.tap(find.byTooltip('More options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove from collection'));
    await t.pumpAndSettle();
    // The confirm defaults to the safe choice; remove deliberately.
    expect(find.text('Keep it'), findsOneWidget);
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(s.games.any((g) => g.title == 'Beta Run'), isFalse);
    expect(find.textContaining('Removed'), findsOneWidget);
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(s.games.any((g) => g.title == 'Beta Run'), isTrue);
  });
}

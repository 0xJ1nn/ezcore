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
import 'package:ezcore/widgets/orbit_widgets.dart';
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

  /// The title in the 3D action bar.
  String barTitle(WidgetTester t) {
    final bar = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_FlowBar',
    );
    final texts = t.widgetList<Text>(
      find.descendant(of: bar, matching: find.byType(Text)),
    );
    return texts
        .map((x) => x.data)
        .whereType<String>()
        .firstWhere((d) => [...games, zeta].any((g) => g.title == d));
  }

  testWidgets('3D is the default view', (t) async {
    await pump(t);
    expect(find.byType(CoverFlow), findsOneWidget);
  });

  testWidgets('3D opens on the game played last, and offers Resume', (t) async {
    await pump(t, view: CollectionView.flow);
    expect(barTitle(t), 'Beta Run');
    expect(find.widgetWithText(OrbitPrimary, 'Resume'), findsOneWidget);
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
    expect(find.widgetWithText(OrbitPrimary, "Let's play"), findsOneWidget);
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
    // Test text is wide (Ahem): scroll the tab row to it.
    await t.dragUntilVisible(
      find.text('Super Nintendo'),
      find
          .ancestor(
            of: find.text('Time capsule'),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(-120, 0),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Super Nintendo'));
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
    expect(find.text('All games'), findsOneWidget);
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
          expect(find.byType(OrbitSearch), findsOneWidget);
          expect(find.byType(CollectionViewSwitch), findsOneWidget);
          expect(find.byTooltip('Add games'), findsOneWidget);
          expect(find.byTooltip('Sort'), findsOneWidget);
          // The test font is wide, so on phones the later tabs are reached
          // by scrolling the tab row, as a thumb would.
          final tabs = find
              .ancestor(
                of: find.text('Time capsule'),
                matching: find.byType(Scrollable),
              )
              .first;
          for (final tab in ['Time capsule', 'Favorites', 'All systems']) {
            await t.dragUntilVisible(
              find.text(tab),
              tabs,
              const Offset(-80, 0),
            );
            expect(find.text(tab), findsOneWidget, reason: tab);
          }
        });
      }
    }
  });

  testWidgets('Time capsule: the games you played, latest first', (t) async {
    await pump(t, view: CollectionView.flow);
    // Sorting A–Z must not reorder the capsule: it is a history.
    await t.tap(find.byTooltip('Sort'));
    await t.pumpAndSettle();
    await t.tap(find.text('A–Z').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Time capsule'));
    await t.pumpAndSettle();
    expect(barTitle(t), 'Beta Run');
    expect(find.bySemanticsLabel(RegExp('Game 1 of 2')), findsOneWidget);
  });

  testWidgets('Time capsule before anything is played says so', (t) async {
    await pump(
      t,
      view: CollectionView.grid,
      library: [for (final g in games) g.copyWith(lastPlayedMs: 0)],
    );
    await t.tap(find.text('Time capsule'));
    await t.pumpAndSettle();
    expect(find.textContaining('Games you play land here'), findsOneWidget);
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
    await t.tap(find.byTooltip('Sort'));
    await t.pumpAndSettle();
    await t.tap(find.text('By system').last);
    await t.pumpAndSettle();
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
      await pump(t, view: view, library: [...games, zeta]);
      await t.tap(find.byTooltip('Sort'));
      await t.pumpAndSettle();
      await t.tap(find.text('By system').last);
      await t.pumpAndSettle();
      final headings = find.bySemanticsLabel(
        RegExp(r'^Game Boy Advance, 2 games$'),
      );
      expect(headings, findsOneWidget, reason: view.label);
    }
  });
}

// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

// Render-time checks for the numbers the phone and desktop plates measure.
// Each assertion reads a value back from a pumped widget or a public token so
// a drifted chrome number fails where it is painted, not in a design note.
import 'package:ezcore/brand/brand_mark.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/home_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/input_mode.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/game_dock.dart';
import 'package:ezcore/widgets/library_header.dart';
import 'package:ezcore/widgets/library_looks/grid_look.dart';
import 'package:ezcore/widgets/library_looks/library_cover.dart';
import 'package:ezcore/widgets/library_looks/list_look.dart';
import 'package:ezcore/widgets/library_looks/look_theme.dart';
import 'package:ezcore/widgets/orbit_chrome.dart';
import 'package:ezcore/widgets/orbit_sheet.dart';
import 'package:ezcore/widgets/orbit_toast.dart';
import 'package:ezcore/widgets/orbit_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _game = GameEntry(
  id: 'deep-orbit',
  title: 'Deep Orbit',
  system: 'gc',
  filePath: '/deep.gcm',
  extension: 'gcm',
  coreId: 'powercube',
);

Future<void> pumpMeasured(
  WidgetTester t,
  Widget body, {
  Size size = const Size(1200, 900),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: Tokens.theme(),
      home: Scaffold(body: body),
    ),
  );
  await t.pump();
}

void main() {
  testWidgets('primary CTA renders the measured button', (t) async {
    await pumpMeasured(
      t,
      Center(
        child: OrbitPrimary(label: 'Resume', onPressed: () {}),
      ),
    );
    final buttonFinder = find
        .descendant(
          of: find.byType(OrbitPrimary),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.constraints != null && w.child is Row,
          ),
        )
        .first;
    final button = t.widget<Container>(buttonFinder);
    expect(button.constraints!.minHeight, 56, reason: 'primary height');
    expect(button.padding, const EdgeInsets.fromLTRB(18, 0, 24, 0));
    final iconFinder = find
        .descendant(of: buttonFinder, matching: find.byType(Icon))
        .first;
    expect(t.getSize(iconFinder).width, 22, reason: 'primary glyph');
    final label = t.widget<Text>(
      find.descendant(of: buttonFinder, matching: find.text('Resume')),
    );
    expect(label.style?.fontSize, 17);
    expect(label.style?.fontWeight, FontWeight.w700);
    expect(
      label.style?.fontFamily,
      Tokens.bodyFamily,
      reason: 'button body face',
    );

    await pumpMeasured(
      t,
      Center(
        child: OrbitSecondary(label: 'Open Systems', onPressed: () {}),
      ),
    );
    final secondary = t.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(
      secondary.style?.minimumSize?.resolve(<WidgetState>{}),
      const Size(0, Tokens.ctaHeight),
    );
    final secondaryLabel = t.widget<Text>(find.text('Open Systems'));
    expect(secondaryLabel.style?.fontSize, 16);
    expect(secondaryLabel.style?.fontWeight, FontWeight.w700);
  });

  testWidgets('phone bar insets tabs and keeps the measured label gap', (
    t,
  ) async {
    await pumpMeasured(
      t,
      SizedBox.expand(
        child: OrbitBottomNav(page: 'library', onGo: (_) {}, onAddGames: () {}),
      ),
      size: const Size(390, 844),
    );
    final bar = find.byType(OrbitBottomNav);
    final barBox = t.widget<Container>(
      find
          .descendant(
            of: bar,
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.decoration == Tokens.bottomBarDecor,
            ),
          )
          .first,
    );
    expect(barBox.padding, const EdgeInsets.symmetric(horizontal: 8));
    final firstTab = find
        .descendant(of: bar, matching: find.byType(InkWell))
        .first;
    expect(
      t.getRect(firstTab).left - t.getRect(bar).left,
      8,
      reason: 'first tab inset',
    );
    final gap = t.widget<SizedBox>(
      find
          .descendant(
            of: bar,
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.height != null && w.width == null,
            ),
          )
          .first,
    );
    expect(gap.height, 5, reason: 'icon to label gap');
  });

  testWidgets('mini dock renders the measured panel', (t) async {
    await pumpMeasured(
      t,
      SizedBox(
        width: 390,
        child: GameDock(
          game: _game,
          mode: GameDockMode.mini,
          onResume: () {},
          onDetails: () {},
          onFavorite: () {},
          onMore: () {},
        ),
      ),
      size: const Size(390, 844),
    );
    expect(t.getSize(find.byType(GameDock)).height, 68, reason: 'mini height');
    final panel = t.widget<Container>(
      find
          .descendant(
            of: find.byType(GameDock),
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.child is LayoutBuilder,
            ),
          )
          .first,
    );
    expect(panel.padding, const EdgeInsets.fromLTRB(16, 0, 8, 0));
    final title = t.widget<Text>(
      find.descendant(
        of: find.byType(GameDock),
        matching: find.text('Deep Orbit'),
      ),
    );
    expect(title.style?.fontSize, 17, reason: 'mini title size');
  });

  testWidgets('toast keeps the measured Undo gap', (t) async {
    await pumpMeasured(
      t,
      Center(
        child: OrbitToast(message: 'Saved', onUndo: () {}),
      ),
    );
    final undoRow = find
        .ancestor(of: find.text('Undo'), matching: find.byType(Row))
        .last;
    final children = t.widget<Row>(undoRow).children;
    final gap = children[children.length - 2];
    expect(gap, isA<SizedBox>());
    expect((gap as SizedBox).width, 12, reason: 'Undo gap');
  });

  testWidgets('options sheet reserves the measured bottom inset', (t) async {
    await pumpMeasured(
      t,
      Center(
        child: OrbitOptionsSheet(
          title: 'Title',
          items: const [
            OrbitSheetItem(label: 'One', icon: Icons.check, value: 1),
          ],
        ),
      ),
    );
    final panel = t.widget<Container>(
      find
          .byWidgetPredicate(
            (w) => w is Container && w.decoration == Tokens.sheetDecor,
          )
          .first,
    );
    expect(panel.padding, const EdgeInsets.fromLTRB(20, 14, 20, 76));
  });

  testWidgets('desktop lockup renders at the measured height', (t) async {
    await pumpMeasured(t, const OrbitTopBar(compact: false));
    expect(t.widget<BrandLockup>(find.byType(BrandLockup)).height, 34);
  });

  testWidgets('wide rail uses the measured button and padding', (t) async {
    await pumpMeasured(
      t,
      SizedBox(
        height: 900,
        child: OrbitRail(page: 'cores', onGo: (_) {}, onAddGames: () {}),
      ),
    );
    final rail = t.widget<Container>(
      find
          .descendant(
            of: find.byType(OrbitRail),
            matching: find.byType(Container),
          )
          .first,
    );
    // The prototype's rail pads `96px 0 28px` (no horizontal inset): its
    // 80 px items are centred in the 104 px rail by the column. Add games sits
    // 18 px below the four destinations (`margin-top:18px` on the fifth stop).
    expect(rail.padding, const EdgeInsets.fromLTRB(0, 96, 0, 28));
    expect(
      find.descendant(
        of: find.byType(OrbitRail),
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == Tokens.railAddGap,
        ),
      ),
      findsOneWidget,
      reason: 'gap before Add games',
    );
    final button = find.byType(AnimatedContainer).first;
    final box = t.widget<AnimatedContainer>(button);
    expect(
      t.getRect(button).width,
      Tokens.railItemWidth,
      reason: 'rail item width',
    );
    // Pick the stop's own box by its measured min-height: the focus border
    // also builds a Container with tight width constraints inside the rail
    // button's AnimatedContainer.
    final inner = t.widget<Container>(
      find
          .descendant(
            of: button,
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.constraints?.minHeight == Tokens.railItemHeight,
            ),
          )
          .first,
    );
    expect(
      inner.constraints!.minHeight,
      Tokens.railItemHeight,
      reason: 'rail button height',
    );
    expect(
      (box.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(16),
    );
    final gap = t.widget<SizedBox>(
      find
          .descendant(
            of: button,
            matching: find.byWidgetPredicate(
              (w) => w is SizedBox && w.height != null && w.width == null,
            ),
          )
          .first,
    );
    expect(gap.height, 7, reason: 'rail icon to label gap');
    final label = t.widget<Text>(
      find.descendant(of: button, matching: find.text('Library')),
    );
    expect(
      label.style?.fontWeight,
      FontWeight.w600,
      reason: 'inactive rail label weight',
    );
  });

  testWidgets('short rail uses the measured compact button', (t) async {
    await pumpMeasured(
      t,
      SizedBox(
        width: 72,
        height: 390,
        child: OrbitRail(
          page: 'cores',
          onGo: (_) {},
          short: true,
          modifier: LayoutModifier.handheld,
          onAddGames: () {},
        ),
      ),
      size: const Size(844, 390),
    );
    final button = find.byType(AnimatedContainer).first;
    final box = t.widget<AnimatedContainer>(button);
    final inner = t.widget<Container>(
      find
          .descendant(
            of: button,
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.constraints != null,
            ),
          )
          .first,
    );
    expect(
      inner.constraints!.minHeight,
      52,
      reason: 'short rail button height',
    );
    expect(
      (box.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(14),
    );
    final icon = t.widget<Icon>(
      find.descendant(of: button, matching: find.byType(Icon)).first,
    );
    expect(icon.size, 24, reason: 'short rail icon');
  });

  testWidgets('grid keeps the measured row and phone gaps', (t) async {
    final actions = LookActions(
      games: const [],
      selectedId: null,
      state: AppState.ephemeral(),
      onTap: (_) {},
    );
    await pumpMeasured(t, GridLook(actions: actions));
    var grid = t.widget<GridView>(find.byType(GridView));
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .mainAxisSpacing,
      24,
      reason: 'grid row gap',
    );
    expect(grid.padding, const EdgeInsets.fromLTRB(47, 20, 47, 24));
    expect(LookTheme.gridCover, const Size(132, 176), reason: 'prototype CSS');
    expect(LookTheme.wallCover, const Size(156, 208), reason: 'prototype CSS');
    expect(
      const Size(LookTheme.shelfCoverWidth, LookTheme.shelfCoverHeight),
      const Size(150, 200),
      reason: 'prototype CSS',
    );
    expect(LookTheme.shelfGap, 22, reason: 'prototype CSS');
    await pumpMeasured(
      t,
      SizedBox(
        width: 390,
        height: 600,
        child: GridLook(actions: actions, compact: true),
      ),
      size: const Size(390, 844),
    );
    grid = t.widget<GridView>(find.byType(GridView));
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisSpacing,
      12,
      reason: 'phone grid cross gap',
    );
  });

  testWidgets('phone list uses the measured inset, title and thumb', (t) async {
    final actions = LookActions(
      games: const [_game],
      selectedId: null,
      state: AppState.ephemeral(),
      onTap: (_) {},
    );
    await pumpMeasured(
      t,
      SizedBox(
        width: 390,
        height: 600,
        child: ListLook(actions: actions, compact: true),
      ),
      size: const Size(390, 844),
    );
    final row = t.widget<Container>(
      find
          .descendant(
            of: find.byType(ListLook),
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.padding != null,
            ),
          )
          .first,
    );
    expect(row.padding, const EdgeInsets.symmetric(horizontal: 12));
    final titleSizes = t
        .widgetList<Text>(find.text('Deep Orbit'))
        .map((w) => w.style?.fontSize)
        .toList();
    expect(titleSizes, contains(15), reason: 'phone list title size');
    final cover = t.widget<LibraryCover>(find.byType(LibraryCover));
    expect(cover.width, 36, reason: 'phone thumb width');
    expect(cover.height, 48, reason: 'phone thumb height');
  });

  testWidgets('phone screen title renders at the measured size', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final state = AppState.ephemeral()..games = List.of(const [_game]);
    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: HomeScreen(state: state)),
      ),
    );
    await t.pump();
    expect(t.widget<LibraryTitle>(find.byType(LibraryTitle)).titleSize, 28);
  });

  testWidgets('switch renders the measured 56×32 toggle and 24 px knob', (
    t,
  ) async {
    await pumpMeasured(
      t,
      Center(
        child: OrbitToggle(value: true, onChanged: (_) {}, label: 'Motion'),
      ),
    );
    final trackFinder = find.byType(AnimatedContainer).first;
    final track = t.widget<AnimatedContainer>(trackFinder);
    expect(
      t.getSize(trackFinder),
      const Size(Tokens.toggleWidth, Tokens.toggleHeight),
    );
    expect(track.padding, const EdgeInsets.all(Tokens.togglePad));
    expect(
      (track.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(Tokens.toggleRadius),
    );
    // An AnimatedContainer builds its own Container, so a plain
    // `find.byType(Container).first` finds the 56×32 track, not the knob.
    // Select the child pinned to the measured 24 px knob size instead.
    final knobFinder = find.descendant(
      of: trackFinder,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints ==
                BoxConstraints.tightFor(
                  width: Tokens.toggleKnob,
                  height: Tokens.toggleKnob,
                ),
      ),
    );
    expect(knobFinder, findsOneWidget, reason: 'toggle knob');
    expect(
      t.getSize(knobFinder),
      const Size(Tokens.toggleKnob, Tokens.toggleKnob),
    );
  });

  testWidgets('full dock keeps the measured badge, gaps and glyph chip', (
    t,
  ) async {
    await pumpMeasured(
      t,
      SizedBox(
        width: 900,
        child: GameDock(
          game: _game,
          mode: GameDockMode.full,
          onResume: () {},
          onDetails: () {},
          onFavorite: () {},
          onMore: () {},
        ),
      ),
    );
    final badge = t.widget<Container>(
      find
          .ancestor(of: find.text('GAMECUBE'), matching: find.byType(Container))
          .first,
    );
    expect(
      badge.padding,
      const EdgeInsets.symmetric(horizontal: Tokens.dockGap),
    );
    final chipFinder = find
        .ancestor(of: find.text('Enter'), matching: find.byType(Container))
        .first;
    final chip = t.widget<Container>(chipFinder);
    expect(t.getSize(chipFinder).height, 24, reason: '24 px glyph chip');
    expect(chip.decoration, isA<BoxDecoration>());
    expect(
      (chip.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(12),
    );
    expect(
      find.descendant(
        of: find.byType(GameDock),
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == Tokens.dockGap,
        ),
      ),
      findsWidgets,
      reason: '10 px dock rhythm',
    );
  });

  testWidgets('OS bar status corner keeps the measured chip and gap', (
    t,
  ) async {
    await pumpMeasured(t, OrbitStatus(now: () => DateTime(2026, 1, 1, 9, 41)));
    final chipFinder = find
        .ancestor(
          of: find.text('On this device'),
          matching: find.byType(Container),
        )
        .first;
    final chip = t.widget<Container>(chipFinder);
    expect(t.getSize(chipFinder).height, 30);
    expect(
      chip.padding,
      const EdgeInsets.symmetric(horizontal: Tokens.statusPad),
    );
    final label = t.widget<Text>(find.text('On this device'));
    expect(label.style?.fontSize, 14);
    expect(
      find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == Tokens.statusGap,
      ),
      findsNWidgets(2),
      reason: '22 px status gaps',
    );
  });

  testWidgets('library search field and chip counts keep the measured type', (
    t,
  ) async {
    final controller = TextEditingController();
    final node = FocusNode();
    addTearDown(() {
      controller.dispose();
      node.dispose();
    });
    await pumpMeasured(
      t,
      LibrarySearchField(
        controller: controller,
        focusNode: node,
        onChanged: (_) {},
      ),
    );
    final field = t.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    expect(
      field.padding,
      const EdgeInsets.fromLTRB(
        Tokens.searchPadLeft,
        0,
        Tokens.searchPadRight,
        0,
      ),
    );
    expect(t.widget<Icon>(find.byType(Icon).first).size, Tokens.searchIconSize);

    await pumpMeasured(
      t,
      Center(
        child: OrbitChip(
          label: 'All games',
          sub: '12',
          active: false,
          onTap: () {},
        ),
      ),
    );
    expect(
      t.widget<Text>(find.text('12')).style?.fontSize,
      14,
      reason: 'chip counts inherit the 14 px label',
    );
  });

  test('motion tokens hold the measured durations', () {
    expect(Tokens.fullMoveDur, const Duration(milliseconds: 520));
    expect(Tokens.fullSceneDur, const Duration(milliseconds: 900));
  });
}

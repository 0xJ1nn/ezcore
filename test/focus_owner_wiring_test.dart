// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

// T19 review: the two places that still owned focus for themselves now write
// to the one FocusOwner. A LookTile's hover moves the same focus its arrows
// move, and the 3D shelf is registered so the dock returns to it and its row
// end bumps. These are the in-app counterparts of focus_owner_test.dart's
// synthetic acceptance tests.
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/home_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/input_mode.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/cover_flow.dart';
import 'package:ezcore/widgets/library_looks/library_cover.dart';
import 'package:ezcore/widgets/pad_navigator.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final owner = FocusOwner.shared;

  setUp(() {
    InputMode.shared.reset();
    owner.reset();
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  });

  tearDown(() {
    owner.reset();
    InputMode.shared.reset();
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  int rings(WidgetTester t) => t
      .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
      .where((c) {
        final border = (c.decoration as BoxDecoration?)?.border as Border?;
        return border?.top.color == Tokens.accentHi;
      })
      .length;

  testWidgets(
    'hovering a LookTile writes the single focus, not a second ring',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 120,
                  height: 160,
                  child: LookTile(
                    semanticLabel: 'first',
                    onTap: () {},
                    child: const SizedBox.expand(),
                  ),
                ),
                SizedBox(
                  width: 120,
                  height: 160,
                  child: LookTile(
                    semanticLabel: 'second',
                    onTap: () {},
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final nodes = t
          .widgetList<FocusableActionDetector>(
            find.byType(FocusableActionDetector),
          )
          .map((d) => d.focusNode!)
          .toList();
      expect(rings(t), 0);

      final center = t.getCenter(
        find.byWidgetPredicate(
          (w) => w is LookTile && w.semanticLabel == 'second',
        ),
      );
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await t.pump();
      await mouse.moveTo(center);
      await t.pump();

      expect(
        FocusManager.instance.primaryFocus,
        same(nodes.last),
        reason: 'the pointer moved the one focus to the hovered tile',
      );
      expect(
        owner.remembered,
        same(nodes.last),
        reason: 'the look remembers that tile per screen',
      );
      expect(rings(t), 1, reason: 'hover and arrows cannot show two rings');
      await mouse.removePointer();
    },
  );

  testWidgets('a LookTile nudges 7 px at a row end', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 160,
            child: LookTile(
              semanticLabel: 'edge',
              onTap: () {},
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    Offset translation() {
      final transform = t.widget<Transform>(
        find
            .descendant(
              of: find.byType(LookTile),
              matching: find.byType(Transform),
            )
            .first,
      );
      final v = transform.transform.getTranslation();
      return Offset(v.x, v.y);
    }

    expect(translation(), Offset.zero);
    owner.edge.value = const EdgeSignal('edge', TraversalDirection.right, 1);
    await t.pump();
    await t.pump(const Duration(milliseconds: 139));
    expect(translation().dx, inInclusiveRange(6, FocusOwner.edgeNudge));
  });

  testWidgets('the shelf is registered and dock-up returns to it', (t) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    final state = AppState.ephemeral()
      ..games = const [
        GameEntry(
          id: 'lanterns',
          title: 'Lanterns of Vell',
          system: 'nds',
          filePath: '/l.nds',
          extension: 'nds',
          coreId: 'dualscreen',
          year: 2008,
          lastPlayedMs: 1000,
        ),
      ];
    final dockScope = FocusScopeNode(debugLabel: 'dock scope');
    final dock = FocusNode(debugLabel: 'dock');
    addTearDown(dock.dispose);
    addTearDown(dockScope.dispose);

    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: SizedBox.expand(
            child: Stack(
              children: [
                Positioned.fill(child: HomeScreen(state: state)),
                // A separate scope, like the dock's own button group: a plain
                // up cannot traverse back into the shelf from here.
                FocusScope(
                  node: dockScope,
                  child: Focus(
                    focusNode: dock,
                    child: const SizedBox(width: 1, height: 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    final shelf = t.widget<CoverFlow>(find.byType(CoverFlow)).focusNode;
    expect(shelf, isNotNull);
    expect(
      owner.selectedCover,
      same(shelf),
      reason: 'the call site registered the shelf with the one owner',
    );
    expect(owner.idOf(shelf!), isNotNull);
    expect(
      owner.remembered,
      same(shelf),
      reason: 'the shelf itself is remembered for this screen',
    );

    dock.requestFocus();
    await t.pump();
    expect(owner.move(TraversalDirection.up, from: dock), isTrue);
    await t.pump();
    expect(
      FocusManager.instance.primaryFocus,
      same(shelf),
      reason: 'up from the dock lands on the selected cover',
    );
  });

  testWidgets('the shelf bumps 7 px at the end of its row', (t) async {
    final node = FocusNode(debugLabel: 'shelf');
    owner.register('shelf-test', node);
    addTearDown(() => owner.unregister('shelf-test', node));
    addTearDown(node.dispose);

    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 500,
            child: CoverFlow(
              count: 2,
              index: 0,
              focusNode: node,
              itemSize: const Size(200, 260),
              onIndexChanged: (_) {},
              onActivate: (_) {},
              itemBuilder: (context, i, front) =>
                  const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await t.pumpAndSettle();

    expect(owner.move(TraversalDirection.left), isTrue);
    await t.pump();
    Offset translation() {
      final transform = t.widget<Transform>(
        find
            .descendant(
              of: find.byType(CoverFlow),
              matching: find.byType(Transform),
            )
            .first,
      );
      final v = transform.transform.getTranslation();
      return Offset(v.x, v.y);
    }

    await t.pump(const Duration(milliseconds: 139));
    expect(
      translation().dx,
      inInclusiveRange(-FocusOwner.edgeNudge, -6),
      reason: 'left at the first cover nudges 7 px toward the wall',
    );
  });
}

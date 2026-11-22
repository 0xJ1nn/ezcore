// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'package:ezcore/main.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/import_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/game_dock.dart';
import 'package:ezcore/widgets/orbit_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A populated shelf must keep a visible route to import on every family,
/// and the phone's selected-game panel must keep the frame's info and CTA.

const _game = GameEntry(
  id: 'sample',
  title: 'Sample Title',
  system: 'gc',
  filePath: '/library/sample',
  extension: 'gcm',
  fileSize: 1048576,
  lastPlayedMs: 1758500000000,
);

Future<void> pumpShell(WidgetTester tester, Size size) async {
  final state = AppState.ephemeral();
  state.games = const [_game];
  state.loaded = true;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
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
      home: Shell(key: UniqueKey(), state: state),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> pumpMiniDock(
  WidgetTester tester, {
  required VoidCallback onResume,
  required VoidCallback onMore,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: Tokens.theme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: GameDock(
              game: _game,
              mode: GameDockMode.mini,
              onResume: onResume,
              onDetails: () {},
              onFavorite: () {},
              onMore: onMore,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('desktop rail offers Add games and reaches import', (tester) async {
    await pumpShell(tester, const Size(1280, 720));
    final rail = find.byType(OrbitRail);
    expect(rail, findsOneWidget);
    final add = find.descendant(of: rail, matching: find.text('Add games'));
    expect(add, findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'rail overflow at 1280x720');
    await tester.tap(add);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(ImportScreen), findsOneWidget);
  });

  testWidgets('short rail keeps five destinations without overflow', (tester) async {
    await pumpShell(tester, const Size(640, 320));
    final rail = find.byType(OrbitRail);
    final add = find.descendant(
      of: rail,
      matching: find.bySemanticsLabel('Add games'),
    );
    expect(add, findsOneWidget, reason: 'short rail needs the same fifth stop');
    expect(tester.takeException(), isNull, reason: 'rail overflow at 640x320');
  });

  testWidgets('phone bar still shows Add and reaches import', (tester) async {
    await pumpShell(tester, const Size(390, 844));
    final nav = find.byType(OrbitBottomNav);
    expect(nav, findsOneWidget);
    final add = find.descendant(of: nav, matching: find.text('Add'));
    expect(add, findsOneWidget);
    await tester.tap(add);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byType(ImportScreen), findsOneWidget);
  });

  testWidgets('mini dock names the system and the last play', (tester) async {
    await pumpMiniDock(tester, onResume: () {}, onMore: () {});
    expect(find.textContaining('GameCube'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'last played', caseSensitive: false)),
      findsOneWidget,
    );
  });

  testWidgets('mini dock has a labelled Resume that responds to taps', (
    tester,
  ) async {
    var resumed = 0;
    var more = 0;
    await pumpMiniDock(
      tester,
      onResume: () => resumed++,
      onMore: () => more++,
    );
    final dock = find.byType(GameDock);
    final resume = find.descendant(of: dock, matching: find.text('Resume'));
    expect(resume, findsOneWidget);
    await tester.tap(resume);
    expect(resumed, 1);
    await tester.tap(find.byTooltip('More options'));
    expect(more, 1);
    expect(tester.renderObject<RenderBox>(dock).size.height, lessThanOrEqualTo(68));
  });
}

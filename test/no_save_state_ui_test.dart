// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/player_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/theme/tokens.dart';

/// A core that cannot serialize — its `retro_serialize_size` is 0, as the
/// LCD-handheld core's is — must never be offered a snapshot it can only fail
/// to take. The pause menu is the only place that affordance appears, so the
/// contract is asserted there, in every shape it can take:
///
///   * "Save snapshot" and "Load snapshot" stay in place (the menu keeps its
///     shape) but are disabled and say "No saves";
///   * no "Snapshots" heading promises a list that can never fill;
///   * tapping either row does nothing — no toast, and certainly no Dart
///     `Bad state: Core does not support save states` in the player's face;
///   * Restart and Quit stop promising a snapshot they will not take.
AppState _state() {
  final state = AppState.ephemeral();
  state.games = const [
    GameEntry(
      id: 'handheld',
      title: 'Handheld Game',
      system: 'lcdhandheld',
      extension: 'mgw',
      filePath: '/games/handheld.mgw',
      coreId: 'gw',
    ),
  ];
  return state;
}

Future<ui.Image> _frame(WidgetTester tester) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 120, 90),
    Paint()..color = const Color(0xFF003341),
  );
  final picture = recorder.endRecording();
  final image = await tester.runAsync(() async {
    final image = await picture.toImage(120, 90);
    picture.dispose();
    return image;
  });
  return image!;
}

/// Pumps the player with a preview whose core has no save states.
Future<void> _pump(
  WidgetTester tester, {
  AppState? state,
  Size size = const Size(1440, 900),
}) async {
  final app = state ?? _state();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(app.dispose);
  final frame = await _frame(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: Tokens.theme(),
      home: PlayerScreen(
        gameId: 'handheld',
        state: app,
        preview: PlayerPreview(
          frame: frame,
          sessionMinutes: 4,
          saveStates: false,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.byKey(const Key('player-hud')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  testWidgets('the save row is disabled and says why', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('pause-row-save')), findsOneWidget);
    // Both save and load say it: neither can work without states.
    expect(find.text('No saves'), findsNWidgets(2));
  });

  testWidgets('tapping save does nothing instead of erroring', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('pause-row-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.text('Snapshot saved'), findsNothing);
  });

  testWidgets('the load row is disabled too', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('pause-row-load')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pause-row-load')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.text('Snapshot loaded'), findsNothing);
  });

  testWidgets('no Snapshots heading promises a list that cannot fill', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Snapshots'), findsNothing);
  });

  testWidgets('restart does not promise a snapshot it will not take', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('pause-row-restart')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('no save states'), findsOneWidget);
    expect(find.textContaining('A snapshot of this moment'), findsNothing);
  });

  testWidgets('quitting says the game will start over', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('pause-row-quit')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Back to the library?'), findsOneWidget);
    expect(find.textContaining('no save states'), findsOneWidget);
    expect(find.textContaining('takes a snapshot'), findsNothing);
  });

  testWidgets('the phone sheet keeps its shape without snapshot copy', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 844));
    for (final id in const ['save', 'load']) {
      expect(find.byKey(ValueKey('pause-sheet-$id')), findsOneWidget);
    }
    expect(find.text('Snapshots'), findsNothing);
  });
}

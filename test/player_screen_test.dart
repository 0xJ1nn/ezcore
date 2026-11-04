import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/controls/control_overlay.dart';
import 'package:ezcore/models/cheat.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/player_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/save_sync.dart';
import 'package:ezcore/theme/tokens.dart';

/// A save provider with fixed timestamps, so the snapshot copy is stable.
class _FixedSaves implements SaveSyncProvider {
  _FixedSaves(this.slots);
  final Map<String, List<SaveSlot>> slots;
  final Map<String, Map<String, Uint8List>> _bytes = {};

  @override
  String get id => 'test';

  @override
  Future<List<SaveSlot>> list(String gameId) async =>
      List<SaveSlot>.from(slots[gameId] ?? const []);

  @override
  Future<Uint8List?> download(String gameId, String slot) async =>
      _bytes[gameId]?[slot];

  @override
  Future<void> upload(String gameId, String slot, Uint8List bytes) async {
    _bytes.putIfAbsent(gameId, () => {})[slot] = bytes;
  }

  @override
  Future<void> remove(String gameId, String slot) async {
    _bytes[gameId]?.remove(slot);
  }
}

AppState _state({SaveSyncProvider? saves}) {
  final state = saves == null
      ? AppState.ephemeral()
      : AppState.internal(persistence: null, saves: saves);
  state.games = const [
    GameEntry(
      id: 'lanterns',
      title: 'Lanterns of Vell',
      system: 'nds',
      extension: 'nds',
      filePath: '/games/lanterns.nds',
      coreId: 'dualscreen',
    ),
  ];
  state.cheatsByGame['lanterns'] = const [
    CheatEntry(index: 0, desc: 'Infinite health', code: '00', enabled: true),
    CheatEntry(index: 1, desc: 'Max gold', code: '01', enabled: true),
  ];
  return state;
}

AppState _gbaState() {
  final state = _state();
  state.games = const [
    GameEntry(
      id: 'starfall',
      title: 'Starfall Courier',
      system: 'gba',
      extension: 'gba',
      filePath: '/games/starfall.gba',
      coreId: 'advancebit',
    ),
  ];
  state.cheatsByGame.remove('lanterns');
  return state;
}

Future<ui.Image> _frame(WidgetTester tester, Size size) async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(Offset.zero & size, Paint()..color = const Color(0xFF003341));
  final picture = recorder.endRecording();
  final image = await tester.runAsync(() async {
    final image = await picture.toImage(
      size.width.round(),
      size.height.round(),
    );
    picture.dispose();
    return image;
  });
  return image!;
}

Future<void> _pumpPlayer(
  WidgetTester tester, {
  required AppState state,
  String gameId = 'lanterns',
  Size size = const Size(1440, 900),
  Size frameSize = const Size(120, 90),
  bool touch = false,
  String? slot = 'auto',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final frame = await _frame(tester, frameSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: Tokens.theme(),
      home: PlayerScreen(
        gameId: gameId,
        state: state,
        initialSlot: slot,
        preview: PlayerPreview(
          frame: frame,
          touchControls: touch,
          sessionMinutes: 38,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _openPause(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('player-hud')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

Future<void> _dispose(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(const SizedBox());
  state.dispose();
}

void main() {
  // Player UI: failure chrome, the fading HUD, the receded pause layer, the
  // three device layouts, and the actions the pause menu must keep.
  testWidgets('missing core shows launch failure, not simulated gameplay', (
    tester,
  ) async {
    final state = AppState.ephemeral();
    state.addGame(
      const GameEntry(
        id: 'missing',
        title: 'Missing content',
        system: 'gba',
        extension: 'gba',
        filePath: '/missing.gba',
        coreId: 'missing',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(gameId: 'missing', state: state),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Launch failed'), findsOneWidget);
    expect(find.textContaining('Native canvas binds'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets('the HUD fades after five seconds; the launch toast says so', (
    tester,
  ) async {
    final state = _state();
    await _pumpPlayer(tester, state: state);
    expect(find.byKey(const Key('player-hud')), findsOneWidget);
    expect(find.text('Picked up where you left off'), findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
    expect(find.text('Picked up where you left off'), findsNothing);
    await _dispose(tester, state);
  });

  testWidgets('a fresh launch names the game in the toast', (tester) async {
    final state = _state();
    await _pumpPlayer(tester, state: state, slot: null);
    expect(find.text('Starting Lanterns of Vell'), findsOneWidget);
    await _dispose(tester, state);
  });

  testWidgets('the frame recedes to 56% and tilts when paused', (tester) async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 21, 30);
    final saves = _FixedSaves({
      'lanterns': [
        SaveSlot(id: 'auto', modified: now, size: 8),
        SaveSlot(id: 'slot0', modified: yesterday, size: 8),
        SaveSlot(
          id: 'slot1',
          modified: now.subtract(const Duration(days: 3)),
          size: 8,
        ),
        SaveSlot(
          id: 'crash-1',
          modified: now.subtract(const Duration(days: 8)),
          size: 8,
        ),
      ],
    });
    final state = _state(saves: saves);
    await _pumpPlayer(tester, state: state);

    await _openPause(tester);
    expect(find.text('TAKE A BREATHER'), findsOneWidget);
    for (final id in const [
      'resume',
      'save',
      'load',
      'cheats',
      'controls',
      'restart',
      'quit',
    ]) {
      expect(find.byKey(ValueKey('pause-row-$id')), findsOneWidget);
    }
    expect(find.text('4 saved'), findsOneWidget);
    expect(find.text('2 on'), findsOneWidget);
    expect(find.text('Snapshots'), findsOneWidget);
    expect(
      find.textContaining('Yesterday 21:30', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('3 days ago', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Last week', findRichText: true),
      findsOneWidget,
    );

    final recede = tester.widget<Transform>(
      find.byKey(const Key('player-frame-recede')),
    );
    final m = recede.transform;
    expect(
      math.sqrt(m.entry(0, 0) * m.entry(0, 0) + m.entry(0, 2) * m.entry(0, 2)),
      closeTo(0.56, 0.01),
    );
    expect(
      math.atan2(m.entry(0, 2), m.entry(0, 0)),
      closeTo(8 * math.pi / 180, 0.01),
    );
    await _dispose(tester, state);
  });

  testWidgets('phone portrait puts the HUD on top and the pad below the game', (
    tester,
  ) async {
    final state = _state();
    await _pumpPlayer(
      tester,
      state: state,
      size: const Size(390, 844),
      frameSize: const Size(130, 194),
      touch: true,
    );

    // The picture is full-bleed and the menu chip stays centred above it.
    expect(
      tester.getRect(find.byKey(const Key('player-frame'))),
      rectMoreOrLessEquals(const Rect.fromLTWH(0, 56, 390, 582), epsilon: 0.1),
    );
    expect(
      tester.getCenter(find.byKey(const Key('player-hud'))).dx,
      closeTo(195, 1),
    );
    final layout = tester
        .widget<ControlOverlay>(find.byType(ControlOverlay))
        .layout;
    Rect rect(String id) =>
        layout.controls.firstWhere((c) => c.id == id).rect.resolve(390, 844);
    expect(rect('a').center.dx, closeTo(344, 2));
    expect(rect('a').center.dy, closeTo(759, 2));
    expect(rect('y').center.dx, closeTo(259, 2));
    expect(rect('x').center.dy, closeTo(717, 2));
    expect(rect('b').center.dy, closeTo(801, 2));
    expect(rect('dpad').center.dx, closeTo(87.5, 2));
    expect(rect('select').center.dx, closeTo(161, 2));
    expect(rect('start').center.dx, closeTo(233, 2));
    // The touch board owns the menu, so there is no duplicate menu control.
    expect(layout.controls.any((c) => c.id == 'menu'), isFalse);
    await _dispose(tester, state);
  });

  testWidgets('phone landscape keeps the game centred and A/B in the gutter', (
    tester,
  ) async {
    final state = _gbaState();
    await _pumpPlayer(
      tester,
      state: state,
      gameId: 'starfall',
      size: const Size(844, 390),
      frameSize: const Size(120, 80),
      touch: true,
    );

    expect(
      tester.getRect(find.byKey(const Key('player-frame'))),
      rectMoreOrLessEquals(
        const Rect.fromLTWH(182, 22, 480, 320),
        epsilon: 0.01,
      ),
    );
    // The HUD gives way to the touch menu button.
    expect(find.byKey(const Key('player-hud')), findsNothing);
    final layout = tester
        .widget<ControlOverlay>(find.byType(ControlOverlay))
        .layout;
    Rect rect(String id) =>
        layout.controls.firstWhere((c) => c.id == id).rect.resolve(844, 390);
    expect(rect('a').center.dx, closeTo(779, 2));
    expect(rect('a').center.dy, closeTo(168, 2));
    expect(rect('b').center.dx, closeTo(698, 2));
    expect(rect('b').center.dy, closeTo(216, 2));
    expect(rect('l').top, closeTo(21, 2));
    expect(rect('menu').center.dx, closeTo(424, 2));
    await _dispose(tester, state);
  });

  testWidgets(
    'the phone pause sheet keeps every action and builds a 3x2 grid',
    (tester) async {
      final state = _state();
      await _pumpPlayer(
        tester,
        state: state,
        size: const Size(390, 844),
        frameSize: const Size(130, 194),
        touch: true,
      );
      await _openPause(tester);

      for (final id in const [
        'resume',
        'save',
        'load',
        'cheats',
        'controls',
        'quit',
      ]) {
        expect(find.byKey(ValueKey('pause-sheet-$id')), findsOneWidget);
      }
      expect(
        tester.getRect(find.byKey(const Key('player-frame'))),
        rectMoreOrLessEquals(
          const Rect.fromLTWH(53.5, 68, 283, 207),
          epsilon: 0.2,
        ),
      );
      // Restart moves into Controls on the phone board.
      expect(find.text('Restart game'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pause-sheet-controls')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Restart game'), findsOneWidget);
      await _dispose(tester, state);
    },
  );

  testWidgets('the phone landscape pause panel pairs six actions, no hints', (
    tester,
  ) async {
    final state = _gbaState();
    for (final id in const ['auto', 'slot0', 'slot1']) {
      await state.saves.upload('starfall', id, Uint8List(4));
    }
    await _pumpPlayer(
      tester,
      state: state,
      gameId: 'starfall',
      size: const Size(844, 390),
      frameSize: const Size(120, 80),
      touch: true,
    );
    final overlay = tester.widget<ControlOverlay>(find.byType(ControlOverlay));
    final menu = overlay.layout.controls
        .firstWhere((c) => c.id == 'menu')
        .rect
        .resolve(844, 390);
    await tester.tapAt(menu.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('TAKE A BREATHER'), findsOneWidget);
    for (final id in const [
      'resume',
      'save',
      'load',
      'cheats',
      'controls',
      'quit',
    ]) {
      expect(find.byKey(ValueKey('pause-row-$id')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('pause-row-restart')), findsNothing);
    expect(find.text('3 saved'), findsNothing);
    expect(find.text('Snapshots'), findsNothing);
    final recede = tester.widget<Transform>(
      find.byKey(const Key('player-frame-recede')),
    );
    expect(recede.transform.entry(0, 0), closeTo(0.68, 0.01));
    await _dispose(tester, state);
  });

  testWidgets('quitting the session explains that it snapshots first', (
    tester,
  ) async {
    final state = _state();
    await _pumpPlayer(tester, state: state);
    await _openPause(tester);
    await tester.tap(find.byKey(const ValueKey('pause-row-quit')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Back to the library?'), findsOneWidget);
    expect(find.textContaining('takes a snapshot'), findsOneWidget);
    await _dispose(tester, state);
  });
}

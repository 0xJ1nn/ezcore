// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/controls/control_overlay.dart';
import 'package:ezcore/emu/core_session_backend.dart';
import 'package:ezcore/models/cheat.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/player_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/save_sync.dart';
import 'package:ezcore/theme/symbols.dart';
import 'package:ezcore/theme/tokens.dart';

/// A save provider with fixed timestamps, so the snapshot copy is stable.
class _FixedSaves extends SaveSyncProvider {
  _FixedSaves(this.slots);
  final Map<String, List<SaveSlot>> slots;
  final Map<String, Map<String, Uint8List>> _bytes = {};
  final Map<String, Map<String, Uint8List>> thumbnails = {};

  /// When true, storing a still fails the way a read-only vault would.
  bool rejectStills = false;

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
    final list = slots.putIfAbsent(gameId, () => []);
    list.removeWhere((s) => s.id == slot);
    list.add(SaveSlot(id: slot, modified: DateTime.now(), size: bytes.length));
  }

  @override
  Future<void> remove(String gameId, String slot) async {
    _bytes[gameId]?.remove(slot);
    thumbnails[gameId]?.remove(slot);
  }

  @override
  Future<Uint8List?> thumbnail(String gameId, String slot) async =>
      thumbnails[gameId]?[slot];

  @override
  Future<void> putThumbnail(
    String gameId,
    String slot,
    Uint8List png,
  ) async {
    if (rejectStills) throw StateError('still folder is read-only');
    thumbnails.putIfAbsent(gameId, () => {})[slot] = png;
  }
}

/// A session backend that answers a scripted save; the preview never opens
/// a real core, so only the save path is exercised.
class _SaveBackend implements CoreSessionBackend {
  @override
  Future<bool> attachVideo(int window, int width, int height) async => false;
  int saves = 0;

  @override
  Future<Uint8List> save() async {
    saves++;
    return Uint8List.fromList([7, 7, 7, 7]);
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
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
  CoreSessionBackend? backend,
  bool frame = true,
  Future<Uint8List?> Function(ui.Image? frame)? captureStill,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final picture = frame ? await _frame(tester, frameSize) : null;
  await tester.pumpWidget(
    MaterialApp(
      theme: Tokens.theme(),
      home: PlayerScreen(
        gameId: gameId,
        state: state,
        initialSlot: slot,
        preview: PlayerPreview(
          frame: picture,
          touchControls: touch,
          backend: backend,
          captureStill: captureStill,
          sessionMinutes: 38,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

/// A PNG of a flat [size] field, the shape of a captured still.
Future<Uint8List> _stillPng(WidgetTester tester, Size size) async {
  final image = await _frame(tester, size);
  final data = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Lets a decoded still arrive. The codec's work is real async, so the test
/// waits outside its fake clock before pumping the rebuild into place.
Future<void> _settleStills(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
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
    expect(find.text('Lanterns of Vell'), findsOneWidget);
    expect(find.text('TAKE A BREATHER'), findsNothing);
    expect(
      find.text('Nintendo DS · dualscreen · session 38 min'),
      findsOneWidget,
    );
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
    expect(find.byIcon(Symbols.tune), findsOneWidget);
    expect(find.byIcon(Symbols.sportsEsports), findsNothing);
    expect(find.text('4 saved'), findsOneWidget);
    expect(find.text('2 on'), findsOneWidget);
    expect(find.text('Snapshots'), findsOneWidget);
    expect(
      find.textContaining('Slot 1 · Yesterday 21:30', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Slot 2 · 3 days ago', findRichText: true),
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
    // The receded frame keeps a soft -30px 50px 90px -24px shadow.
    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const Key('player-frame')),
        matching: find.byType(DecoratedBox),
      ),
    );
    final shadow = (decorated.decoration as BoxDecoration).boxShadow!.single;
    expect(shadow.offset, const Offset(-30, 50));
    expect(shadow.blurRadius, 90);
    expect(shadow.spreadRadius, -24);
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
    // The touch HUD uses the pause glyph, not a hamburger.
    expect(find.byIcon(Symbols.pause), findsOneWidget);
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
    // A/B are 64 px circles beside the frame; B sits 32 px past its right
    // edge at 63% height, and A is up and to the right of B.
    expect(rect('a').width, closeTo(64, 0.1));
    expect(rect('a').center.dx, closeTo(780, 2));
    expect(rect('a').center.dy, closeTo(208, 2));
    expect(rect('b').width, closeTo(64, 0.1));
    expect(rect('b').center.dx, closeTo(694, 2));
    expect(rect('b').center.dy, closeTo(246, 2));
    expect(rect('l').top, closeTo(24, 2));
    expect(rect('l').left, closeTo(24, 2));
    expect(rect('r').right, closeTo(820, 2));
    // D-pad: 140 px across, centred at 58% of the height.
    expect(rect('dpad').width, closeTo(140, 0.1));
    expect(rect('dpad').center.dy, closeTo(226, 2));
    // Bottom row: 32 px pills with a pause glyph on Menu, drawn by the bar.
    expect(rect('select').height, closeTo(32, 0.1));
    expect(rect('menu').height, closeTo(32, 0.1));
    expect(rect('menu').center.dx, closeTo(423, 2));
    expect(rect('select').right + 8, closeTo(rect('menu').left, 2));
    expect(rect('menu').right + 8, closeTo(rect('start').left, 2));
    expect(find.byIcon(Symbols.pause), findsOneWidget);
    expect(find.text('Select'), findsOneWidget);
    expect(find.text('Menu'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    await _dispose(tester, state);
  });

  testWidgets(
    'the phone pause sheet keeps every action and builds a 3x2 grid',
    (tester) async {
      final now = DateTime.now();
      final saves = _FixedSaves({
        'lanterns': [
          SaveSlot(
            id: 'auto',
            modified: now.subtract(const Duration(minutes: 1)),
            size: 8,
          ),
          SaveSlot(id: 'slot0', modified: now, size: 8),
          SaveSlot(id: 'slot1', modified: now, size: 8),
        ],
      });
      final state = _state(saves: saves);
      await _pumpPlayer(
        tester,
        state: state,
        size: const Size(390, 844),
        frameSize: const Size(130, 194),
        touch: true,
      );
      await _openPause(tester);

      expect(find.textContaining('Session 38 min'), findsOneWidget);
      expect(find.textContaining('autosaved 1 min ago'), findsOneWidget);
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
      // The still above the sheet tilts back: top edge a little narrower.
      final tilt = tester.widget<Transform>(
        find.byKey(const Key('player-frame-tilt')),
      );
      expect(tilt.transform.entry(3, 2), greaterThan(0));
      expect(tilt.transform.entry(1, 2), greaterThan(0));
      // Snapshot labels are plain 600 11 px text, not chips.
      expect(find.text('TAKE A BREATHER'), findsNothing);
      final auto = tester.widget<Text>(find.text('Auto'));
      expect(auto.style?.fontSize, 11);
      expect(auto.style?.fontWeight, FontWeight.w600);
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

    expect(find.text('Starfall Courier'), findsOneWidget);
    expect(find.text('TAKE A BREATHER'), findsNothing);
    expect(find.byIcon(Symbols.tune), findsOneWidget);
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
    final auto = tester.widget<Text>(find.text('Auto'));
    expect(auto.style?.fontSize, 11);
    expect(auto.style?.fontWeight, FontWeight.w600);
    // The landscape preview tilts like the desktop one: rotateY 8°.
    final recede = tester.widget<Transform>(
      find.byKey(const Key('player-frame-recede')),
    );
    final m = recede.transform;
    expect(
      math.sqrt(m.entry(0, 0) * m.entry(0, 0) + m.entry(0, 2) * m.entry(0, 2)),
      closeTo(0.68, 0.01),
    );
    expect(
      math.atan2(m.entry(0, 2), m.entry(0, 0)),
      closeTo(8 * math.pi / 180, 0.01),
    );
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

  testWidgets('a still paints on its card; a slot without one keeps stripes', (
    tester,
  ) async {
    final now = DateTime.now();
    final saves = _FixedSaves({
      'lanterns': [
        SaveSlot(id: 'auto', modified: now, size: 8),
        SaveSlot(id: 'slot0', modified: now, size: 8),
      ],
    });
    saves.thumbnails['lanterns'] = {
      'auto': await _stillPng(tester, const Size(120, 90)),
    };
    final state = _state(saves: saves);
    await _pumpPlayer(tester, state: state);
    await _settleStills(tester);
    await _openPause(tester);

    expect(find.byKey(const ValueKey('snapshot-still-auto')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('snapshot-placeholder-auto')),
      findsNothing,
    );
    // The slot with no captured still is the design's placeholder.
    expect(
      find.byKey(const ValueKey('snapshot-placeholder-slot0')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('snapshot-still-slot0')), findsNothing);
    final still = tester.widget<RawImage>(
      find.byKey(const ValueKey('snapshot-still-auto')),
    );
    expect(still.fit, BoxFit.cover);
    await _dispose(tester, state);
  });

  testWidgets('saving a snapshot stores a still for both slots it writes', (
    tester,
  ) async {
    final saves = _FixedSaves({'lanterns': <SaveSlot>[]});
    final backend = _SaveBackend();
    final state = _state(saves: saves);
    await _pumpPlayer(tester, state: state, backend: backend);
    await _openPause(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('pause-row-save')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(backend.saves, 2);
    final stills = saves.thumbnails['lanterns'] ?? const {};
    expect(stills.keys, contains('slot0'));
    expect(stills.keys.where((id) => id.startsWith('slot-')), hasLength(1));
    // The bytes are a PNG, not the state's own payload.
    expect(stills['slot0']!.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    await _dispose(tester, state);
  });

  testWidgets('a save with no picture still writes both snapshots', (
    tester,
  ) async {
    final saves = _FixedSaves({'lanterns': <SaveSlot>[]});
    final state = _state(saves: saves);
    await _pumpPlayer(
      tester,
      state: state,
      backend: _SaveBackend(),
      frame: false,
    );
    await _openPause(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('pause-row-save')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final ids = (await saves.list('lanterns')).map((s) => s.id).toSet();
    expect(ids, contains('slot0'));
    expect(ids.where((id) => id.startsWith('slot-')), hasLength(1));
    expect(saves.thumbnails, isEmpty);
    await _dispose(tester, state);
  });

  testWidgets('a save whose still cannot be stored keeps the snapshot', (
    tester,
  ) async {
    final saves = _FixedSaves({'lanterns': <SaveSlot>[]})
      ..rejectStills = true;
    final state = _state(saves: saves);
    await _pumpPlayer(tester, state: state, backend: _SaveBackend());
    await _openPause(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('pause-row-save')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final ids = (await saves.list('lanterns')).map((s) => s.id).toSet();
    expect(ids, contains('slot0'));
    expect(ids.where((id) => id.startsWith('slot-')), hasLength(1));
    expect(find.text('Snapshot saved'), findsOneWidget);
    await _dispose(tester, state);
  });

  testWidgets('a capture that throws still saves both snapshots', (
    tester,
  ) async {
    final saves = _FixedSaves({'lanterns': <SaveSlot>[]});
    final state = _state(saves: saves);
    await _pumpPlayer(
      tester,
      state: state,
      backend: _SaveBackend(),
      captureStill: (_) async => throw StateError('encoder is busy'),
    );
    await _openPause(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('pause-row-save')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final ids = (await saves.list('lanterns')).map((s) => s.id).toSet();
    expect(ids, contains('slot0'));
    expect(ids.where((id) => id.startsWith('slot-')), hasLength(1));
    expect(saves.thumbnails, isEmpty);
    expect(find.text('Snapshot saved'), findsOneWidget);
    await _dispose(tester, state);
  });

  testWidgets('a save flashes the frame white, then clears it', (tester) async {
    final saves = _FixedSaves({'lanterns': <SaveSlot>[]});
    final state = _state(saves: saves);
    await _pumpPlayer(tester, state: state, backend: _SaveBackend());
    await _openPause(tester);
    expect(find.byKey(const Key('player-flash')), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('pause-row-save')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final flash = tester.widget<ColoredBox>(
      find.byKey(const Key('player-flash')),
    );
    // A white shutter over the picture.
    expect(flash.color.r, 1);
    expect(flash.color.g, 1);
    expect(flash.color.b, 1);
    expect(flash.color.a, greaterThan(0.2));

    // The flash clears on its own timer, so the wait is real time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('player-flash')), findsNothing);
    await _dispose(tester, state);
  });

  testWidgets('reduced motion holds the flash at 40% and drops the fade', (
    tester,
  ) async {
    final saves = _FixedSaves({'lanterns': <SaveSlot>[]});
    final state = _state(saves: saves);
    await state.setSetting('motion', false);
    await _pumpPlayer(tester, state: state, backend: _SaveBackend());
    await _openPause(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('pause-row-save')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final flash = tester.widget<ColoredBox>(
      find.byKey(const Key('player-flash')),
    );
    expect(flash.color.a, closeTo(0.4, 0.001));
    await _dispose(tester, state);
  });
}

// The game page: play or resume, saves with readable names, core choice,
// favourite and remove. And visible keyboard/controller focus on tiles.
import 'dart:convert';

import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/game_detail_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/save_sync.dart';
import 'package:ezcore/theme/symbols.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/focus_glow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A save provider with the fixed ages the device renders show.
class _TimedSaves implements SaveSyncProvider {
  _TimedSaves(this.times);
  final Map<String, DateTime> times;

  @override
  String get id => 'test';

  @override
  Future<List<SaveSlot>> list(String gameId) async => [
    for (final e in times.entries)
      SaveSlot(id: e.key, modified: e.value, size: 3),
  ];

  @override
  Future<Uint8List?> download(String gameId, String slot) async =>
      Uint8List.fromList(const [1, 2, 3]);

  @override
  Future<void> upload(String gameId, String slot, Uint8List bytes) async {
    times[slot] = DateTime.now();
  }

  @override
  Future<void> remove(String gameId, String slot) async {
    times.remove(slot);
  }
}

CoreManifest core(String id) => CoreManifest(
  id: id,
  name: id.toUpperCase(),
  version: '1',
  license: 'MIT',
  systems: const ['gba'],
  extensions: const ['gba'],
  cheatFamilies: const [],
  cheatsSupported: false,
  delivery: const {},
  artifacts: const {'x': 'p'},
);

void main() {
  Future<AppState> pump(
    WidgetTester t, {
    List<String> slots = const [],
    Size size = const Size(1280, 900),
    SaveSyncProvider? saves,
    int? year,
    int fileSize = 0,
    bool favorite = false,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    // A previous pump in the same test may have left a route open.
    await t.pumpWidget(const SizedBox.shrink());
    final s = saves == null
        ? AppState.ephemeral()
        : AppState.internal(persistence: null, saves: saves);
    for (final c in [core('alpha'), core('beta')]) {
      s.registry.loadCatalog({c.id: jsonEncode(c.toJson())});
      s.registry.install(c, expectedSha256: 'p');
    }
    s.games = [
      GameEntry(
        id: 'g',
        title: 'Hollow Orbit',
        system: 'gba',
        filePath: '/games/fusion.gba',
        extension: 'gba',
        coreId: 'alpha',
        lastPlayedMs: 1758000000000,
        fileSize: fileSize,
        year: year,
        favorite: favorite,
      ),
    ];
    if (saves == null) {
      for (final slot in slots) {
        await s.saves.upload('g', slot, Uint8List.fromList([1, 2, 3]));
      }
    }
    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GameDetailScreen(gameId: 'g', state: s),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return s;
  }

  test('saves get readable names', () {
    expect(saveName('auto'), 'Autosave');
    expect(saveName('slot0'), 'Quick save');
    expect(saveName('slot1'), 'Slot 1');
    expect(saveName('slot-142233'), 'Saved 14:22:33');
    expect(saveName('custom'), 'custom');
  });

  test('snapshot tags mark the automatic and crash-safe saves', () {
    expect(snapshotTag('auto'), 'Auto');
    expect(snapshotTag('slot1'), isNull);
    expect(snapshotTag('recovered'), 'Crash-safe');
    expect(snapshotTagColor('auto'), Tokens.systemLabelFg);
    expect(snapshotTagColor('recovered'), Tokens.warn);
  });

  testWidgets('no saves: Play, and an explanation', (t) async {
    await pump(t);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Resume'), findsNothing);
    expect(find.textContaining('No snapshots yet'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('an automatic save offers Resume and Play from start', (t) async {
    await pump(
      t,
      slots: ['auto', 'slot0', 'slot-101500'],
      size: const Size(1440, 900),
    );
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Play from start'), findsOneWidget);
    expect(find.text('Autosave'), findsOneWidget);
    expect(find.text('Quick save'), findsOneWidget);
    expect(find.text('Saved 10:15:00'), findsOneWidget);
  });

  testWidgets('desktop carries the design header, stats, actions and cards', (
    t,
  ) async {
    await pump(
      t,
      slots: ['auto', 'slot1', 'slot2', 'recovered'],
      size: const Size(1440, 900),
    );
    expect(find.text('PLAYED'), findsOneWidget);
    expect(find.text('LAST PLAYED'), findsOneWidget);
    expect(find.text('SNAPSHOTS'), findsOneWidget);
    expect(find.text('CORE'), findsOneWidget);
    expect(find.text('Choose one to jump back in'), findsOneWidget);
    expect(find.text('Autosave'), findsOneWidget);
    expect(find.text('Slot 1'), findsOneWidget);
    expect(find.text('Recovered'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('Crash-safe'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);
  });

  testWidgets('phone drops the stat strip and keeps full-width actions', (
    t,
  ) async {
    await pump(t, slots: ['auto'], size: const Size(390, 844));
    expect(find.text('PLAYED'), findsNothing);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('From start'), findsOneWidget);
    expect(find.text('Snapshots'), findsOneWidget);
  });

  for (final size in const [
    Size(390, 844),
    Size(844, 390),
    Size(820, 1180),
    Size(1180, 820),
    Size(1280, 900),
    Size(1440, 900),
  ]) {
    testWidgets('no overflow at $size', (t) async {
      await pump(t, slots: ['auto', 'slot0'], size: size);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('deleting a snapshot asks first', (t) async {
    final s = await pump(t, slots: ['slot0']);
    await t.longPress(find.byKey(const Key('snapshot-slot0')));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete snapshot'));
    await t.pumpAndSettle();
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(await s.saves.list('g'), isEmpty);
    expect(find.byKey(const Key('snapshot-slot0')), findsNothing);
  });

  testWidgets('choosing another core is remembered', (t) async {
    final s = await pump(t);
    await t.tap(find.textContaining('ALPHA'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('BETA').last);
    await t.pumpAndSettle();
    expect(s.games.single.coreId, 'beta');
  });

  testWidgets('favourite toggles; remove asks and keeps the file', (t) async {
    final s = await pump(t);
    await t.tap(find.byTooltip('Add to favourites'));
    await t.pump();
    expect(s.games.single.favorite, isTrue);
    await t.longPress(find.text('Hollow Orbit').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Remove from library'));
    await t.pumpAndSettle();
    expect(find.textContaining('is not deleted'), findsOneWidget);
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(s.games, isEmpty);
  });

  testWidgets('desktop carries the full design header and card names', (
    t,
  ) async {
    await pump(
      t,
      slots: ['auto', 'slot1'],
      size: const Size(1440, 900),
      year: 2008,
      fileSize: 64 << 20,
    );
    expect(
      find.text('2008'),
      findsNWidgets(2),
      reason: 'the cover and the year chip both carry it',
    );
    expect(find.text('64.0 MB'), findsOneWidget);
    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('Play from start'), findsOneWidget);
    expect(find.text('Autosave'), findsOneWidget);
    expect(find.text('Choose one to jump back in'), findsOneWidget);
    expect(
      find.text('—'),
      findsOneWidget,
      reason: 'playtime is not tracked, so the value stays honest',
    );
  });

  testWidgets('tablet folds year and size into one chip and drops hints', (
    t,
  ) async {
    await pump(
      t,
      slots: ['auto', 'slot1'],
      size: const Size(1180, 820),
      year: 2008,
      fileSize: 64 << 20,
    );
    expect(find.text('2008 · 64.0 MB'), findsOneWidget);
    expect(
      find.text('2008'),
      findsOneWidget,
      reason: 'the cover keeps its year; the chip folds it in',
    );
    expect(find.text('Enter'), findsNothing);
    expect(find.text('From start'), findsOneWidget);
    expect(find.text('Choose one to jump back in'), findsNothing);
    expect(find.text('Autosave'), findsNothing);
    expect(
      find.text('Slot 1'),
      findsOneWidget,
      reason: 'the slot name moves into the thumbnail tag',
    );
    expect(find.text('when you stopped'), findsOneWidget);
  });

  testWidgets('phone uses the compact chip, blue heart and 3a action stack', (
    t,
  ) async {
    await pump(
      t,
      slots: ['auto'],
      size: const Size(390, 844),
      year: 2008,
      fileSize: 64 << 20,
      favorite: true,
    );
    expect(find.text('GAME BOY ADVANCE · 2008'), findsOneWidget);
    expect(find.text('64.0 MB'), findsNothing);
    expect(find.text('Enter'), findsNothing);
    expect(find.text('From start'), findsOneWidget);
    expect(find.text('Autosave'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Icon &&
            w.icon == Symbols.favorite &&
            w.fill == 1 &&
            w.color == Tokens.iconBlue,
      ),
      findsOneWidget,
      reason: 'the favourite heart is the accent blue in the phone bar',
    );
  });

  testWidgets('compact families shorten yesterday to the day', (t) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final saves = _TimedSaves({
      'auto': now.subtract(const Duration(minutes: 20)),
      'slot1': today
          .subtract(const Duration(days: 1))
          .add(const Duration(hours: 21, minutes: 30)),
    });
    await pump(t, size: const Size(390, 844), saves: saves);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Yesterday 21:30'), findsNothing);

    await pump(t, size: const Size(1440, 900), saves: saves);
    expect(find.text('Yesterday 21:30'), findsOneWidget);
    expect(find.text('Yesterday'), findsNothing);
  });

  testWidgets('keyboard focus shows a ring and Enter activates', (t) async {
    var taps = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: FocusGlow(
              onTap: () => taps++,
              child: const SizedBox(width: 80, height: 80),
            ),
          ),
        ),
      ),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pumpAndSettle();
    final box = t.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final border = (box.decoration as BoxDecoration).border as Border;
    expect(border.top.color, Tokens.accentHi, reason: 'focus ring visible');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(taps, 1);
  });
}

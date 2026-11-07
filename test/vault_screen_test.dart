import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/vault_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/save_sync.dart';
import 'package:ezcore/theme/symbols.dart';
import 'package:ezcore/theme/tokens.dart';

/// A vault with fixed slot times and sizes, so the timeline's order and copy
/// can be asserted without depending on when the test runs.
class _FixedSaves implements SaveSyncProvider {
  _FixedSaves(this.slots);
  final Map<String, List<SaveSlot>> slots;

  @override
  String get id => 'local';

  @override
  Future<List<SaveSlot>> list(String gameId) async =>
      List<SaveSlot>.of(slots[gameId] ?? const []);

  @override
  Future<Uint8List?> download(String gameId, String slot) async => Uint8List(1);

  @override
  Future<void> upload(String gameId, String slot, Uint8List bytes) async {
    final list = slots.putIfAbsent(gameId, () => []);
    list.removeWhere((s) => s.id == slot);
    list.insert(
      0,
      SaveSlot(id: slot, modified: DateTime.now(), size: bytes.length),
    );
  }

  @override
  Future<void> remove(String gameId, String slot) async {
    slots[gameId]?.removeWhere((s) => s.id == slot);
  }
}

const _mb = 1024 * 1024;

AppState _state(_FixedSaves saves, {List<GameEntry>? games}) {
  final state = AppState.internal(persistence: null, saves: saves);
  state.games =
      games ??
      const [
        GameEntry(
          id: 'lanterns',
          title: 'Lanterns of Vell',
          system: 'nds',
          filePath: '/Games/lanterns.nds',
          extension: 'nds',
          stateCount: 4,
        ),
      ];
  return state;
}

_FixedSaves _designVault() {
  final now = DateTime.now();
  final yesterday = now.subtract(const Duration(days: 1));
  DateTime yAt(int hour, int minute) =>
      DateTime(yesterday.year, yesterday.month, yesterday.day, hour, minute);
  return _FixedSaves({
    'lanterns': [
      SaveSlot(
        id: 'auto',
        modified: now.subtract(const Duration(minutes: 5)),
        size: 512 * _mb,
      ),
      SaveSlot(id: 'slot 1', modified: yAt(21, 30), size: 256 * _mb),
      SaveSlot(
        id: 'slot 2',
        modified: now.subtract(const Duration(days: 3)),
        size: 128 * _mb,
      ),
      SaveSlot(
        id: 'crash-safe',
        modified: now.subtract(const Duration(days: 8)),
        size: 128 * _mb,
      ),
    ],
  });
}

Future<void> _pump(WidgetTester tester, AppState state, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: Tokens.theme(),
      home: Scaffold(body: VaultScreen(state: state)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('desktop shows per-game rails with tagged snapshots', (
    tester,
  ) async {
    final saves = _designVault();
    await _pump(tester, _state(saves), const Size(1440, 900));

    expect(find.text('EVERY SAVE. EVERY GAME.'), findsOneWidget);
    expect(find.text('Your time capsule'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Your time capsule')).dx, 48);
    expect(find.text('Local vault'), findsOneWidget);
    // 1.0 GB of snapshots in a 64 GB vault.
    expect(find.text('1.0 GB of 64 GB'), findsOneWidget);
    expect(find.text('Kept on this device only'), findsOneWidget);

    expect(find.text('4 snapshots · Nintendo DS'), findsOneWidget);
    for (final tag in ['Auto', 'Slot 1', 'Slot 2', 'Crash-safe']) {
      expect(find.text(tag), findsOneWidget, reason: tag);
    }
    expect(find.text('when you stopped'), findsOneWidget);
    expect(find.text('Yesterday 21:30'), findsOneWidget);
    expect(find.text('3 days ago'), findsOneWidget);
    expect(find.text('Last week'), findsOneWidget);
  });

  testWidgets('phone portrait becomes one vertical timeline, newest first', (
    tester,
  ) async {
    final saves = _designVault();
    await _pump(tester, _state(saves), const Size(390, 844));

    // The vault meter collapses to one line under the title, and the header
    // keeps the design's 24 px phone margin instead of the rail's 48.
    expect(find.text('1.0 GB · kept on this device only'), findsOneWidget);
    expect(tester.getTopLeft(find.text('EVERY SAVE. EVERY GAME.')).dx, 24);
    expect(tester.getTopLeft(find.text('Your time capsule')).dx, 24);
    final eyebrow = tester.widget<Text>(find.text('EVERY SAVE. EVERY GAME.'));
    expect(eyebrow.style?.fontSize, 13);

    // The card title steps down to the phone type scale while the slot
    // subtitle keeps its 12.5 px floor.
    final cardTitle = tester.widget<Text>(find.text('Lanterns of Vell').first);
    expect(cardTitle.style?.fontSize, 15.5);

    // Per-game count copy belongs to the rails layout only.
    expect(find.text('4 snapshots · Nintendo DS'), findsNothing);
    expect(find.textContaining('Autosave ·'), findsOneWidget);

    double topOf(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(topOf('Auto'), lessThan(topOf('Slot 1')));
    expect(topOf('Slot 1'), lessThan(topOf('Slot 2')));
    expect(topOf('Slot 2'), lessThan(topOf('Crash-safe')));
  });

  testWidgets(
    'phone portrait flattens games newest first and labels crash-safe',
    (tester) async {
      final now = DateTime.now();
      final saves = _FixedSaves({
        'lanterns': [
          SaveSlot(
            id: 'auto',
            modified: now.subtract(const Duration(minutes: 5)),
            size: 2 * _mb,
          ),
          SaveSlot(
            id: 'slot 1',
            modified: now.subtract(const Duration(days: 2)),
            size: _mb,
          ),
        ],
        'aurora': [
          SaveSlot(
            id: 'auto',
            modified: now.subtract(const Duration(minutes: 10)),
            size: _mb,
          ),
        ],
        'tidal': [
          SaveSlot(
            id: 'crash-safe',
            modified: now.subtract(const Duration(days: 3)),
            size: _mb,
          ),
        ],
      });
      await _pump(
        tester,
        _state(
          saves,
          games: const [
            GameEntry(
              id: 'lanterns',
              title: 'Lanterns of Vell',
              system: 'nds',
              filePath: '/Games/lanterns.nds',
              extension: 'nds',
              stateCount: 2,
            ),
            GameEntry(
              id: 'aurora',
              title: 'Aurora Run',
              system: 'gba',
              filePath: '/Games/aurora.gba',
              extension: 'gba',
              stateCount: 1,
            ),
            GameEntry(
              id: 'tidal',
              title: 'Tidal Arcana',
              system: 'snes',
              filePath: '/Games/tidal.sfc',
              extension: 'sfc',
              stateCount: 1,
            ),
          ],
        ),
        const Size(390, 844),
      );

      expect(find.textContaining('Autosave ·'), findsNWidgets(2));
      expect(find.text('Recovered after a crash'), findsOneWidget);

      double topOf(Finder finder) => tester.getTopLeft(finder).dy;
      final lanternsAuto = find.text('Lanterns of Vell').first;
      expect(topOf(lanternsAuto), lessThan(topOf(find.text('Aurora Run'))));
      expect(
        topOf(find.text('Aurora Run')),
        lessThan(topOf(find.text('Tidal Arcana'))),
      );
    },
  );

  testWidgets('phone landscape keeps the rails and drops the eyebrow', (
    tester,
  ) async {
    await _pump(tester, _state(_designVault()), const Size(844, 390));

    expect(find.text('Your time capsule'), findsOneWidget);
    expect(find.text('EVERY SAVE. EVERY GAME.'), findsNothing);
    expect(find.text('Local vault'), findsOneWidget);
    expect(find.text('4 snapshots · Nintendo DS'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Your time capsule')).dx, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet portrait keeps the eyebrow and the vault budget', (
    tester,
  ) async {
    await _pump(tester, _state(_designVault()), const Size(820, 1180));

    expect(find.text('EVERY SAVE. EVERY GAME.'), findsOneWidget);
    expect(find.text('1.0 GB of 64 GB'), findsOneWidget);
    expect(find.text('4 snapshots · Nintendo DS'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Your time capsule')).dx, 48);
    final title = tester.widget<Text>(find.text('Your time capsule'));
    expect(title.style?.fontSize, 44);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone rows keep the delete and Undo actions', (tester) async {
    final saves = _designVault();
    await _pump(tester, _state(saves), const Size(390, 844));

    await tester.longPress(find.text('Auto'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.text('Delete snapshot'), findsOneWidget);

    await tester.tap(find.text('Delete snapshot'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(saves.slots['lanterns']!.any((s) => s.id == 'auto'), isFalse);
    expect(find.text('Snapshot deleted'), findsOneWidget);
    final toastIcon = tester.widget<Icon>(find.byIcon(Symbols.delete));
    expect(toastIcon.color, Tokens.text);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(saves.slots['lanterns']!.any((s) => s.id == 'auto'), isTrue);
  });

  testWidgets('long-press delete offers Undo that restores the snapshot', (
    tester,
  ) async {
    final saves = _designVault();
    await _pump(tester, _state(saves), const Size(1440, 900));

    await tester.longPress(find.text('Auto'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.text('Delete snapshot'), findsOneWidget);

    await tester.tap(find.text('Delete snapshot'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(saves.slots['lanterns']!.any((s) => s.id == 'auto'), isFalse);
    expect(find.text('Snapshot deleted'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(saves.slots['lanterns']!.any((s) => s.id == 'auto'), isTrue);
    expect(find.text('Auto'), findsOneWidget);
  });

  testWidgets('empty vault keeps the honest empty state', (tester) async {
    await _pump(tester, _state(_FixedSaves({})), const Size(1440, 900));
    expect(find.text('Your time capsule'), findsOneWidget);
    expect(find.text('Empty'), findsOneWidget);
    expect(find.text('No moments saved yet.'), findsOneWidget);
  });
}

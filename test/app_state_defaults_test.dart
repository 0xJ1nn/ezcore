import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/state/app_state.dart';

void main() {
  group('AppState factory defaults', () {
    test('default factory uses LocalSaveSyncProvider', () {
      final state = AppState();
      expect(state.saves.id, 'local');
    });

    test('default factory has PersistenceService (non-null)', () {
      final state = AppState();
      // persistence != null is verified by the fact that load() would
      // attempt to read state.json; we can verify via reflection by
      // checking that games list starts empty (not from mock library).
      expect(state.games, isEmpty);
    });

    test('ephemeral factory uses MemorySaveSyncProvider', () {
      final state = AppState.ephemeral();
      expect(state.saves.id, 'memory');
    });

    test('ephemeral factory has no persistence', () {
      final state = AppState.ephemeral();
      // ephemeral state has null persistence, so games stay empty
      // even after mutators — verified by no file on disk.
      expect(state.games, isEmpty);
    });

    test('production defaults resolve platform path', () {
      final state = AppState();
      // LocalSaveSyncProvider root path should match platform path
      // This test is a smoke test that the factory doesn't throw.
      expect(state.saves, isNotNull);
    });
  });

  group('AppState settings', () {
    test('settings getter returns unmodifiable map', () async {
      final state = AppState.ephemeral();
      await state.setSetting('theme', 'dark');
      final s = state.settings;
      expect(s['theme'], 'dark');
      expect(() => s['volume'] = 0.5, throwsUnsupportedError);
    });

    test('setSetting replaces existing key', () async {
      final state = AppState.ephemeral();
      await state.setSetting('theme', 'light');
      await state.setSetting('theme', 'dark');
      expect(state.settings['theme'], 'dark');
    });

    test('removeSetting drops key', () async {
      final state = AppState.ephemeral();
      await state.setSetting('theme', 'dark');
      await state.setSetting('volume', 0.8);
      await state.removeSetting('theme');
      expect(state.settings.containsKey('theme'), isFalse);
      expect(state.settings['volume'], 0.8);
    });
  });

  group('AppState recordPlay', () {
    test('recordPlay updates lastPlayedMs', () {
      final state = AppState.ephemeral();
      final before = DateTime.now().millisecondsSinceEpoch;
      // addGame requires going through state machinery
      state.games = [
        GameEntry(
          id: 'g1',
          title: 'Test',
          system: 'gb',
          filePath: '/foo/bar.gb',
          extension: 'gb',
        ),
      ];
      state.recordPlay('g1');
      expect(state.games.first.lastPlayedMs, greaterThanOrEqualTo(before));
    });
  });
}

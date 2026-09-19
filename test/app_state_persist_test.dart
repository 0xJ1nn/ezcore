import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/cheat.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:ezcore/services/persistence_service.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/save_sync.dart';

class FakeLocalDataDirProvider implements LocalDataDirProvider {
  FakeLocalDataDirProvider(this.dir);
  final Directory dir;

  @override
  Future<Directory> localDataDir() async => dir;

  @override
  String localDataDirPath() => dir.path;
}

void main() {
  late Directory tmpDir;
  late FakeLocalDataDirProvider dirProvider;
  late PersistenceService persistence;
  late LocalSaveSyncProvider saves;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('ezcore_appstate');
    dirProvider = FakeLocalDataDirProvider(tmpDir);
    persistence = PersistenceService(dirProvider);
    saves = LocalSaveSyncProvider(tmpDir);
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  group('AppState persistence round-trip', () {
    test('games persist across AppState instances', () async {
      final state1 = AppState.internal(persistence: persistence, saves: saves);
      state1.games = [
        GameEntry(
          id: 'g1',
          title: 'Test Game',
          system: 'gb',
          filePath: '/foo/bar.gb',
          extension: 'gb',
          coreId: 'pocketbit',
        ),
      ];
      await state1.persist();

      final state2 = AppState.internal(
        persistence: PersistenceService(dirProvider),
        saves: LocalSaveSyncProvider(tmpDir),
      );
      final loaded = await state2.persistence!.load();
      expect(loaded.games.length, 1);
      expect(loaded.games.first.id, 'g1');
      expect(loaded.games.first.title, 'Test Game');
    });

    test('cheats persist across AppState instances', () async {
      final state1 = AppState.internal(persistence: persistence, saves: saves);
      state1.cheatsByGame['g1'] = [
        CheatEntry(index: 0, desc: 'Infinite lives', code: 'ABC', enabled: true),
      ];
      await state1.persist();

      final state2 = AppState.internal(
        persistence: PersistenceService(dirProvider),
        saves: LocalSaveSyncProvider(tmpDir),
      );
      final loaded = await state2.persistence!.load();
      expect(loaded.cheatsByGame['g1'], isNotNull);
      expect(loaded.cheatsByGame['g1']!.length, 1);
    });

    test('settings persist across AppState instances', () async {
      final state1 = AppState.internal(persistence: persistence, saves: saves);
      await state1.setSetting('theme', 'dark');
      await state1.setSetting('volume', 0.8);
      await state1.persist();

      final state2 = AppState.internal(
        persistence: PersistenceService(dirProvider),
        saves: LocalSaveSyncProvider(tmpDir),
      );
      final loaded = await state2.persistence!.load();
      expect(loaded.settings['theme'], 'dark');
      expect(loaded.settings['volume'], 0.8);
    });

    test('favorites persist', () async {
      final state1 = AppState.internal(persistence: persistence, saves: saves);
      state1.games = [
        GameEntry(
          id: 'g1',
          title: 'Test',
          system: 'gb',
          filePath: '/foo/bar.gb',
          extension: 'gb',
          favorite: true,
        ),
      ];
      await state1.persist();

      final state2 = AppState.internal(
        persistence: PersistenceService(dirProvider),
        saves: LocalSaveSyncProvider(tmpDir),
      );
      final loaded = await state2.persistence!.load();
      expect(loaded.games.first.favorite, isTrue);
    });

    test('core choice persists', () async {
      final state1 = AppState.internal(persistence: persistence, saves: saves);
      state1.games = [
        GameEntry(
          id: 'g1',
          title: 'Test',
          system: 'gb',
          filePath: '/foo/bar.gb',
          extension: 'gb',
          coreId: 'pocketbit',
        ),
      ];
      await state1.persist();

      final state2 = AppState.internal(
        persistence: PersistenceService(dirProvider),
        saves: LocalSaveSyncProvider(tmpDir),
      );
      final loaded = await state2.persistence!.load();
      expect(loaded.games.first.coreId, 'pocketbit');
    });
  });

  group('AppState ephemeral does not persist', () {
    test('ephemeral state has null persistence', () {
      final state = AppState.ephemeral();
      expect(state.persistence, isNull);
    });
  });
}

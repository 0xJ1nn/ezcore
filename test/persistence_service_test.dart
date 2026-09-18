import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/cheat.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:ezcore/services/persistence_service.dart';

void main() {
  late Directory tmpDir;
  late PersistenceService service;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('ezcore_persist');
    final dirProvider = FakeLocalDataDirProvider(tmpDir);
    service = PersistenceService(dirProvider, filename: 'state.json');
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  group('PersistenceService load', () {
    test('returns empty state when no file exists', () async {
      final state = await service.load();
      expect(state.games, isEmpty);
      expect(state.cheatsByGame, isEmpty);
      expect(state.settings, isEmpty);
    });

    test('returns empty state when file is corrupt', () async {
      final file = File('${tmpDir.path}/state.json');
      await file.writeAsString('not valid json {{{');
      final state = await service.load();
      expect(state.games, isEmpty);
      expect(state.cheatsByGame, isEmpty);
      expect(state.settings, isEmpty);
    });
  });

  group('PersistenceService save/load round-trip', () {
    test('persists and reloads games', () async {
      const games = [
        GameEntry(
          id: 'g1',
          title: 'Test',
          system: 'gb',
          filePath: '/foo/bar.gb',
          extension: 'gb',
          favorite: true,
          coreId: 'sameboy',
        ),
      ];
      await service.saveGames(games);
      final state = await service.load();
      expect(state.games, games);
    });

    test('persists and reloads cheats', () async {
      final cheats = {
        'g1': const [
          CheatEntry(index: 0, desc: 'Infinite lives', code: 'ABC', enabled: true),
        ],
      };
      await service.saveCheats(cheats);
      final state = await service.load();
      expect(state.cheatsByGame['g1'], cheats['g1']);
    });

    test('persists and reloads settings', () async {
      await service.saveSettings({'theme': 'dark', 'volume': 0.8});
      final state = await service.load();
      expect(state.settings['theme'], 'dark');
      expect(state.settings['volume'], 0.8);
    });

    test('saveAll replaces entire state', () async {
      const games = [
        GameEntry(
          id: 'g1',
          title: 'Test',
          system: 'gb',
          filePath: '/foo/bar.gb',
          extension: 'gb',
        ),
      ];
      await service.saveAll(PersistedState(
        games: games,
        cheatsByGame: {
          'g1': const [CheatEntry(index: 0, desc: 'Infinite lives', code: 'ABC')],
        },
        settings: const {'theme': 'dark'},
      ));
      final state = await service.load();
      expect(state.games, games);
      expect(state.cheatsByGame['g1'], isNotNull);
      expect(state.settings['theme'], 'dark');
    });

    test('saveGames preserves cheats and settings from prior save', () async {
      await service.saveAll(PersistedState(
        games: const [],
        cheatsByGame: {
          'g1': const [CheatEntry(index: 0, desc: 'Infinite lives', code: 'ABC')],
        },
        settings: const {'theme': 'dark'},
      ));
      const games = [
        GameEntry(
          id: 'g2',
          title: 'Other',
          system: 'gba',
          filePath: '/foo/other.gba',
          extension: 'gba',
        ),
      ];
      await service.saveGames(games);
      final state = await service.load();
      expect(state.games, games);
      expect(state.cheatsByGame['g1'], isNotNull);
      expect(state.settings['theme'], 'dark');
    });

    test('saveCheats preserves games and settings from prior save', () async {
      await service.saveAll(PersistedState(
        games: const [
          GameEntry(
            id: 'g1',
            title: 'Test',
            system: 'gb',
            filePath: '/foo/bar.gb',
            extension: 'gb',
          ),
        ],
        cheatsByGame: {},
        settings: const {'theme': 'light'},
      ));
      await service.saveCheats({
        'g1': const [CheatEntry(index: 0, desc: 'Lives', code: 'ABC')],
      });
      final state = await service.load();
      expect(state.games.length, 1);
      expect(state.cheatsByGame['g1'], isNotNull);
      expect(state.settings['theme'], 'light');
    });

    test('saveSettings preserves games and cheats from prior save', () async {
      await service.saveAll(PersistedState(
        games: const [
          GameEntry(
            id: 'g1',
            title: 'Test',
            system: 'gb',
            filePath: '/foo/bar.gb',
            extension: 'gb',
          ),
        ],
        cheatsByGame: {
          'g1': const [CheatEntry(index: 0, desc: 'Lives', code: 'ABC')],
        },
        settings: const {'theme': 'light'},
      ));
      await service.saveSettings({'theme': 'dark'});
      final state = await service.load();
      expect(state.games.length, 1);
      expect(state.cheatsByGame['g1'], isNotNull);
      expect(state.settings['theme'], 'dark');
    });

    test('deleteAll removes state file', () async {
      await service.saveGames(const [
        GameEntry(
          id: 'g1',
          title: 'Test',
          system: 'gb',
          filePath: '/foo/bar.gb',
          extension: 'gb',
        ),
      ]);
      await service.deleteAll();
      final state = await service.load();
      expect(state.games, isEmpty);
    });

  });

  group('PersistenceService file integrity', () {
    test('overlapping saves preserve call order without temp-file races', () async {
      await Future.wait([
        for (var i = 0; i < 20; i++)
          service.saveAll(PersistedState(settings: {'sequence': i})),
      ]);
      expect((await service.load()).settings['sequence'], 19);
    });

    test('overlapping partial updates preserve other fields', () async {
      await Future.wait([
        service.saveGames(const [GameEntry(id: 'g', title: 'Test',
            system: 'gb', filePath: '/test.gb', extension: 'gb')]),
        service.saveSettings({'volume': 0.5}),
      ]);
      final state = await service.load();
      expect(state.games.single.id, 'g');
      expect(state.settings['volume'], 0.5);
    });
    test('writes via atomic temp + rename', () async {
      await service.saveGames(const [
        GameEntry(
          id: 'g1',
          title: 'Test',
          system: 'gb',
          filePath: '/foo/bar.gb',
          extension: 'gb',
        ),
      ]);
      final tmpFile = File('${tmpDir.path}/state.json.tmp');
      expect(tmpFile.existsSync(), isFalse);
      final stateFile = File('${tmpDir.path}/state.json');
      expect(stateFile.existsSync(), isTrue);
    });
  });
}

class FakeLocalDataDirProvider implements LocalDataDirProvider {
  FakeLocalDataDirProvider(this.dir);
  final Directory dir;

  @override
  Future<Directory> localDataDir() async => dir;

  @override
  String localDataDirPath() => dir.path;
}

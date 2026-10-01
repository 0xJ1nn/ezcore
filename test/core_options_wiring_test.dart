// Core options must reach the core from the very first frame.
//
// Many cores read their options only inside retro_load_game (the renderer
// choice is the usual example), so a value applied after the game loads is
// too late. EmulationService.start therefore applies the resolved options
// between init and load_game. This drives the real runtime and the
// synth_variables core, which echoes the value it read through
// GET_VARIABLE into the audio stream — the core's own view, not the
// runtime's stored copy. Skips cleanly when the native pieces are not built.
import 'dart:io';
import 'dart:typed_data';

import 'package:ezcore/emu/emulation_service.dart';
import 'package:ezcore/runtime/ezcore_runtime.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:ezcore/services/persistence_service.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/save_sync.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_paths.dart' as paths;

/// Sample values emitted by runtime/test/synth_core/synth_variables_core.c.
const _seenA = 0x2001;
const _seenB = 0x2002;

class _Dir implements LocalDataDirProvider {
  _Dir(this.dir);
  final Directory dir;
  @override
  Future<Directory> localDataDir() async => dir;
  @override
  String localDataDirPath() => dir.path;
}

int _firstSample(EmulationService service) {
  service.runFrame();
  final out = BytesBuilder();
  service.drainAudio(service.audioPending, out);
  final bytes = out.takeBytes();
  return ByteData.sublistView(bytes).getInt16(0, Endian.little);
}

void main() {
  final bridge = paths.bridgeLib();
  final dir = paths.runtimeBuildDir();
  final synth = dir == null
      ? null
      : '$dir/libsynth_variables_libretro.${paths.hostLibExt}';
  final built = bridge != null && synth != null && File(synth).existsSync();
  final skip = built ? null : 'needs built runtime + synth_variables core';

  Future<EmulationService> start(Map<String, String> options) async {
    final service = EmulationService(
      runtime: EzCoreRuntime.load(runtimePath: bridge!),
    );
    await service.start(
      corePath: synth!,
      romPath: '/dev/null',
      rom: Uint8List(0),
      coreOptions: options,
    );
    return service;
  }

  group('EmulationService applies core options before the game loads', () {
    test('no options: the core runs on its default', skip: skip, () async {
      final service = await start(const {});
      try {
        expect(_firstSample(service), _seenA);
        expect(service.rejectedCoreOptions, isEmpty);
      } finally {
        service.close();
      }
    });

    test(
      'a resolved option is what the core reads on frame one',
      skip: skip,
      () async {
        final service = await start(const {'synth_mode': 'b'});
        try {
          expect(_firstSample(service), _seenB);
        } finally {
          service.close();
        }
      },
    );

    test(
      'an option the core does not declare is reported, not fatal',
      skip: skip,
      () async {
        final service = await start(const {
          'synth_mode': 'b',
          'stale_key_from_older_core': 'x',
        });
        try {
          expect(service.rejectedCoreOptions, ['stale_key_from_older_core']);
          expect(_firstSample(service), _seenB);
        } finally {
          service.close();
        }
      },
    );
  });

  group('AppState core option overrides', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('ezcore_coreopts');
    });
    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    AppState mk() => AppState.internal(
      persistence: PersistenceService(_Dir(tmp)),
      saves: LocalSaveSyncProvider(tmp),
    );

    test('nothing set resolves to nothing (the core keeps its defaults)', () {
      expect(mk().coreOptionsFor(coreId: 'c', gameId: 'g'), isEmpty);
    });

    test('a per-game value beats the per-core value', () async {
      final s = mk();
      await s.setCoreOptionOverride('c', 'renderer', 'software');
      await s.setCoreOptionOverride('c', 'region', 'auto');
      await s.setGameCoreOptionOverride('g', 'renderer', 'hardware');
      expect(s.coreOptionsFor(coreId: 'c', gameId: 'g'), {
        'renderer': 'hardware',
        'region': 'auto',
      });
      // Another game of the same core only sees the core layer.
      expect(s.coreOptionsFor(coreId: 'c', gameId: 'other'), {
        'renderer': 'software',
        'region': 'auto',
      });
      // Another core sees none of it.
      expect(s.coreOptionsFor(coreId: 'd', gameId: 'g2'), isEmpty);
    });

    test('clearing an override falls back to the layer below', () async {
      final s = mk();
      await s.setCoreOptionOverride('c', 'renderer', 'software');
      await s.setGameCoreOptionOverride('g', 'renderer', 'hardware');
      await s.setGameCoreOptionOverride('g', 'renderer', null);
      expect(s.coreOptionsFor(coreId: 'c', gameId: 'g'), {
        'renderer': 'software',
      });
    });

    test('overrides are persisted', () async {
      final a = mk();
      await a.setCoreOptionOverride('c', 'renderer', 'software');
      await a.setGameCoreOptionOverride('g', 'region', 'pal');
      final persisted = await PersistenceService(_Dir(tmp)).load();
      expect(persisted.settings[AppState.coreOptionsKey], {
        'c': {'renderer': 'software'},
      });
      expect(persisted.settings[AppState.gameCoreOptionsKey], {
        'g': {'region': 'pal'},
      });
    });

    test('a corrupt persisted value is ignored, not a crash', () async {
      final s = mk();
      await s.setSetting(AppState.coreOptionsKey, 'not a map');
      await s.setSetting(AppState.gameCoreOptionsKey, {'g': 42});
      expect(s.coreOptionsFor(coreId: 'c', gameId: 'g'), isEmpty);
    });
  });
}

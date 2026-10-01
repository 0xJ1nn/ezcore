// A core's manifest may declare recommended starting values for its own
// options (`default_options`). They are data — validated strings, never
// code — and they sit at the bottom of the precedence order: the user's
// per-core choice beats them, and a per-game choice beats both. This is how
// a core that needs a non-default setting to run on ezCORE today (the N64
// core's software renderer, until the GPU path lands) gets it without the
// UI ever naming a core (PLATFORM.md §6.5).
import 'dart:convert';
import 'dart:io';

import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/services/core_package_validator.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:ezcore/services/persistence_service.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/save_sync.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> manifest({Object? defaults}) => {
  'id': 'demo',
  'name': 'Demo',
  'version': '1.0',
  'license': 'MIT',
  'systems': ['n64'],
  'extensions': ['z64'],
  'delivery': {'linux': 'bundled'},
  'artifacts': <String, String>{},
  'default_options': ?defaults,
};

class _Dir implements LocalDataDirProvider {
  _Dir(this.dir);
  final Directory dir;
  @override
  Future<Directory> localDataDir() async => dir;
  @override
  String localDataDirPath() => dir.path;
}

void main() {
  group('CoreManifest.default_options', () {
    test('absent means no defaults', () {
      final m = CoreManifest.fromJson(manifest());
      expect(m.defaultOptions, isEmpty);
      expect(m.validate(), isEmpty);
    });

    test('a string map is parsed and valid', () {
      final m = CoreManifest.fromJson(
        manifest(defaults: {'renderer': 'software', 'rsp': 'lle'}),
      );
      expect(m.defaultOptions, {'renderer': 'software', 'rsp': 'lle'});
      expect(m.validate(), isEmpty);
      expect(m.toJson()['default_options'], m.defaultOptions);
    });

    test('non-string values are rejected, not stringified', () {
      final m = CoreManifest.fromJson(
        manifest(defaults: {'renderer': 1, 'ok': 'yes'}),
      );
      expect(m.validate(), contains(contains('default_options')));
      expect(m.defaultOptions.containsKey('renderer'), isFalse);
    });

    test('a non-object is rejected', () {
      final m = CoreManifest.fromJson(manifest(defaults: ['renderer']));
      expect(m.validate(), contains(contains('default_options')));
    });

    test('oversized maps and strings are rejected', () {
      final many = {for (var i = 0; i < 129; i++) 'k$i': 'v'};
      expect(
        CoreManifest.fromJson(manifest(defaults: many)).validate(),
        contains(contains('default_options')),
      );
      final long = {'k': 'v' * 257};
      expect(
        CoreManifest.fromJson(manifest(defaults: long)).validate(),
        contains(contains('default_options')),
      );
    });
  });

  group('package validator', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('ezcore_defopts');
    });
    tearDown(() async => tmp.delete(recursive: true));

    Future<PackageValidationReport> validate(Map<String, dynamic> m) async {
      final dir = await Directory('${tmp.path}/demo').create();
      await File('${dir.path}/manifest.json').writeAsString(jsonEncode(m));
      return PackageValidationReport.validate(dir);
    }

    test('accepts a well-formed default_options', () async {
      final r = await validate(manifest(defaults: {'renderer': 'software'}));
      expect(r.errors, isEmpty);
    });

    test('rejects a malformed default_options', () async {
      final r = await validate(manifest(defaults: {'renderer': true}));
      expect(r.errors, contains(contains('default_options')));
    });
  });

  group('AppState resolution with manifest defaults', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('ezcore_defopts_state');
    });
    tearDown(() async => tmp.delete(recursive: true));

    AppState mk() {
      final s = AppState.internal(
        persistence: PersistenceService(_Dir(tmp)),
        saves: LocalSaveSyncProvider(tmp),
      );
      s.registry.loadCatalog({
        'demo': jsonEncode(
          manifest(defaults: {'renderer': 'software', 'rsp': 'lle'}),
        ),
      });
      return s;
    }

    test('manifest defaults apply when the user set nothing', () {
      expect(mk().coreOptionsFor(coreId: 'demo', gameId: 'g'), {
        'renderer': 'software',
        'rsp': 'lle',
      });
    });

    test('the user per-core and per-game choices beat the manifest', () async {
      final s = mk();
      await s.setCoreOptionOverride('demo', 'renderer', 'hardware');
      await s.setGameCoreOptionOverride('g', 'rsp', 'hle');
      expect(s.coreOptionsFor(coreId: 'demo', gameId: 'g'), {
        'renderer': 'hardware',
        'rsp': 'hle',
      });
    });

    test('an unknown core id resolves to only the user layers', () {
      expect(mk().coreOptionsFor(coreId: 'nope', gameId: 'g'), isEmpty);
    });
  });
}

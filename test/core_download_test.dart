import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/cores/core_registry.dart';
import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/services/core_downloader.dart';
import 'package:ezcore/services/core_staging.dart';
import 'package:ezcore/services/hash_verifier.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:ezcore/services/native_dirs.dart';

/// On-demand core downloads (ADR-013): release metadata → URL → streamed
/// fetch → sha256-verified against the manifest pin → vault + registry.
/// Failure-first: none of this existed when this file was first run.

class FakeLocalDataDirProvider implements LocalDataDirProvider {
  FakeLocalDataDirProvider(this.dir);
  final Directory dir;

  @override
  Future<Directory> localDataDir() async => dir;

  @override
  String localDataDirPath() => dir.path;
}

class FakeFetcher implements CoreAssetFetcher {
  FakeFetcher({this.chunks, this.error});
  final List<List<int>>? chunks;
  final Object? error;
  final List<Uri> seen = [];

  @override
  Stream<List<int>> open(Uri url) {
    seen.add(url);
    if (error != null) return Stream<List<int>>.error(error!);
    return Stream.fromIterable(chunks!);
  }
}

CoreManifest _giant(String pin, {Map<String, String>? delivery}) {
  return CoreManifest(
    id: 'giant',
    name: 'Giant Core',
    version: '1.2.3',
    license: 'GPL-3.0-or-later',
    systems: ['testsystem'],
    extensions: ['gt'],
    cheatFamilies: const [],
    cheatsSupported: false,
    delivery: delivery ??
        const {
          'macos': 'download',
          'windows': 'download',
          'linux': 'download',
          'android': 'absent',
          'ios': 'absent',
        },
    artifacts: {'linux-x64': pin},
  );
}

const _releaseJson = <String, dynamic>{
  'repo': 'JinUltimate1995/ezcore',
  'tag': 'v9.9.9',
  'assets': {
    'linux-x64': {'giant': 'giant_libretro-linux-x64.so'},
  },
};

void main() {
  late Directory tmpDir;
  late FakeLocalDataDirProvider dirs;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('ezcore_download');
    dirs = FakeLocalDataDirProvider(tmpDir);
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  /// SHA-256 of [bytes], computed the way production does (pure Dart).
  Future<String> pinOf(List<int> bytes) async {
    final f = File('${tmpDir.path}/pin-source');
    await f.writeAsBytes(bytes);
    return const DartHashVerifier().sha256File(f.path);
  }

  group('CoreRelease / URL construction', () {
    test('builds the pinned GitHub release asset URL', () {
      final r = CoreRelease.fromJson(_releaseJson);
      expect(
        r.downloadUri('linux-x64', 'giant').toString(),
        'https://github.com/JinUltimate1995/ezcore/releases/download/'
        'v9.9.9/giant_libretro-linux-x64.so',
      );
    });

    test('refuses cores with no published asset for this platform', () {
      final r = CoreRelease.fromJson(_releaseJson);
      expect(
        () => r.downloadUri('windows-x64', 'giant'),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('not published'),
        )),
      );
    });

    test('tolerates a missing release map (older catalogs)', () {
      final r = CoreRelease.fromJson(const {});
      expect(r.repo, isEmpty);
      expect(r.tag, isEmpty);
      expect(r.assets, isEmpty);
    });
  });

  group('CoreDownloader', () {
    test('streams, verifies the pin, stages to the vault, installs', () async {
      final bytes = utf8.encode('legit giant core bytes');
      final pin = await pinOf(bytes);
      final fetcher = FakeFetcher(chunks: [bytes.sublist(0, 7), bytes.sublist(7)]);
      final registry = CoreRegistry();
      final m = _giant(pin);
      registry.loadCatalog({'giant': json.encode(m.toJson())});

      final dl = CoreDownloader(
        dirs: dirs,
        fetcher: fetcher,
        hashes: const DartHashVerifier(),
        isIOS: () => false,
      );
      final got = await dl.download(
        manifest: m,
        release: CoreRelease.fromJson(_releaseJson),
        platformKey: 'linux-x64',
        registry: registry,
      );

      expect(got, pin);
      expect(fetcher.seen.single.host, 'github.com');
      expect(fetcher.seen.single.path,
          '/JinUltimate1995/ezcore/releases/download/v9.9.9/'
          'giant_libretro-linux-x64.so');

      final dest = File('${tmpDir.path}/cores/giant/giant.so');
      expect(dest.existsSync(), isTrue, reason: 'vault copy must exist');
      expect(utf8.decode(dest.readAsBytesSync()), 'legit giant core bytes');
      expect(File('${dest.path}.ezpin').existsSync(), isTrue,
          reason: 'verification sidecar must exist for the staging fast path');
      expect(File('${dest.path}.part').existsSync(), isFalse);
      expect(registry.isInstalled('giant'), isTrue);
    });

    test('hash mismatch: discards the download and refuses install',
        () async {
      final good = utf8.encode('pinned bytes');
      final pin = await pinOf(good);
      final evil = utf8.encode('tampered bytes');
      final registry = CoreRegistry();
      final m = _giant(pin);
      registry.loadCatalog({'giant': json.encode(m.toJson())});

      final dl = CoreDownloader(
        dirs: dirs,
        fetcher: FakeFetcher(chunks: [evil]),
        hashes: const DartHashVerifier(),
        isIOS: () => false,
      );

      await expectLater(
        dl.download(
          manifest: m,
          release: CoreRelease.fromJson(_releaseJson),
          platformKey: 'linux-x64',
          registry: registry,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('SHA-256'),
        )),
      );
      expect(File('${tmpDir.path}/cores/giant/giant.so').existsSync(), isFalse);
      expect(File('${tmpDir.path}/cores/giant/giant.so.part').existsSync(),
          isFalse);
      expect(registry.isInstalled('giant'), isFalse);
    });

    test('transport failure: typed error, no partial files left', () async {
      final good = utf8.encode('pinned bytes');
      final pin = await pinOf(good);
      final registry = CoreRegistry();
      final m = _giant(pin);
      registry.loadCatalog({'giant': json.encode(m.toJson())});

      final dl = CoreDownloader(
        dirs: dirs,
        fetcher: FakeFetcher(error: StateError('HTTP 404 Not Found')),
        hashes: const DartHashVerifier(),
        isIOS: () => false,
      );

      await expectLater(
        dl.download(
          manifest: m,
          release: CoreRelease.fromJson(_releaseJson),
          platformKey: 'linux-x64',
          registry: registry,
        ),
        throwsA(isA<StateError>()),
      );
      final dir = Directory('${tmpDir.path}/cores/giant');
      if (dir.existsSync()) {
        expect(dir.listSync(), isEmpty,
            reason: 'no .part/.so/sidecar may survive a failed fetch');
      }
      expect(registry.isInstalled('giant'), isFalse);
    });

    test('refuses cores whose delivery is not download here', () async {
      final bytes = utf8.encode('x');
      final pin = await pinOf(bytes);
      final m = _giant(
        pin,
        delivery: const {
          'macos': 'bundled',
          'windows': 'bundled',
          'linux': 'bundled',
          'android': 'absent',
          'ios': 'absent',
        },
      );
      final dl = CoreDownloader(
        dirs: dirs,
        fetcher: FakeFetcher(chunks: [bytes]),
        hashes: const DartHashVerifier(),
        isIOS: () => false,
      );
      await expectLater(
        dl.download(
          manifest: m,
          release: CoreRelease.fromJson(_releaseJson),
          platformKey: 'linux-x64',
          registry: CoreRegistry(),
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('not a downloadable core'),
        )),
      );
    });

    test('iOS never downloads (App Review 2.5.2/4.7)', () async {
      final pin = await pinOf(utf8.encode('x'));
      final dl = CoreDownloader(
        dirs: dirs,
        fetcher: FakeFetcher(chunks: [utf8.encode('x')]),
        hashes: const DartHashVerifier(),
        isIOS: () => true,
      );
      await expectLater(
        dl.download(
          manifest: _giant(pin),
          release: CoreRelease.fromJson(_releaseJson),
          platformKey: 'linux-x64',
          registry: CoreRegistry(),
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('iOS never downloads'),
        )),
      );
    });
  });

  group('staging keeps downloaded cores alive', () {
    test('a verified vault copy with no local source survives ensureStaged',
        () async {
      final bytes = utf8.encode('downloaded earlier');
      final pin = await pinOf(bytes);
      // Seed the vault exactly as CoreDownloader leaves it.
      final coreDir = Directory('${tmpDir.path}/cores/giant')
        ..createSync(recursive: true);
      final dest = File('${coreDir.path}/giant.so')
        ..writeAsBytesSync(bytes);
      final stat = dest.statSync();
      File('${dest.path}.ezpin').writeAsStringSync(json.encode({
        'pin': pin,
        'size': stat.size,
        'mtimeMs': stat.modified.millisecondsSinceEpoch,
      }));

      final staging = CoreStagingService(
        dirs: dirs,
        hashes: const DartHashVerifier(),
        native: const FallbackNativeDirs(),
      );
      final staged = await staging.ensureStaged(catalog: [_giant(pin)]);

      expect(staged, contains('giant'),
          reason: 'a downloaded core has no bundled source but must count');
      expect(dest.existsSync(), isTrue,
          reason: 'ensureStaged must never delete a verified download');
      expect(staging.errors, isEmpty);
    });
  });

  group('committed release map (cores/release.json + catalog)', () {
    final release =
        json.decode(File('cores/release.json').readAsStringSync())
            as Map<String, dynamic>;
    final catalog =
        json.decode(File('cores/catalog.json').readAsStringSync())
            as Map<String, dynamic>;

    Map<String, dynamic> manifestOf(String id) =>
        json.decode(File('cores/$id/manifest.json').readAsStringSync())
            as Map<String, dynamic>;

    test('release tag matches the pubspec version', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final v = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(pubspec)!
          .group(1)!
          .split('+')
          .first;
      expect(release['tag'], 'v$v');
      expect(release['repo'], 'JinUltimate1995/ezcore');
    });

    test('every published asset is download-delivery, pinned, conventionally named', () {
      final assets = release['assets'] as Map<String, dynamic>;
      expect(assets, isNotEmpty, reason: 'hybrid set must publish something');
      for (final entry in assets.entries) {
        final plat = entry.key;
        final os = plat.split('-').first;
        final ext = os == 'windows'
            ? 'dll'
            : (os == 'macos' || os == 'ios') ? 'dylib' : 'so';
        for (final asset in (entry.value as Map<String, dynamic>).entries) {
          final id = asset.key;
          final m = manifestOf(id);
          expect((m['delivery'] as Map)[os], 'download',
              reason: '$id:$plat publishes an asset but is not download');
          expect((m['artifacts'] as Map)[plat], isA<String>(),
              reason: '$id:$plat publishes an asset without a pin');
          expect(asset.value, '${id}_libretro-$plat.$ext',
              reason: '$id:$plat asset name diverges from the upload convention');
        }
      }
    });

    test('hybrid split: giants download on desktop, portcomp stays bundled', () {
      for (final id in ['pointclick', 'dreamarc', 'powercube']) {
        final d = (manifestOf(id)['delivery'] as Map).cast<String, String>();
        expect(d['linux'], 'download', reason: id);
        expect(d['macos'], 'download', reason: id);
        expect(d['windows'], 'download', reason: id);
      }
      // Hybrid threshold: the ~20 MB PSP core ships built-in.
      final portcomp =
          (manifestOf('portcomp')['delivery'] as Map).cast<String, String>();
      expect(portcomp['linux'], 'bundled');
      expect(portcomp['macos'], 'bundled');
      // Mobile keeps its tier: pointclick bundled on android + ios,
      // the console giants absent everywhere mobile.
      final pc = (manifestOf('pointclick')['delivery'] as Map).cast<String, String>();
      expect(pc['android'], 'bundled');
      expect(pc['ios'], 'bundled');
      for (final id in ['dreamarc', 'powercube']) {
        final d = (manifestOf(id)['delivery'] as Map).cast<String, String>();
        expect(d['android'], 'absent', reason: id);
        expect(d['ios'], 'absent', reason: id);
      }
    });

    test('no core anywhere declares ios delivery download', () {
      for (final entry in catalog.entries) {
        final m = entry.value as Map<String, dynamic>;
        expect((m['delivery'] as Map?)?['ios'], isNot('download'),
            reason: entry.key);
      }
    });

    test('linux-x64 download set is exactly the giants', () {
      final assets = (release['assets'] as Map<String, dynamic>)['linux-x64']
          as Map<String, dynamic>?;
      expect(assets?.keys.toSet(), {'pointclick', 'dreamarc', 'powercube'});
    });
  });
}

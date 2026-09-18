import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/services/core_path_resolver.dart';
import 'package:ezcore/services/hash_verifier.dart';
import 'package:ezcore/services/local_data_dir.dart';

class FakeHashVerifier implements HashVerifier {
  FakeHashVerifier(this._hashes);
  final Map<String, String> _hashes;

  @override
  Future<String> sha256File(String path) async {
    if (!_hashes.containsKey(path)) {
      throw StateError('No canned hash for $path');
    }
    return _hashes[path]!;
  }
}

CoreManifest _mgba() => const CoreManifest(
      id: 'mgba',
      name: 'mGBA',
      version: '0.11-dev',
      license: 'MPL-2.0',
      systems: ['gba'],
      extensions: ['gba'],
      cheatFamilies: ['gba_actionreplay'],
      cheatsSupported: true,
      delivery: {'ios': 'bundled', 'macos': 'download'},
      artifacts: {'macos-arm64': 'sha-mgba'},
    );

CoreManifest _blocked() => const CoreManifest(
      id: 'switch_hold',
      name: 'Nintendo Switch — legal hold',
      version: '0.0.0-blocked',
      license: 'GPL-3.0',
      systems: ['switch'],
      extensions: [],
      cheatFamilies: [],
      cheatsSupported: false,
      delivery: {},
      artifacts: {},
      blockedReason: 'Yuzu settlement',
    );

void main() {
  late Directory tmpDir;
  late CorePathResolver resolver;
  late FakeHashVerifier hashVerifier;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('ezcore_corepath');
    final dirProvider = FakeLocalDataDirProvider(tmpDir);
    hashVerifier = FakeHashVerifier({});
    resolver = CorePathResolver(dirProvider, hashVerifier);
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  test('currentPlatformKey returns os-arch string', () {
    final key = CorePathResolver.currentPlatformKey();
    expect(key, matches(RegExp(r'^(macos|linux|windows|android|ios)-(arm64|x64|unknown)$')));
  });

  test('resolve returns null when artifact missing from manifest', () async {
    final manifest = const CoreManifest(
      id: 'scummvm',
      name: 'ScummVM',
      version: '2.8.0',
      license: 'GPL-3.0',
      systems: ['scumm'],
      extensions: ['scummvm'],
      cheatFamilies: [],
      cheatsSupported: false,
      delivery: {},
      artifacts: {}, // no macos-arm64 artifact
    );
    final resolved = await resolver.resolve(manifest);
    expect(resolved, isNull);
  });

  test('resolve returns null when file does not exist', () async {
    final resolved = await resolver.resolve(_mgba());
    expect(resolved, isNull);
  });

  test('resolve returns CorePath when file exists at expected location', () async {
    final key = CorePathResolver.currentPlatformKey();
    if (!key.startsWith('macos')) {
      // This test only applies to macOS hosts; skip elsewhere.
      markTestSkipped('Core artifact path test is host-specific');
      return;
    }
    final artifactDir = Directory('${tmpDir.path}/cores/mgba');
    await artifactDir.create(recursive: true);
    final artifactFile = File('${artifactDir.path}/mgba.dylib');
    await artifactFile.writeAsString('fake artifact');

    final resolved = await resolver.resolve(_mgba());
    expect(resolved, isNotNull);
    expect(resolved!.path, artifactFile.path);
    expect(resolved.sha256, 'sha-mgba');
    expect(resolved.platformKey, key);
  });

  group('verifyPin', () {
    test('throws StateError when artifact missing', () async {
      expect(
        () => resolver.verifyPin(_mgba()),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('No artifact resolved'),
        )),
      );
    });

    test('throws StateError when core is blocked (legal hold)', () async {
      // Even though artifacts is empty, verifyPin should reject blocked cores
      expect(
        () => resolver.verifyPin(_blocked()),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('legal hold'),
        )),
      );
    });

    test('throws StateError when SHA-256 pin mismatches', () async {
      final key = CorePathResolver.currentPlatformKey();
      if (!key.startsWith('macos')) {
        markTestSkipped('Core artifact path test is host-specific');
        return;
      }
      final artifactDir = Directory('${tmpDir.path}/cores/mgba');
      await artifactDir.create(recursive: true);
      final artifactFile = File('${artifactDir.path}/mgba.dylib');
      await artifactFile.writeAsString('fake artifact');

      // Wrong hash
      hashVerifier._hashes[artifactFile.path] = 'wronghash';

      expect(
        () => resolver.verifyPin(_mgba()),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('SHA-256 mismatch'),
        )),
      );
    });

    test('returns canonical hash when pin matches', () async {
      final key = CorePathResolver.currentPlatformKey();
      if (!key.startsWith('macos')) {
        markTestSkipped('Core artifact path test is host-specific');
        return;
      }
      final artifactDir = Directory('${tmpDir.path}/cores/mgba');
      await artifactDir.create(recursive: true);
      final artifactFile = File('${artifactDir.path}/mgba.dylib');
      await artifactFile.writeAsString('fake artifact');

      hashVerifier._hashes[artifactFile.path] = 'sha-mgba';

      final hash = await resolver.verifyPin(_mgba());
      expect(hash, 'sha-mgba');
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

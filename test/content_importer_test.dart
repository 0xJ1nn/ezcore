import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/services/content_importer.dart';
import 'package:ezcore/services/hash_verifier.dart';

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
      delivery: {'ios': 'bundled'},
      artifacts: {'macos-arm64': 'sha-mgba'},
    );

CoreManifest _blockedSwitch() => const CoreManifest(
      id: 'switch_hold',
      name: 'Nintendo Switch — legal hold',
      version: '0.0.0-blocked',
      license: 'GPL-3.0',
      systems: ['switch'],
      extensions: ['nsp'],
      cheatFamilies: [],
      cheatsSupported: false,
      delivery: {},
      artifacts: {},
      blockedReason: 'Yuzu settlement',
    );

Map<String, CoreManifest> _catalog() => {
      'mgba': _mgba(),
      'switch_hold': _blockedSwitch(),
    };

void main() {
  late Directory tmpDir;
  late ContentImporter importer;
  late FakeHashVerifier hashVerifier;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('ezcore_import');
    hashVerifier = FakeHashVerifier({});
    importer = ContentImporter(hashVerifier);
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  group('importFile', () {
    test('returns error when file does not exist', () async {
      final result = await importer.importFile(
        '${tmpDir.path}/missing.gba',
        knownShas: {},
        catalog: _catalog(),
      );
      expect(result.isError, isTrue);
      expect(result.error, contains('does not exist'));
    });

    test('rejects files with extensions mapped to blocked cores', () async {
      final file = File('${tmpDir.path}/switch_game.nsp');
      await file.writeAsString('fake nsp');
      final result = await importer.importFile(
        file.path,
        knownShas: {},
        catalog: _catalog(),
      );
      expect(result.isSkipped, isTrue);
      expect(result.skippedReason, contains('legal hold'));
    });

    test('skips files with no matching core', () async {
      final file = File('${tmpDir.path}/game.xyz');
      await file.writeAsString('fake xyz');
      final result = await importer.importFile(
        file.path,
        knownShas: {},
        catalog: _catalog(),
      );
      expect(result.isSkipped, isTrue);
      expect(result.skippedReason, contains('No core for extension'));
    });

    test('skips duplicate files by hash', () async {
      final file = File('${tmpDir.path}/game.gba');
      await file.writeAsString('fake gba');
      const hash = 'abc123';
      hashVerifier._hashes[file.path] = hash;
      final result = await importer.importFile(
        file.path,
        knownShas: {hash},
        catalog: _catalog(),
      );
      expect(result.isSkipped, isTrue);
      expect(result.skippedReason, contains('Duplicate'));
    });

    test('imports valid game file', () async {
      final file = File('${tmpDir.path}/mygame.gba');
      await file.writeAsString('fake gba content');
      const hash = 'deadbeef';
      hashVerifier._hashes[file.path] = hash;
      final result = await importer.importFile(
        file.path,
        knownShas: {},
        catalog: _catalog(),
      );
      expect(result.isSuccess, isTrue);
      expect(result.game, isNotNull);
      expect(result.game!.id, 'imp-$hash');
      expect(result.game!.title, 'mygame.gba');
      expect(result.game!.system, 'gba');
      expect(result.game!.extension, 'gba');
      expect(result.game!.filePath, file.path);
      expect(result.game!.coreId, 'mgba');
    });

    test('validates file existence and manifest match before import', () async {
      final file = File('${tmpDir.path}/valid.gba');
      await file.writeAsString('valid gba');
      const hash = 'cafebabe';
      hashVerifier._hashes[file.path] = hash;
      final result = await importer.importFile(
        file.path,
        knownShas: {},
        catalog: _catalog(),
      );
      expect(result.game!.filePath, file.path);
      expect(result.game!.sha1, hash);
    });

    test('matches extension case-insensitively', () async {
      final file = File('${tmpDir.path}/UPPER.GBA');
      await file.writeAsString('upper case ext');
      const hash = 'abcabc';
      hashVerifier._hashes[file.path] = hash;
      final result = await importer.importFile(
        file.path,
        knownShas: {},
        catalog: _catalog(),
      );
      expect(result.isSuccess, isTrue);
      expect(result.game!.extension, 'gba');
    });
  });

  group('scanDirectory', () {
    test('returns error when directory does not exist', () async {
      final result = await importer.scanDirectory(
        '${tmpDir.path}/nonexistent',
        knownShas: {},
        catalog: _catalog(),
      );
      expect(result.hasError, isTrue);
      expect(result.manifestError, contains('does not exist'));
    });

    test('scans directory and categorizes files', () async {
      final gbaFile = File('${tmpDir.path}/game.gba');
      await gbaFile.writeAsString('gba');
      hashVerifier._hashes[gbaFile.path] = 'hash1';
      final blockedFile = File('${tmpDir.path}/game.nsp');
      await blockedFile.writeAsString('nsp');
      final noCoreFile = File('${tmpDir.path}/readme.txt');
      await noCoreFile.writeAsString('readme');

      final result = await importer.scanDirectory(
        tmpDir.path,
        knownShas: {},
        catalog: _catalog(),
      );
      expect(result.hasError, isFalse);
      expect(result.importedCount, 1);
      expect(result.skippedCount, 2);
      expect(result.errorCount, 0);
    });
  });
}

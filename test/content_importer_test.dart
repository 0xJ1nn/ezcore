import 'dart:io';
import 'dart:typed_data';

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

/// Creates a fake ROM file with valid magic bytes and size.
///
/// [extension] determines which magic bytes to write. [size] is the total
/// file size (must be >= 512 to pass validation). Magic bytes are written
/// at the offset where the real format carries them (GB logo at 0x104,
/// GBA logo at 0x04, Genesis "SEGA" at 0x100) — mirroring the validator.
/// The file is filled with 0xFF padding elsewhere.
Future<File> createFakeRom(Directory dir, String name, String extension, {int size = 4096}) async {
  final file = File('${dir.path}/$name.$extension');
  final bytes = Uint8List(size);

  // Write magic bytes based on extension
  final magic = _magicForExtension(extension);
  final offset = _offsetForExtension(extension);
  if (magic != null) {
    for (var i = 0; i < magic.length && offset + i < size; i++) {
      bytes[offset + i] = magic[i];
    }
  }

  // Fill rest with 0xFF (non-text, non-zero)
  final start = magic == null ? 0 : offset + magic.length;
  for (var i = start; i < size; i++) {
    if (bytes[i] == 0) bytes[i] = 0xFF;
  }

  await file.writeAsBytes(bytes);
  return file;
}

/// Offset where the format's magic lives inside the cart (0 = file header).
int _offsetForExtension(String ext) {
  switch (ext.toLowerCase()) {
    case 'gb':
    case 'gbc':
      return 0x104;
    case 'gba':
      return 0x04;
    case 'md':
    case 'gen':
    case 'sms':
    case 'gg':
    case 'sg':
      return 0x100;
    default:
      return 0;
  }
}

/// Returns the magic bytes for a given extension, or null if none defined.
List<int>? _magicForExtension(String ext) {
  switch (ext.toLowerCase()) {
    case 'gba':
      return [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21];
    case 'gb':
    case 'gbc':
      return [0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B];
    case 'nes':
      return [0x4E, 0x45, 0x53, 0x1A];
    case 'sfc':
    case 'smc':
      return [0x78, 0x56, 0x34, 0x12];
    case 'n64':
    case 'z64':
    case 'v64':
      return [0x80, 0x37, 0x12, 0x40];
    case 'md':
    case 'gen':
    case 'sms':
    case 'gg':
    case 'sg':
      return [0x53, 0x45, 0x47, 0x41];
    case 'nds':
      return [0x4E, 0x44, 0x53, 0x00];
    case 'a26':
      return [0x41, 0x54, 0x41, 0x52, 0x49, 0x00];
    case 'pce':
    case 'sgx':
      return [0x50, 0x43, 0x45, 0x00];
    case 'fds':
      return [0x46, 0x44, 0x53, 0x1A];
    case 'unf':
      return [0x55, 0x4E, 0x46, 0x00];
    case 'zip':
      return [0x50, 0x4B, 0x03, 0x04];
    case 'iso':
      return [0x01, 0x43, 0x44, 0x30, 0x30, 0x31];
    case 'chd':
      return [0x4D, 0x43, 0x6F, 0x6D, 0x70, 0x72, 0x48, 0x44];
    case 'cso':
    case 'ciso':
      return [0x43, 0x49, 0x53, 0x4F];
    case 'pbp':
      return [0x00, 0x50, 0x42, 0x50];
    case 'elf':
      return [0x7F, 0x45, 0x4C, 0x46];
    case 'prx':
      return [0x00, 0x50, 0x52, 0x58];
    case 'dol':
      return [0x00, 0xD0, 0x0D, 0xFE];
    case 'wad':
      return [0x49, 0x57, 0x41, 0x44];
    case 'wbfs':
      return [0x57, 0x42, 0x46, 0x53];
    case 'rvz':
      return [0x52, 0x56, 0x5A, 0x01];
    case 'gcm':
      return [0x47, 0x43, 0x4D, 0x00];
    case 'cdi':
      return [0x43, 0x44, 0x49, 0x00];
    case 'gdi':
      return [0x47, 0x44, 0x49, 0x00];
    case 'exe':
      return [0x4D, 0x5A];
    case 'com':
      return [0x00, 0x00, 0x00, 0x00];
    case 'bin':
    case 'img':
    case 'fig':
      return [0x00, 0x00, 0x00, 0x00];
    default:
      return null; // No magic — binary check only
  }
}

CoreManifest _mgba() => const CoreManifest(
      id: 'advancebit',
      name: 'mGBA',
      version: '0.11-dev',
      license: 'MPL-2.0',
      systems: ['gba'],
      extensions: ['gba'],
      cheatFamilies: ['gba_actionreplay'],
      cheatsSupported: true,
      delivery: {'ios': 'bundled'},
      artifacts: {'macos-arm64': 'sha-advancebit'},
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
      'advancebit': _mgba(),
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
      final file = await createFakeRom(tmpDir, 'game', 'gba');
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
      final file = await createFakeRom(tmpDir, 'mygame', 'gba');
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
      expect(result.game!.coreId, 'advancebit');
    });

    test('validates file existence and manifest match before import', () async {
      final file = await createFakeRom(tmpDir, 'valid', 'gba');
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
      final file = await createFakeRom(tmpDir, 'UPPER', 'GBA');
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

    test('rejects text files that share a ROM extension', () async {
      final file = File('${tmpDir.path}/README.gba');
      await file.writeAsString('This is a README file, not a ROM.');
      final result = await importer.importFile(
        file.path,
        knownShas: {},
        catalog: _catalog(),
      );
      expect(result.isSkipped, isTrue);
      expect(result.skippedReason, contains('Not a valid ROM'));
    });

    test('rejects files with wrong magic bytes', () async {
      final file = File('${tmpDir.path}/fake.gba');
      await file.writeAsBytes(List.filled(4096, 0xFF));
      final result = await importer.importFile(
        file.path,
        knownShas: {},
        catalog: _catalog(),
      );
      expect(result.isSkipped, isTrue);
      expect(result.skippedReason, contains('Not a valid ROM'));
    });

    test('rejects files that are too small', () async {
      final file = File('${tmpDir.path}/tiny.gba');
      await file.writeAsBytes([0x24, 0xFF, 0xAE, 0x51]);
      final result = await importer.importFile(
        file.path,
        knownShas: {},
        catalog: _catalog(),
      );
      expect(result.isSkipped, isTrue);
      expect(result.skippedReason, contains('Not a valid ROM'));
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
      final gbaFile = await createFakeRom(tmpDir, 'game', 'gba');
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

    test('skips hidden directories during scan', () async {
      final hiddenDir = Directory('${tmpDir.path}/.hidden');
      await hiddenDir.create();
      final gbaFile = await createFakeRom(hiddenDir, 'game', 'gba');
      hashVerifier._hashes[gbaFile.path] = 'hash1';

      final result = await importer.scanDirectory(
        tmpDir.path,
        knownShas: {},
        catalog: _catalog(),
      );
      expect(result.importedCount, 0);
    });
  });
}

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
      name: 'Nintendo Switch — on hold',
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
      expect(result.skippedReason, contains('is on hold'));
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

  group('system-aware identification', () {
    late Map<String, CoreManifest> catalog;

    setUp(() {
      catalog = _multiCatalog();
    });

    Future<File> writeBytes(String name, List<int> bytes) async {
      final f = File('${tmpDir.path}/$name');
      await f.writeAsBytes(bytes);
      hashVerifier._hashes[f.path] = 'hash-${f.path.hashCode}';
      return f;
    }
    List<int> gbRom() {
      final b = List<int>.filled(4096, 0xFF);
      const logo = [0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B];
      for (var i = 0; i < logo.length; i++) {
        b[0x104 + i] = logo[i];
      }
      b[0x143] = 0x00; // not CGB-only
      return b;
    }

    List<int> mzExe({required bool pe}) {
      final b = List<int>.filled(4096, 0x90);
      b[0] = 0x4D;
      b[1] = 0x5A;
      // e_lfanew at 0x3C (little-endian u32). 0 for DOS, 0x40 -> PE.
      b[0x3C] = pe ? 0x40 : 0x00;
      b[0x3D] = 0x00;
      b[0x3E] = 0x00;
      b[0x3F] = 0x00;
      if (pe) {
        b[0x40] = 0x50;
        b[0x41] = 0x45;
        b[0x42] = 0x00;
        b[0x43] = 0x00;
      }
      return b;
    }

    List<int> rawCdTrack({int sectors = 4}) {
      final b = List<int>.filled(2352 * sectors, 0x7F);
      // Raw CD sector sync pattern at sector start.
      const sync = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00];
      for (var i = 0; i < sync.length; i++) {
        b[i] = sync[i];
      }
      return b;
    }

    List<int> wiiWad() {
      return [0x49, 0x73, 0x00, 0x00, ...List<int>.filled(2048, 0xAB)];
    }

    List<int> doomWad(String magic) {
      return [...magic.codeUnits, ...List<int>.filled(2048, 0xAB)];
    }

    Future<ImportResult> importFile(String name, List<int> bytes) async {
      final f = await writeBytes(name, bytes);
      return importer.importFile(f.path, knownShas: {}, catalog: catalog);
    }

    test('GB game picks a GB-first core, not the first alphabetical core',
        () async {
      final result = await importFile('game.gb', gbRom());
      expect(result.isSuccess, isTrue,
          reason: result.skippedReason ?? result.error);
      expect(result.game!.coreId, 'gambatte',
          reason: 'a .gb ROM must not be handed to a GBA-first core');
      expect(result.game!.system, 'gb');
    });

    test('GB games keep file-size metadata', () async {
      final result = await importFile('sized.gb', gbRom());
      expect(result.game!.fileSize, 4096);
    });

    test('Wii WAD imports to the GameCube/Wii core', () async {
      final result = await importFile('shop.wad', wiiWad());
      expect(result.isSuccess, isTrue,
          reason: result.skippedReason ?? result.error);
      expect(result.game!.coreId, 'powercube');
      expect(result.game!.system, 'wii');
    });

    test('Doom IWAD/PWAD is rejected — no core can run it', () async {
      for (final magic in ['IWAD', 'PWAD']) {
        final result = await importFile('$magic.wad', doomWad(magic));
        expect(result.isSkipped, isTrue,
            reason: 'a Doom WAD must never import as a GameCube game');
        expect(result.skippedReason, contains('Doom'));
      }
    });

    test('raw CD track .bin is rejected with a .cue/.gdi hint', () async {
      final result = await importFile('track01.bin', rawCdTrack());
      expect(result.isSkipped, isTrue);
      expect(result.skippedReason, contains('cue'));
    });

    test('Windows PE .exe is rejected; plain DOS .exe imports', () async {
      final pe = await importFile('setup.exe', mzExe(pe: true));
      expect(pe.isSkipped, isTrue,
          reason: 'a Windows system executable is not DOS game content');
      expect(pe.skippedReason, contains('Windows'));

      final dos = await importFile('doom.exe', mzExe(pe: false));
      expect(dos.isSuccess, isTrue,
          reason: dos.skippedReason ?? dos.error);
      expect(dos.game!.coreId, 'realmode');
    });

    test('small power-of-two .bin goes to the Atari 2600 core', () async {
      final cart = List<int>.filled(4096, 0xFF);
      final result = await importFile('cart.bin', cart);
      expect(result.isSuccess, isTrue,
          reason: result.skippedReason ?? result.error);
      expect(result.game!.coreId, 'joystick');
      expect(result.game!.system, 'atari2600');
    });

    test('Genesis .bin (SEGA header) goes to the Genesis core', () async {
      final rom = List<int>.filled(262144, 0xFF);
      const sega = [0x53, 0x45, 0x47, 0x41];
      for (var i = 0; i < sega.length; i++) {
        rom[0x100 + i] = sega[i];
      }
      final result = await importFile('sonic.bin', rom);
      expect(result.isSuccess, isTrue,
          reason: result.skippedReason ?? result.error);
      expect(result.game!.coreId, 'blastproc');
      expect(result.game!.system, 'genesis');
    });

    test('GBA homebrew without the Nintendo logo imports (ARM header)',
        () async {
      final rom = List<int>.filled(32768, 0x00);
      rom[3] = 0xEA; // ARM branch at the entry point
      rom[0xB0] = 0x96; // fixed byte, toolchain variant placement
      final result = await importFile('homebrew.gba', rom);
      expect(result.isSuccess, isTrue,
          reason: result.skippedReason ?? result.error);
      expect(result.game!.coreId, 'advancebit');
      expect(result.game!.system, 'gba');
    });

    test('NDS homebrew without the logo imports (ARM header)', () async {
      final rom = List<int>.filled(131072, 0x00);
      rom[3] = 0xEA;
      rom[0xB2] = 0x96;
      rom[0x0C] = 0x23; // "####" placeholder game code
      rom[0x0D] = 0x23;
      rom[0x0E] = 0x23;
      rom[0x0F] = 0x23;
      final result = await importFile('homebrew.nds', rom);
      expect(result.isSuccess, isTrue,
          reason: result.skippedReason ?? result.error);
      expect(result.game!.coreId, 'dualscreen');
      expect(result.game!.system, 'nds');
    });

    test('zip holding a single .nes ROM goes to the NES core', () async {
      final zip = _zipWith('game.nes', 0x00);
      final result = await importFile('nes-pack.zip', zip);
      expect(result.isSuccess, isTrue,
          reason: result.skippedReason ?? result.error);
      expect(result.game!.coreId, 'nesbyte');
      expect(result.game!.system, 'nes');
    });

    test('zip with arcade-style entries goes to the arcade core', () async {
      final zip = _zipWith('sf2.03', 0x00);
      final result = await importFile('sf2.zip', zip);
      expect(result.isSuccess, isTrue,
          reason: result.skippedReason ?? result.error);
      expect(result.game!.coreId, 'coinbox');
      expect(result.game!.system, 'arcade');
    });
  });
}

/// A miniature but spec-shaped ZIP archive (store method) carrying one
/// named entry, used to exercise archive content sniffing: local header,
/// central directory header, end-of-central-directory. Big enough to
/// clear the 512-byte minimum ROM size.
List<int> _zipWith(String entryName, int padByte) {
  final name = entryName.codeUnits;
  final data = List<int>.filled(600, padByte);
  final out = <int>[];

  List<int> le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  List<int> le32(int v) =>
      [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

  // Local file header (30 bytes + name + data).
  out.addAll([0x50, 0x4B, 0x03, 0x04]);
  out.addAll(le16(20)); // version needed
  out.addAll(le16(0)); // flags
  out.addAll(le16(0)); // method: store
  out.addAll(le16(0)); // mod time
  out.addAll(le16(0)); // mod date
  out.addAll(le32(0)); // crc32
  out.addAll(le32(data.length)); // compressed size
  out.addAll(le32(data.length)); // uncompressed size
  out.addAll(le16(name.length));
  out.addAll(le16(0)); // extra length
  out.addAll(name);
  out.addAll(data);

  final cdOffset = out.length;
  // Central directory header (46 bytes + name).
  out.addAll([0x50, 0x4B, 0x01, 0x02]);
  out.addAll(le16(20)); // version made by
  out.addAll(le16(20)); // version needed
  out.addAll(le16(0)); // flags
  out.addAll(le16(0)); // method
  out.addAll(le16(0)); // time
  out.addAll(le16(0)); // date
  out.addAll(le32(0)); // crc
  out.addAll(le32(data.length)); // compressed size
  out.addAll(le32(data.length)); // uncompressed size
  out.addAll(le16(name.length));
  out.addAll(le16(0)); // extra
  out.addAll(le16(0)); // comment
  out.addAll(le16(0)); // disk start
  out.addAll(le16(0)); // internal attrs
  out.addAll(le32(0)); // external attrs
  out.addAll(le32(0)); // local header offset
  out.addAll(name);
  final cdSize = out.length - cdOffset;

  // End of central directory.
  out.addAll([0x50, 0x4B, 0x05, 0x06]);
  out.addAll(le16(0)); // disk
  out.addAll(le16(0)); // cd start disk
  out.addAll(le16(1)); // entries on this disk
  out.addAll(le16(1)); // total entries
  out.addAll(le32(cdSize));
  out.addAll(le32(cdOffset));
  out.addAll(le16(0)); // comment length
  return out;
}

/// Catalog mirroring the real one's extension overlaps: several cores
/// claim .gb/.gbc, several claim .bin, and .wad belongs to powercube.
Map<String, CoreManifest> _multiCatalog() {
  CoreManifest core(
    String id,
    String name,
    List<String> systems,
    List<String> extensions,
  ) =>
      CoreManifest(
        id: id,
        name: name,
        version: '1.0',
        license: 'MIT',
        systems: systems,
        extensions: extensions,
        cheatFamilies: const [],
        cheatsSupported: false,
        delivery: const {},
        artifacts: const {},
      );

  return {
    'advancebit': core('advancebit', 'AdvanceBit', ['gba', 'gb', 'gbc'],
        ['gba', 'gb', 'gbc', 'zip']),
    'blastproc': core('blastproc', 'BlastProc', ['genesis', 'sms', 'gg', 'scd'],
        ['md', 'gen', 'sms', 'gg', 'sg', 'bin', 'iso', 'cue', 'chd', 'zip']),
    'cardcon': core('cardcon', 'CardCon', ['pce', 'pcecd'],
        ['pce', 'sgx', 'cue', 'ccd', 'chd', 'zip']),
    'coinbox': core('coinbox', 'CoinBox', ['arcade', 'neogeo'], ['zip']),
    'dreamarc': core('dreamarc', 'DreamArc', ['dc', 'naomi'],
        ['cdi', 'gdi', 'chd', 'cue', 'zip', 'lst', 'bin']),
    'dualscreen': core('dualscreen', 'DualScreen', ['nds'], ['nds', 'zip']),
    'gambatte': core('gambatte', 'Gambatte', ['gb', 'gbc'], ['gb', 'gbc', 'zip']),
    'geometry1': core('geometry1', 'Geometry1', ['psx'],
        ['cue', 'ccd', 'chd', 'pbp', 'iso', 'm3u']),
    'joystick': core('joystick', 'Joystick', ['atari2600'],
        ['a26', 'bin', 'zip']),
    'nesbyte': core('nesbyte', 'NesByte', ['nes', 'fds'],
        ['nes', 'fds', 'unf', 'zip']),
    'pointclick': core('pointclick', 'PointClick', ['scumm'],
        ['scummvm', 'zip']),
    'powercube': core('powercube', 'PowerCube', ['gc', 'wii'],
        ['iso', 'gcm', 'ciso', 'wbfs', 'rvz', 'elf', 'dol', 'wad']),
    'realmode': core('realmode', 'RealMode', ['dos'],
        ['zip', 'exe', 'com', 'bat', 'iso', 'img']),
    'superfx': core('superfx', 'SuperFX', ['snes'],
        ['sfc', 'smc', 'fig', 'zip']),
  };
}

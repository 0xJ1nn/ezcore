/// Deep classification test: ROM content validation must accept the
/// playable content each bundled core declares, and reject system files
/// that abuse the same (or a similar) extension.
///
/// Driven from the real committed catalog (`cores/catalog.json`) so a
/// new core/extension automatically joins the sweep. Cases:
///
///  * text impostor on a binary format       -> rejected  (README.nes)
///  * wrong-magic binary on a binary format  -> rejected  (ELF named .gb,
///    AppleDouble `._x.nes`, HTML saved as .zip)
///  * wrong/no extension system files        -> no core    (desktop.ini,
///    Thumbs.db, autorun.inf)
///  * correct-magic synthetic per format     -> accepted
///  * real generated iNES ROM                -> accepted end-to-end
///  * text-by-spec formats (cue/ccd/gdi/m3u/lst/scummvm/bat) -> accepted
///  * empty / too-small / oversized files    -> rejected
///
/// Format facts used below are spec-level (ISO9660 PVD at 0x8000, NDS
/// logo at 0xC0, Sega "TMR SEGA" header at 0x7FF0, UNIF magic, N64 byte
/// orders); formats without a reliable signature are classified
/// headerless and only size/text gates apply.
///
/// This file is a permanent test (project.md §79 compliant).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/services/content_importer.dart';
import 'package:ezcore/services/hash_verifier.dart';
import 'package:ezcore/services/rom_validator.dart';

/// Formats whose real-world content is text by specification. A bundled
/// core declares these extensions, so a mostly-text file carrying one of
/// them is plausible content, not a system-file impostor. Conversely, a
/// *binary* file posing as one of these is rejected (inverse gate).
const textBySpec = {'cue', 'ccd', 'gdi', 'm3u', 'lst', 'scummvm', 'bat'};

/// Formats with no reliable signature in their spec (raw carts, disc
/// system areas, container dumps, uncertain headers). Any non-text
/// binary within the size bounds is plausible; text impostors are still
/// rejected earlier.
const headerless = {
  'a26', 'bin', 'fig', 'com', 'img', 'pce', 'sgx', 'sg', 'sfc', 'smc',
  'dol', 'gcm', 'cdi', 'rvz', 'pbp', 'prx',
};

/// Spec-level magic per extension: (offset, bytes) checks as the real
/// format carries them. Mirrors the validator contract; text-by-spec and
/// headerless formats carry no entry.
const magic = <String, List<(int, List<int>)>>{
  'nes': [(0, [0x4E, 0x45, 0x53, 0x1A])],
  'gb': [(0x104, [0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B])],
  'gbc': [(0x104, [0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B])],
  'gba': [(0x04, [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21])],
  'nds': [(0xC0, [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21])],
  'iso': [(0x8000, [0x01, 0x43, 0x44, 0x30, 0x30, 0x31])],
  'md': [(0x100, [0x53, 0x45, 0x47, 0x41])],
  'gen': [(0x100, [0x53, 0x45, 0x47, 0x41])],
  'sms': [(0x7FF0, [0x54, 0x4D, 0x52, 0x20, 0x53, 0x45, 0x47, 0x41])],
  'gg': [(0x7FF0, [0x54, 0x4D, 0x52, 0x20, 0x53, 0x45, 0x47, 0x41])],
  // All three standard N64 byte orders — collections mix them and any
  // of the three extensions may carry any of them:
  'n64': [
    (0, [0x80, 0x37, 0x12, 0x40]), // z64 big-endian (native)
    (0, [0x40, 0x12, 0x37, 0x80]), // .n64 little-endian
    (0, [0x37, 0x80, 0x40, 0x12]), // .v64 byte-swapped
  ],
  'z64': [
    (0, [0x80, 0x37, 0x12, 0x40]),
    (0, [0x40, 0x12, 0x37, 0x80]),
    (0, [0x37, 0x80, 0x40, 0x12]),
  ],
  'v64': [
    (0, [0x37, 0x80, 0x40, 0x12]),
    (0, [0x80, 0x37, 0x12, 0x40]),
    (0, [0x40, 0x12, 0x37, 0x80]),
  ],
  'chd': [(0, [0x4D, 0x43, 0x6F, 0x6D, 0x70, 0x72, 0x48, 0x44])],
  'zip': [(0, [0x50, 0x4B, 0x03, 0x04])],
  'cso': [(0, [0x43, 0x49, 0x53, 0x4F])],
  'ciso': [(0, [0x43, 0x49, 0x53, 0x4F])],
  'wad': [
    (0, [0x49, 0x57, 0x41, 0x44]), // IWAD
    (0, [0x50, 0x57, 0x41, 0x44]), // PWAD (mods — playable content)
  ],
  'wbfs': [(0, [0x57, 0x42, 0x46, 0x53])],
  'exe': [(0, [0x4D, 0x5A])],
  'fds': [(0, [0x46, 0x44, 0x53, 0x1A])],
  'unf': [(0, [0x55, 0x4E, 0x49, 0x46])], // UNIF
  'elf': [(0, [0x7F, 0x45, 0x4C, 0x46])],
};

List<(int, List<int>)> magicFor(String ext) => magic[ext] ?? const [];

void main() {
  const validator = RomValidator();
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ezcore_deep_validation');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File write(String name, List<int> bytes) {
    final f = File('${dir.path}/$name');
    f.writeAsBytesSync(bytes, flush: true);
    return f;
  }

  /// Fills [size] bytes with non-text binary (0xFF), then stamps [ext]'s
  /// magic at its real offset. Size auto-grows so high-offset headers
  /// (SMS/GG at 0x7FF0, ISO at 0x8000) fit.
  List<int> binaryWithMagic(String ext) {
    var size = 4096;
    for (final (offset, bytes) in magicFor(ext)) {
      if (offset + bytes.length + 16 > size) size = offset + bytes.length + 16;
    }
    final out = List<int>.filled(size, 0xFF);
    for (final (offset, bytes) in magicFor(ext)) {
      for (var i = 0; i < bytes.length; i++) {
        out[offset + i] = bytes[i];
      }
    }
    return out;
  }

  /// Builds the committed catalog as `id -> CoreManifest` — the exact
  /// shape ContentImporter consumes.
  Map<String, CoreManifest> loadCatalog() {
    final raw = json.decode(File('cores/catalog.json').readAsStringSync())
        as Map<String, dynamic>;
    return <String, CoreManifest>{
      for (final e in raw.entries)
        e.key: CoreManifest.fromJson(e.value as Map<String, dynamic>),
    };
  }

  group('catalog-driven sweep (every bundled core extension)', () {
    final catalog = json.decode(File('cores/catalog.json').readAsStringSync())
        as Map<String, dynamic>;

    final extToCores = <String, List<String>>{};
    catalog.forEach((id, dynamic m) {
      final map = m as Map<String, dynamic>;
      if (map['blocked'] == true || id.endsWith('_hold')) return;
      for (final e in (map['extensions'] as List? ?? const [])) {
        extToCores.putIfAbsent((e as String).toLowerCase(), () => []).add(id);
      }
    });

    test('catalog exposes the expected extension set', () {
      expect(extToCores.length, greaterThanOrEqualTo(40),
          reason: 'catalog parse yielded too few extensions — parser or '
              'catalog shape changed');
      expect(textBySpec.union(headerless).union(magic.keys.toSet()).length,
          greaterThanOrEqualTo(extToCores.length),
          reason: 'test classification tables must cover every bundled '
              'extension');
    });

    for (final entry in extToCores.entries) {
      final ext = entry.key;
      final cores = entry.value;

      if (textBySpec.contains(ext)) {
        test('.$ext is text-by-spec: real-shaped text accepted '
            '(${cores.join(', ')})', () async {
          final content = switch (ext) {
            'cue' => 'FILE "game (Track 1).bin" BINARY\n'
                '  TRACK 01 MODE2/2350\n'
                '    INDEX 01 00:00:00\n',
            'm3u' => 'game_CD1.chd\ngame_CD2.chd\n',
            'ccd' => '[CloneCD]\nReadSubData=0\nImgPath=game.img\n',
            'gdi' => '1\n"track01.bin" 0 4 2352\n"track02.raw" 0 0 2352\n',
            'lst' => 'game.bin 0 2352\nTRACK02.raw 0 1 2352\n',
            'scummvm' => 'game\n../games\n\n',
            _ => '@echo off\r\ngame.exe\r\n',
          };
          final f = write('real.$ext', content.codeUnits);
          expect(await validator.validate(f.path, ext), isTrue,
              reason: 'a real .$ext file is text by spec — a bundled core '
                  'declares .$ext, so playable content must import');
        });

        test('.$ext inverse gate: empty rejected', () async {
          final f = write('empty.$ext', const []);
          expect(await validator.validate(f.path, ext), isFalse);
        });

        test('.$ext inverse gate: binary impostor rejected', () async {
          final f = write('binary.$ext', binaryWithMagic('nes'));
          expect(await validator.validate(f.path, ext), isFalse,
              reason: 'binary data posing as text-format .$ext must fail');
        });
        continue;
      }

      final isHeaderless = headerless.contains(ext);
      final hasMagic = magicFor(ext).isNotEmpty;

      test('.$ext playable content accepted (${cores.join(', ')})',
          () async {
        final f = write('real.$ext', binaryWithMagic(ext));
        expect(await validator.validate(f.path, ext), isTrue,
            reason: isHeaderless
                ? 'headerless .$ext must accept binary content'
                : 'format-correct binary .$ext must import');
      });

      if (hasMagic && !isHeaderless) {
        test('.$ext wrong-magic binary rejected (system file with the '
            'same extension)', () async {
          // DEADBEEF payload: matches no known ROM magic (for .elf an ELF
          // header would be the *correct* magic, not an impostor).
          final bytes = List<int>.filled(4096, 0xDE);
          bytes[1] = 0xAD;
          bytes[2] = 0xBE;
          bytes[3] = 0xEF;
          final f = write('system.$ext', bytes);
          expect(await validator.validate(f.path, ext), isFalse,
              reason: 'a system binary renamed .$ext must not import');
        });
      }

      test('.$ext text impostor rejected (README renamed)', () async {
        final f = write('impostor.$ext',
            'README\nNot a game — plain text wearing the .$ext extension.'
                .padRight(600)
                .codeUnits);
        expect(await validator.validate(f.path, ext), isFalse,
            reason: 'text file posing as .$ext must not import');
      });
    }
  });

  group('system files abusing ROM extensions', () {
    test('AppleDouble ._game.nes rejected', () async {
      final f = write(
          '._game.nes', [0x00, 0x05, 0x16, 0x07, ...List<int>.filled(600, 0x01)]);
      expect(await validator.validate(f.path, 'nes'), isFalse);
    });

    test('ELF binary renamed to .gb rejected (Nintendo logo not at 0x104)',
        () async {
      final bytes = List<int>.filled(4096, 0);
      bytes[0] = 0x7F;
      bytes[1] = 0x45;
      bytes[2] = 0x4C;
      bytes[3] = 0x46;
      final f = write('game.gb', bytes);
      expect(await validator.validate(f.path, 'gb'), isFalse);
    });

    test('HTML page saved as .zip rejected', () async {
      final f = write(
          'save.zip',
          '<html><body>not a zip at all</body></html>'
              .padRight(600)
              .codeUnits);
      expect(await validator.validate(f.path, 'zip'), isFalse);
    });

    test('real ZIP (PK header) accepted', () async {
      final f =
          write('game.zip', [0x50, 0x4B, 0x03, 0x04, ...List<int>.filled(600, 0xAB)]);
      expect(await validator.validate(f.path, 'zip'), isTrue);
    });

    test('zero-byte .nes rejected', () async {
      final f = write('empty.nes', const []);
      expect(await validator.validate(f.path, 'nes'), isFalse);
    });

    test('too-small .nes rejected (< 512 bytes)', () async {
      final f = write('tiny.nes', [0x4E, 0x45, 0x53, 0x1A, 0, 0]);
      expect(await validator.validate(f.path, 'nes'), isFalse);
    });

    test('oversized file rejected (> 512 MB, sparse)', () async {
      final f = write('huge.nes', binaryWithMagic('nes'));
      final raf = f.openSync(mode: FileMode.append);
      raf.truncateSync(RomValidator.maxRomSize + 1);
      raf.closeSync();
      expect(await validator.validate(f.path, 'nes'), isFalse);
    });

    test('WAD accepts both IWAD and PWAD (base games and mods)', () async {
      for (final head in [
        [0x49, 0x57, 0x41, 0x44], // IWAD
        [0x50, 0x57, 0x41, 0x44], // PWAD
      ]) {
        final f = write('wad_case.wad',
            [...head, ...List<int>.filled(600, 0xAB)]);
        expect(await validator.validate(f.path, 'wad'), isTrue,
            reason: 'magic ${head.map((b) => b.toRadixString(16))} must '
                'import');
      }
    });

    test('N64 ROMs import in all three standard byte orders, under each '
        'of .n64/.z64/.v64', () async {
      const orders = <String, List<int>>{
        'z64': [0x80, 0x37, 0x12, 0x40], // big-endian (native)
        'n64': [0x40, 0x12, 0x37, 0x80], // little-endian
        'v64': [0x37, 0x80, 0x40, 0x12], // byte-swapped
      };
      for (final ext in ['n64', 'z64', 'v64']) {
        for (final order in orders.entries) {
          final f = write('rom_$order.$ext',
              [...order.value, ...List<int>.filled(600, 0xFF)]);
          expect(await validator.validate(f.path, ext), isTrue,
              reason: 'a real ${order.key}-order dump named .$ext must '
                  'import');
        }
      }
    });

    test('undeclared extension gets no core (desktop.ini)', () async {
      final f = write('desktop.ini', List<int>.filled(600, 0x01));
      final result = await ContentImporter(const _StubHashVerifier())
          .importFile(f.path, knownShas: {}, catalog: loadCatalog());
      expect(result.isSkipped, isTrue);
      expect(result.skippedReason, contains('No core for extension'));
    });
  });

  group('real playable ROM end-to-end', () {
    test('generated iNES ROM imports through ContentImporter', () async {
      final rom = ensureNesFixture();
      if (rom == null) {
        // Generator unavailable on this machine — skip loudly rather
        // than fabricate a pass.
        markTestSkipped('gen_nes_minimal_rom.py unavailable — real-ROM '
            'case skipped');
        return;
      }

      expect(await validator.validate(rom.absolute.path, 'nes'), isTrue,
          reason: "the repo's own generated NES ROM must validate");

      final result = await ContentImporter(const _StubHashVerifier())
          .importFile(rom.absolute.path,
              knownShas: <String>{}, catalog: loadCatalog());
      expect(result.isSuccess, isTrue,
          reason: 'import outcome: ${result.skippedReason ?? result.error}');
      expect(result.game!.coreId, 'nesbyte');
      expect(result.game!.system, isNotEmpty);
    });
  });

  group('importer-level rejection messages', () {
    test('text impostor surfaces validation skip reason', () async {
      final f = write('notes.nes',
          'just some text file with a .nes extension'.padRight(600).codeUnits);
      final result = await ContentImporter(const _StubHashVerifier())
          .importFile(f.path, knownShas: {}, catalog: loadCatalog());
      expect(result.isSkipped, isTrue);
      expect(result.skippedReason, contains('content validation'));
    });
  });
}

/// Returns the repo-generated CC0 NES ROM, regenerating it when absent.
File? ensureNesFixture() {
  final rom = File('native/test-roms/ezcore_nes_minimal.nes');
  if (rom.existsSync()) return rom;
  final gen = Process.runSync('python3', ['scripts/gen_nes_minimal_rom.py']);
  return gen.exitCode == 0 && rom.existsSync() ? rom : null;
}

/// Deterministic stand-in for the platform hash verifier: content is
/// never a duplicate in these tests.
class _StubHashVerifier implements HashVerifier {
  const _StubHashVerifier();

  @override
  Future<String> sha256File(String path) async =>
      'stub-${path.hashCode.toRadixString(16)}';
}

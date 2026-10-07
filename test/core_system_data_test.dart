// Core system data (ADR-021): a core's own data folders, shipped under
// system/ in its package and copied into the system dir. Data only, exactly
// the declared folders, never BIOS, never someone else's folder.
import 'dart:convert';
import 'dart:io';

import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/services/core_package_installer.dart';
import 'package:ezcore/services/core_package_validator.dart';
import 'package:ezcore/services/core_system_data.dart';
import 'package:ezcore/services/hash_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('ezsysdata'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// <tmp>/pkg/system/<name>/... with the given files (path -> bytes).
  Directory package(Map<String, List<int>> files) {
    final sys = Directory('${tmp.path}/pkg/system')..createSync(recursive: true);
    files.forEach((path, bytes) {
      File('${sys.path}/$path')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    });
    return sys;
  }

  group('manifest field', () {
    test('absent is fine; a short list of plain names is parsed', () {
      expect(CoreManifest.parseSystemData(null).names, isEmpty);
      final r = CoreManifest.parseSystemData(['dolphin-emu', 'PPSSPP']);
      expect(r.names, ['dolphin-emu', 'PPSSPP']);
      expect(r.errors, isEmpty);
    });

    test('paths, dot names, repeats, non-lists and long lists are refused', () {
      expect(CoreManifest.parseSystemData('dolphin-emu').errors, isNotEmpty);
      expect(CoreManifest.parseSystemData(['../escape']).errors, isNotEmpty);
      expect(CoreManifest.parseSystemData(['a/b']).errors, isNotEmpty);
      expect(CoreManifest.parseSystemData(['..']).errors, isNotEmpty);
      expect(CoreManifest.parseSystemData(['a', 'a']).errors, isNotEmpty);
      expect(CoreManifest.parseSystemData(['a', 'b', 'c', 'd', 'e']).errors,
          isNotEmpty);
    });

    test('the manifest carries it through JSON and validate()', () {
      final m = CoreManifest.fromJson({
        'id': 'x',
        'name': 'X',
        'version': '1',
        'license': 'GPL-2.0',
        'systems': ['gc'],
        'system_data': ['dolphin-emu', '../bad'],
      });
      expect(m.systemData, ['dolphin-emu']);
      expect(m.validate().join(), contains('not a plain folder name'));
      expect(m.toJson()['system_data'], ['dolphin-emu']);
    });
  });

  group('rules', () {
    test('accepts exactly the declared folders of plain data', () {
      final sys = package({
        'dolphin-emu/Sys/GC/font.bin': [1, 2, 3],
        'dolphin-emu/Sys/codehandler.bin': [0x3C, 0x60], // PowerPC, not host code
      });
      final r = checkSystemData(sys, declared: ['dolphin-emu']);
      expect(r.errors, isEmpty);
      expect(r.files, 2);
    });

    test('refuses undeclared and missing folders, and loose files', () {
      final sys = package({
        'dolphin-emu/a.ini': [1],
        'other/b.ini': [1],
        'loose.txt': [1],
      });
      final r = checkSystemData(sys, declared: ['dolphin-emu', 'PPSSPP']);
      expect(r.errors.join('\n'), contains('system/other is not declared'));
      expect(r.errors.join('\n'), contains('system/PPSSPP is missing'));
      expect(r.errors.join('\n'), contains('only the declared folders'));
    });

    test('declared but no system/ folder: an error when copying, fine for '
        'a manifest-only folder', () {
      final none = Directory('${tmp.path}/none');
      expect(checkSystemData(none, declared: ['PPSSPP']).errors, isNotEmpty);
      expect(
        checkSystemData(none, declared: ['PPSSPP'], requirePresent: false)
            .errors,
        isEmpty,
      );
    });

    test('refuses links', () {
      final sys = package({'PPSSPP/a.ini': [1]});
      Link('${sys.path}/PPSSPP/ln').createSync('${sys.path}/PPSSPP/a.ini');
      expect(checkSystemData(sys, declared: ['PPSSPP']).errors.join(),
          contains('links are not allowed'));
    });

    test('refuses files with an execute bit', () {
      final sys = package({'PPSSPP/run.dat': [1, 2]});
      Process.runSync('chmod', ['+x', '${sys.path}/PPSSPP/run.dat']);
      expect(checkSystemData(sys, declared: ['PPSSPP']).errors.join(),
          contains('is executable'));
    });

    for (final (what, bytes) in [
      ('ELF', [0x7F, 0x45, 0x4C, 0x46, 2]),
      ('Mach-O', [0xCF, 0xFA, 0xED, 0xFE]),
      ('PE', [0x4D, 0x5A, 0x90, 0]),
      ('shebang', '#!/bin/sh\n'.codeUnits),
    ]) {
      test('refuses a file that starts like a program ($what)', () {
        final sys = package({'PPSSPP/x.bin': bytes});
        expect(checkSystemData(sys, declared: ['PPSSPP']).errors.join(),
            contains('starts like a program'));
      });
    }

    test('refuses a file named like a BIOS', () {
      final sys = package({'dolphin-emu/Sys/GC/IPL.bin': [1]});
      expect(
        checkSystemData(sys, declared: ['dolphin-emu'], biosFiles: ['ipl.bin'])
            .errors
            .join(),
        contains('BIOS'),
      );
    });

    test('caps size and file count', () {
      final sys = package({
        'PPSSPP/a': List.filled(10, 0),
        'PPSSPP/b': List.filled(10, 0),
      });
      expect(checkSystemData(sys, declared: ['PPSSPP'], maxBytes: 15).errors,
          isNotEmpty);
      expect(checkSystemData(sys, declared: ['PPSSPP'], maxFiles: 1).errors,
          isNotEmpty);
    });
  });

  group('copying into the system dir', () {
    Future<({List<String> errors, List<String> warnings})> copy(
      Directory from,
      Directory to, {
      String version = '1.0',
    }) =>
        copySystemData(
          from: from,
          to: to,
          coreId: 'portcomp',
          version: version,
          declared: const ['PPSSPP'],
        );

    test('copies the folder and marks it as ours', () async {
      final sys = package({'PPSSPP/compat.ini': 'x=1'.codeUnits});
      final to = Directory('${tmp.path}/system')..createSync();
      final r = await copy(sys, to);
      expect(r.errors, isEmpty);
      expect(File('${to.path}/PPSSPP/compat.ini').readAsStringSync(), 'x=1');
      expect(File('${to.path}/PPSSPP/$systemDataMarker').readAsStringSync(),
          'portcomp 1.0\n');
    });

    test('is a no-op for the same version, and refreshes on a new one',
        () async {
      final sys = package({'PPSSPP/compat.ini': 'v1'.codeUnits});
      final to = Directory('${tmp.path}/system')..createSync();
      await copy(sys, to);
      // A user edit inside our copy survives a same-version session...
      File('${to.path}/PPSSPP/compat.ini').writeAsStringSync('edited');
      await copy(sys, to);
      expect(File('${to.path}/PPSSPP/compat.ini').readAsStringSync(), 'edited');
      // ...and a new core version replaces the folder with its own data.
      File('${sys.path}/PPSSPP/compat.ini').writeAsStringSync('v2');
      File('${to.path}/PPSSPP/stale.ini').writeAsStringSync('old');
      await copy(sys, to, version: '2.0');
      expect(File('${to.path}/PPSSPP/compat.ini').readAsStringSync(), 'v2');
      expect(File('${to.path}/PPSSPP/stale.ini').existsSync(), isFalse);
    });

    test("never touches a folder of the same name that isn't ours", () async {
      final sys = package({'PPSSPP/compat.ini': 'core'.codeUnits});
      final to = Directory('${tmp.path}/system')..createSync();
      File('${to.path}/PPSSPP/mine.ini')
        ..createSync(recursive: true)
        ..writeAsStringSync('user');
      final r = await copy(sys, to);
      expect(r.warnings.single, contains('not made by ezCORE'));
      expect(File('${to.path}/PPSSPP/mine.ini').readAsStringSync(), 'user');
      expect(File('${to.path}/PPSSPP/compat.ini').existsSync(), isFalse);
    });

    test('copies nothing when the data breaks a rule', () async {
      final sys = package({'PPSSPP/x.bin': [0x7F, 0x45, 0x4C, 0x46]});
      final to = Directory('${tmp.path}/system')..createSync();
      final r = await copy(sys, to);
      expect(r.errors, isNotEmpty);
      expect(Directory('${to.path}/PPSSPP').existsSync(), isFalse);
    });

    test('nothing declared, nothing to do', () async {
      final r = await copySystemData(
        from: Directory('${tmp.path}/nowhere'),
        to: Directory('${tmp.path}/system'),
        coreId: 'x',
        version: '1',
        declared: const [],
      );
      expect(r.errors, isEmpty);
      expect(Directory('${tmp.path}/system').existsSync(), isFalse);
    });
  });

  group('packages', () {
    Future<Directory> pkg({List<String>? declared}) async {
      final dir = Directory('${tmp.path}/pkgsrc/demo')..createSync(recursive: true);
      final lib = File('${dir.path}/demo.${PackageInstaller.libraryExtension}')
        ..writeAsBytesSync(List.filled(64, 9));
      final pin = await const DartHashVerifier().sha256File(lib.path);
      File('${dir.path}/manifest.json').writeAsStringSync(jsonEncode({
        'id': 'demo',
        'name': 'Demo',
        'version': '1.0',
        'license': 'MIT',
        'systems': ['gc'],
        'delivery': {Platform.operatingSystem: 'bundled'},
        'artifacts': {PackageInstaller.platformKey: pin},
        'system_data': ?declared,
      }));
      File('${dir.path}/system/demo-emu/Sys/a.ini')
        ..createSync(recursive: true)
        ..writeAsStringSync('k=v');
      return dir;
    }

    test('an undeclared system/ folder does not validate', () async {
      final report = await PackageValidationReport.validate(await pkg());
      expect(report.ok, isFalse);
      expect(report.errors.join(), contains('not declared in system_data'));
    });

    test('declared system data is installed next to the core', () async {
      final vault = Directory('${tmp.path}/vault');
      final report = await PackageInstaller().install(
        await pkg(declared: ['demo-emu']),
        userConsented: true,
        vaultOverride: vault,
      );
      expect(report.ok, isTrue, reason: report.errors.join());
      final copied = '${vault.path}/cores/demo/system/demo-emu';
      expect(File('$copied/Sys/a.ini').readAsStringSync(), 'k=v');
      expect(File('$copied/$systemDataMarker').readAsStringSync(), 'demo 1.0\n');
    });
  });
}


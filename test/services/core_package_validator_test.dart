// SPDX-License-Identifier: MIT
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/core_package_validator.dart';

/// Reference shape taken verbatim from `cores/nesbyte/manifest.json`
/// (real pins, real delivery/artifacts layout). [id] is parameterized so the
/// same fixture can be mutated per-case.
Map<String, dynamic> nesbyteManifest(String id) => <String, dynamic>{
  'id': id,
  'name': 'NesByte',
  'version': '0.9.9',
  'license': 'GPL-3.0',
  'license_url': 'https://github.com/libretro/Mesen/blob/master/LICENSE',
  'homepage': 'https://github.com/SourMesen/Mesen2',
  'upstream': 'libretro/Mesen',
  'systems': ['nes', 'fds'],
  'extensions': ['nes', 'fds', 'unf', 'zip'],
  'cheats_supported': true,
  'cheat_families': ['nes_gamegenie'],
  'bios_required': false,
  'bios_files': ['disksys.rom'],
  'delivery': <String, String>{
    'macos': 'bundled',
    'windows': 'bundled',
    'linux': 'bundled',
    'android': 'bundled',
    'ios': 'bundled',
  },
  'artifacts': <String, String>{
    'macos-arm64':
        '940e471244ce202441442748dcae5d207690f8b876de5e56fe165bda59e8527b',
    'android-arm64':
        '7063eb166524c184f175d81d840eae167e90ae78fdf56ac79281cb035d3e44f2',
    'linux-x64':
        'c883579a185a3aa880678b731b34b6448715afa87ce6ef785c6b20bc7d9a88a5',
  },
  'execution': <String, String>{
    'macos': 'interpreter',
    'windows': 'interpreter',
    'linux': 'interpreter',
    'android': 'interpreter',
    'ios': 'interpreter',
  },
  'bios_notes': 'FDS only, optional. User-supplied.',
  'provenance': <String, String>{
    'built_from': 'https://github.com/libretro/Mesen',
    'upstream_license': 'GPL-3.0',
    'relationship':
        'independent build of upstream source; not affiliated with, endorsed '
        'by, or supported by the upstream project',
  },
};

/// Writes [manifest] to `<base>/<name>/manifest.json` (optionally with a
/// padding data file) and returns that package directory.
Future<Directory> _writePackage(
  Directory base,
  String name,
  Map<String, dynamic> manifest, {
  int dataSize = 0,
}) async {
  final dir = Directory('${base.path}/$name');
  await dir.create(recursive: true);
  await File('${dir.path}/manifest.json').writeAsString(jsonEncode(manifest));
  if (dataSize > 0) {
    await File(
      '${dir.path}/data.bin',
    ).writeAsBytes(List<int>.filled(dataSize, 0));
  }
  return dir;
}

void main() {
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('ezcore_pkg');
  });
  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  test('valid nesbyte-shaped package passes', () async {
    final dir = await _writePackage(
      base,
      'nesbyte',
      nesbyteManifest('nesbyte'),
    );
    final report = await PackageValidationReport.validate(dir);
    expect(report.ok, isTrue);
    expect(report.errors, isEmpty);
  });

  test('artifacts pin that is not 64-char lowercase hex is rejected', () async {
    final m = nesbyteManifest('nesbyte');
    (m['artifacts'] as Map<String, dynamic>)['linux-x64'] =
        'A' * 64; // uppercase
    final dir = await _writePackage(base, 'nesbyte', m);
    final report = await PackageValidationReport.validate(dir);
    expect(report.ok, isFalse);
    expect(report.errors.any((e) => e.contains('pin')), isTrue);
  });

  test('id not matching [a-z0-9_]+ is rejected', () async {
    final m = nesbyteManifest('Bad_ID!');
    final dir = await _writePackage(base, 'Bad_ID!', m);
    final report = await PackageValidationReport.validate(dir);
    expect(report.ok, isFalse);
    expect(
      report.errors.any((e) => e.contains('must match [a-z0-9_]+')),
      isTrue,
    );
  });

  test('id not matching directory name is rejected', () async {
    final m = nesbyteManifest('other'); // dir is 'nesbyte'
    final dir = await _writePackage(base, 'nesbyte', m);
    final report = await PackageValidationReport.validate(dir);
    expect(report.ok, isFalse);
    expect(
      report.errors.any((e) => e.contains('does not match directory name')),
      isTrue,
    );
  });

  test('invalid delivery value is rejected', () async {
    final m = nesbyteManifest('nesbyte');
    (m['delivery'] as Map<String, dynamic>)['ios'] = 'streaming';
    final dir = await _writePackage(base, 'nesbyte', m);
    final report = await PackageValidationReport.validate(dir);
    expect(report.ok, isFalse);
    expect(report.errors.any((e) => e.contains('delivery')), isTrue);
  });

  test('unknown top-level field is rejected', () async {
    final m = nesbyteManifest('nesbyte');
    m['evil_field'] = true;
    final dir = await _writePackage(base, 'nesbyte', m);
    final report = await PackageValidationReport.validate(dir);
    expect(report.ok, isFalse);
    expect(report.errors, contains('unknown top-level field "evil_field"'));
  });

  test('symlink anywhere in package is rejected', () async {
    final dir = await _writePackage(
      base,
      'nesbyte',
      nesbyteManifest('nesbyte'),
    );
    await Link('${dir.path}/evil_link').create('${dir.path}/manifest.json');
    final report = await PackageValidationReport.validate(dir);
    expect(report.ok, isFalse);
    expect(report.errors.any((e) => e.contains('symlink')), isTrue);
  });

  test('package exceeding size cap is rejected', () async {
    final m = nesbyteManifest('nesbyte');
    final dir = await _writePackage(base, 'nesbyte', m, dataSize: 8192);
    final report = await PackageValidationReport.validate(
      dir,
      maxPackageBytes: 2048,
    );
    expect(report.ok, isFalse);
    expect(report.errors.any((e) => e.contains('size cap')), isTrue);
  });

  test('manifest exceeding manifest size cap is rejected', () async {
    final m = nesbyteManifest('nesbyte');
    (m['provenance'] as Map<String, dynamic>)['relationship'] = 'x' * 2048;
    final dir = await _writePackage(base, 'nesbyte', m);
    final report = await PackageValidationReport.validate(
      dir,
      maxManifestBytes: 1024,
    );
    expect(report.ok, isFalse);
    expect(
      report.errors.any((e) => e.contains('manifest.json exceeds size cap')),
      isTrue,
    );
  });

  test('missing manifest.json is rejected', () async {
    final dir = Directory('${base.path}/empty');
    await dir.create();
    final report = await PackageValidationReport.validate(dir);
    expect(report.ok, isFalse);
    expect(report.errors.any((e) => e.contains('missing')), isTrue);
  });

  test('invalid JSON manifest is rejected', () async {
    final dir = Directory('${base.path}/badjson');
    await dir.create();
    await File('${dir.path}/manifest.json').writeAsString('{not json');
    final report = await PackageValidationReport.validate(dir);
    expect(report.ok, isFalse);
    expect(report.errors.any((e) => e.contains('not valid JSON')), isTrue);
  });

  test('missing id is reported', () async {
    final m = nesbyteManifest('nesbyte');
    m.remove('id');
    final dir = await _writePackage(base, 'nesbyte', m);
    final report = await PackageValidationReport.validate(dir);
    expect(report.errors.any((e) => e.contains('id')), isTrue);
  });

  test('bios_required without bios_files is a warning, not an error', () async {
    final m = nesbyteManifest('nesbyte');
    m['bios_required'] = true;
    m['bios_files'] = <String>[];
    final dir = await _writePackage(base, 'nesbyte', m);
    final report = await PackageValidationReport.validate(dir);
    expect(report.ok, isTrue);
    expect(report.errors, isEmpty);
    expect(report.warnings.any((w) => w.contains('bios_files')), isTrue);
  });

  test('every committed manifest in cores/ validates', () async {
    // Reality as the mutation test: the vocabulary, the known-field set,
    // and the pin format must accept the repository's own 21 manifests.
    final cores = Directory('cores');
    if (!cores.existsSync()) {
      markTestSkipped('no cores/ directory in this checkout');
      return;
    }
    final dirs = cores
        .listSync()
        .whereType<Directory>()
        .where((d) => File('${d.path}/manifest.json').existsSync())
        .toList();
    expect(dirs.length, greaterThan(0));
    final failures = <String>[];
    for (final d in dirs) {
      final report = await PackageValidationReport.validate(d);
      if (!report.ok) failures.add('${d.path}: ${report.errors}');
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}

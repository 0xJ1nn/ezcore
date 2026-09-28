// SPDX-License-Identifier: MIT
//
// Tests for lib/services/core_package_installer.dart.
//
// Each case builds a fake package directory in a temp dir and asserts the
// exact install step it targets, in the order the installer walks them:
//   manifest presence -> validation -> pin verification -> consent -> staging.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/core_package_installer.dart';
import 'package:ezcore/services/hash_verifier.dart';

/// Minimal but schema-valid core-package manifest. Every top-level key is in
/// `kKnownManifestFields` (so the validator accepts it). [pin] is the sha256
/// placed under the current platform key.
Map<String, dynamic> _manifest(String id, String pin) => <String, dynamic>{
  'id': id,
  'name': 'TestCore',
  'version': '1.0.0',
  'license': 'MIT',
  'license_url': 'https://example.invalid/LICENSE',
  'homepage': 'https://example.invalid',
  'upstream': 'example/TestCore',
  'systems': <String>['test'],
  'delivery': <String, String>{
    'linux': 'bundled',
    'macos': 'bundled',
    'windows': 'bundled',
  },
  'artifacts': <String, String>{PackageInstaller.platformKey: pin},
};

/// Writes a package directory `<base>/<id>` with [manifestJson], an optional
/// library file (named [libraryName]), and an optional `.info` file.
Future<Directory> _writePackage(
  Directory base,
  String id,
  Map<String, dynamic> manifestJson, {
  String? libraryName,
  List<int>? libraryBytes,
  String? infoText,
}) async {
  final dir = Directory('${base.path}/$id');
  await dir.create(recursive: true);
  await File(
    '${dir.path}/manifest.json',
  ).writeAsString(jsonEncode(manifestJson));
  if (libraryName != null) {
    await File(
      '${dir.path}/$libraryName',
    ).writeAsBytes(libraryBytes ?? List<int>.filled(32, 7));
  }
  if (infoText != null) {
    await Directory('${dir.path}/info').create(recursive: true);
    await File('${dir.path}/info/$id.info').writeAsString(infoText);
  }
  return dir;
}

/// Overwrites the current-platform artifact pin in the package's manifest with
/// the real sha256 of `<package>/<id>.<suffix>`, so a good-install round-trip
/// can use the real hash rather than a placeholder.
Future<String> _setRealPin(Directory pkg, String id, String suffix) async {
  final libPath = '${pkg.path}/$id.$suffix';
  final realPin = await const DartHashVerifier().sha256File(libPath);
  final manifestPath = '${pkg.path}/manifest.json';
  final manifest =
      jsonDecode(await File(manifestPath).readAsString())
          as Map<String, dynamic>;
  manifest['artifacts'] = <String, String>{
    PackageInstaller.platformKey: realPin,
  };
  await File(manifestPath).writeAsString(jsonEncode(manifest));
  return realPin;
}

void main() {
  late Directory base;
  late String suffix;
  late String platformKey;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('ezcore_installer');
    suffix = PackageInstaller.libraryExtension;
    platformKey = PackageInstaller.platformKey;
  });
  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  test('good install round-trip: verifies pin, stages library, emits '
      'Unverified warning', () async {
    final libBytes = List<int>.filled(64, 0x42);
    final pkg = await _writePackage(
      base,
      'testcore',
      _manifest('testcore', '0' * 64),
      libraryName: 'testcore.$suffix',
      libraryBytes: libBytes,
      infoText:
          'corename = "TestCore"\nsystemname = "Test"\n'
          'systemid = "test"\nsupported_extensions = "bin|rom"',
    );
    await _setRealPin(pkg, 'testcore', suffix);

    final vault = Directory('${base.path}/vault');
    final report = await PackageInstaller().install(
      pkg,
      userConsented: true,
      vaultOverride: vault,
    );

    expect(report.ok, isTrue);
    expect(report.coreId, 'testcore');
    expect(report.errors, isEmpty);
    expect(report.refusedCode, isNull);
    expect(
      report.warnings,
      contains(predicate((String w) => w.contains('Unverified'))),
    );

    final stagedPath = '${vault.path}/cores/testcore/testcore.$suffix';
    expect(report.stagedPath, stagedPath);
    expect(File(stagedPath).existsSync(), isTrue);
    // Staged bytes are a faithful copy of the source library.
    expect(await File(stagedPath).readAsBytes(), libBytes);
    // Sidecar written for fast re-verification (matches core_staging layout).
    expect(File('$stagedPath.ezpin').existsSync(), isTrue);
    // The staged manifest makes the vault self-describing: discovery can
    // register the core on later boots without the bundled catalog.
    expect(
      File('${vault.path}/cores/testcore/manifest.json').existsSync(),
      isTrue,
    );
  });

  test('pin mismatch: refused, nothing staged', () async {
    final libBytes = List<int>.filled(64, 0x42);
    // '0' * 64 is a valid-format pin, so validation passes; the real sha256 of
    // the file will differ, so pin comparison refuses.
    final pkg = await _writePackage(
      base,
      'testcore',
      _manifest('testcore', '0' * 64),
      libraryName: 'testcore.$suffix',
      libraryBytes: libBytes,
    );
    final vault = Directory('${base.path}/vault');
    final report = await PackageInstaller().install(
      pkg,
      userConsented: true,
      vaultOverride: vault,
    );

    expect(report.ok, isFalse);
    expect(report.refusedCode, 'pin_mismatch');
    expect(report.errors, isNotEmpty);
    expect(report.errors.first, contains('SHA-256 mismatch'));
    // Pin mismatch refuses before staging: vault untouched.
    expect(
      File('${vault.path}/cores/testcore/testcore.$suffix').existsSync(),
      isFalse,
    );
  });

  test(
    'no consent: valid pin refused at the consent gate, nothing staged',
    () async {
      final libBytes = List<int>.filled(64, 0x42);
      final pkg = await _writePackage(
        base,
        'testcore',
        _manifest('testcore', '0' * 64),
        libraryName: 'testcore.$suffix',
        libraryBytes: libBytes,
      );
      await _setRealPin(pkg, 'testcore', suffix);

      final vault = Directory('${base.path}/vault');
      final report = await PackageInstaller().install(
        pkg,
        userConsented: false,
        vaultOverride: vault,
      );

      expect(report.ok, isFalse);
      expect(report.refusedCode, 'consent_required');
      expect(report.errors.first, contains('consent'));
      expect(
        File('${vault.path}/cores/testcore/testcore.$suffix').existsSync(),
        isFalse,
      );
    },
  );

  test('invalid manifest: every validator error surfaced verbatim, '
      'nothing staged', () async {
    // Three independent policy violations; each must appear verbatim in the
    // report (not collapsed into a single string).
    final bad = _manifest('testcore', '0' * 64);
    bad['evil_field'] = true; // unknown top-level field
    (bad['delivery'] as Map<String, String>)['ios'] =
        'streaming'; // bad delivery
    (bad['artifacts'] as Map<String, String>)[platformKey] =
        'A' * 64; // not lowercase hex
    final pkg = await _writePackage(base, 'testcore', bad);
    final vault = Directory('${base.path}/vault');
    final report = await PackageInstaller().install(
      pkg,
      userConsented: true,
      vaultOverride: vault,
    );

    expect(report.ok, isFalse);
    expect(report.refusedCode, 'validation_failed');
    // Each validator error is surfaced verbatim (not collapsed): at least one
    // element of `errors` must carry each distinct violation.
    expect(report.errors, contains('unknown top-level field "evil_field"'));
    expect(
      report.errors,
      contains(predicate((String e) => e.contains('delivery for "ios"'))),
    );
    expect(
      report.errors,
      contains(predicate((String e) => e.contains('artifact pin for'))),
    );
    expect(report.errors.length, greaterThanOrEqualTo(3));
    expect(
      File('${vault.path}/cores/testcore/testcore.$suffix').existsSync(),
      isFalse,
    );
  });

  test('missing manifest.json: refused as missing_manifest', () async {
    final pkg = Directory('${base.path}/nomanifest');
    await pkg.create();
    final vault = Directory('${base.path}/vault');
    final report = await PackageInstaller().install(
      pkg,
      userConsented: true,
      vaultOverride: vault,
    );

    expect(report.ok, isFalse);
    expect(report.refusedCode, 'missing_manifest');
    expect(report.errors.first, contains('manifest.json'));
  });

  test(
    'missing platform library: refused as no_library, nothing staged',
    () async {
      // Valid manifest + valid-format pin, but no library file present.
      final pkg = await _writePackage(
        base,
        'testcore',
        _manifest('testcore', '0' * 64),
      );
      final vault = Directory('${base.path}/vault');
      final report = await PackageInstaller().install(
        pkg,
        userConsented: true,
        vaultOverride: vault,
      );

      expect(report.ok, isFalse);
      expect(report.refusedCode, 'no_library');
      expect(report.errors.first, contains('no platform library'));
    },
  );

  test(
    'no artifact pin for current platform: refused as no_artifact_pin',
    () async {
      final libBytes = List<int>.filled(64, 0x42);
      final m = _manifest('testcore', '0' * 64);
      // Replace the current-platform pin with a foreign platform's pin so the
      // current platform has no pin, while keeping validation green.
      (m['artifacts'] as Map<String, String>).clear();
      (m['artifacts'] as Map<String, String>)['macos-arm64'] = 'a' * 64;
      final pkg = await _writePackage(
        base,
        'testcore',
        m,
        libraryName: 'testcore.$suffix',
        libraryBytes: libBytes,
      );
      final vault = Directory('${base.path}/vault');
      final report = await PackageInstaller().install(
        pkg,
        userConsented: true,
        vaultOverride: vault,
      );

      expect(report.ok, isFalse);
      expect(report.refusedCode, 'no_artifact_pin');
      expect(report.errors.first, contains('no artifact pin'));
    },
  );

  test(
    'zip path: refused as zip_not_supported (no archive dependency)',
    () async {
      final zipDir = Directory('${base.path}/foo.zip');
      await zipDir.create();
      final vault = Directory('${base.path}/vault');
      final report = await PackageInstaller().install(
        zipDir,
        userConsented: true,
        vaultOverride: vault,
      );

      expect(report.ok, isFalse);
      expect(report.refusedCode, 'zip_not_supported');
      expect(report.errors.first, contains('not supported in v1'));
    },
  );

  test('vaultOverride is used as the vault root', () async {
    final libBytes = List<int>.filled(64, 0x99);
    final pkg = await _writePackage(
      base,
      'testcore',
      _manifest('testcore', '0' * 64),
      libraryName: 'testcore.$suffix',
      libraryBytes: libBytes,
    );
    await _setRealPin(pkg, 'testcore', suffix);

    final customVault = Directory('${base.path}/custom_vault');
    final report = await PackageInstaller().install(
      pkg,
      userConsented: true,
      vaultOverride: customVault,
    );

    expect(report.ok, isTrue);
    expect(
      report.stagedPath,
      '${customVault.path}/cores/testcore/testcore.$suffix',
    );
    expect(File(report.stagedPath!).existsSync(), isTrue);
  });

  test('installer never touches the network (code-review invariant)', () {
    // No-network proof by source inspection (no fake server). The installer
    // must import only dart:* + relative-local libraries and must not reference
    // any network API in its code. The file header carries the human-readable
    // "code review note"; these asserts back it mechanically.
    final src = File(
      'lib/services/core_package_installer.dart',
    ).readAsStringSync();
    final imports = src
        .split('\n')
        .map((l) => l.trimLeft())
        .where((l) => l.startsWith('import '))
        .toList();
    // No external network packages; only dart:* and relative-local imports.
    expect(
      imports.any((l) => l.startsWith("import 'package:")),
      isFalse,
      reason: 'no package: imports (no http/html/etc.)',
    );
    expect(
      imports.any((l) => l.contains('dart:html')),
      isFalse,
      reason: 'no dart:html import',
    );
    // Strip line comments so we test real code, not the prose note above.
    final codeOnly = src
        .split('\n')
        .map((l) {
          final idx = l.indexOf('//');
          return idx == -1 ? l : l.substring(0, idx);
        })
        .join('\n');
    expect(codeOnly.contains('HttpClient'), isFalse, reason: 'no HttpClient');
    expect(codeOnly.contains('WebSocket'), isFalse, reason: 'no WebSocket');
    // Sanity: local filesystem (dart:io) is the only IO surface.
    expect(imports.any((l) => l == "import 'dart:io';"), isTrue);
  });

  test(
    'a legal-hold manifest (blocked_reason) is refused before anything stages',
    () async {
      final pin = List.filled(64, 'a').join();
      final m = _manifest('citra_hold', pin)
        ..['blocked_reason'] =
            'Nintendo 3DS core — legal hold, never built or shipped';
      final pkg = await _writePackage(base, 'citra_hold', m);
      final vault = await Directory.systemTemp.createTemp(
        'ezcore_vault_blocked',
      );
      try {
        final report = await PackageInstaller().install(
          pkg,
          userConsented: true,
          vaultOverride: vault,
        );
        expect(report.ok, isFalse);
        expect(report.refusedCode, 'core_blocked');
        expect(report.errors.first, contains('legal hold'));
        // Nothing staged: the refusal fires before any vault write.
        expect(
          vault
              .listSync(recursive: true)
              .whereType<Directory>()
              .where((d) => d.path.contains('cores'))
              .isEmpty,
          isTrue,
        );
      } finally {
        await vault.delete(recursive: true);
      }
    },
  );

  test('a license-gated core installs with a responsibility warning', () async {
    final m = _manifest('gated_core', List.filled(64, 'b').join())
      ..['gated_reason'] =
          'upstream license terms — recipe only, never distributed';
    final pkg = await _writePackage(
      base,
      'gated_core',
      m,
      libraryName: 'gated_core.$suffix',
    );
    await _setRealPin(pkg, 'gated_core', suffix);
    final vault = await Directory.systemTemp.createTemp('ezcore_vault_gated');
    try {
      final report = await PackageInstaller().install(
        pkg,
        userConsented: true,
        vaultOverride: vault,
      );
      expect(report.ok, isTrue);
      expect(
        report.warnings.any(
          (w) => w.contains('responsible for holding the rights'),
        ),
        isTrue,
      );
    } finally {
      await vault.delete(recursive: true);
    }
  });
}

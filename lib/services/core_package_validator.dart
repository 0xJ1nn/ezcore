// SPDX-License-Identifier: MIT
//
// Package-level validation for libretro core packages.
//
// A "core package" is a directory (e.g. `cores/nesbyte`) containing a
// `manifest.json`. This validator checks the directory against the repo's
// manifest conventions — field shape, identifier rules, artifact pin format,
// delivery policy, package size caps, and symlink rejection.
//
// The set of allowed top-level manifest fields mirrors the reference shape of
// `cores/nesbyte/manifest.json`; any other top-level key is rejected (listed in
// [PackageValidationReport.errors]) rather than silently ignored.
//
// All checks are best-effort and never throw for policy failures: problems are
// collected on the returned [PackageValidationReport].

import 'dart:convert';
import 'dart:io';

/// Top-level fields permitted in a core package `manifest.json`.
///
/// Mirrors the reference shape of `cores/nesbyte/manifest.json`. Passed as the
/// default value for [PackageValidationReport.validate]'s [allowedFields]
/// parameter; callers may extend the set for vendor-specific keys.
const Set<String> kKnownManifestFields = <String>{
  'id',
  'name',
  'version',
  'license',
  'license_url',
  'homepage',
  'upstream',
  'systems',
  'extensions',
  'cheats_supported',
  'cheat_families',
  'bios_required',
  'bios_files',
  'delivery',
  'artifacts',
  'execution',
  'bios_notes',
  'provenance',
};

/// Result of validating a core package directory.
///
/// Obtain via [PackageValidationReport.validate]. Validation never throws for
/// policy failures; instead, problems are collected in [errors] and
/// [warnings]. [ok] is `true` only when [errors] is empty.
class PackageValidationReport {
  PackageValidationReport._(this.packagePath, this.allowedFields);

  /// Absolute path of the package directory that was validated.
  final String packagePath;

  /// The set of accepted top-level manifest field names.
  final Set<String> allowedFields;

  /// Hard policy failures (the package does not conform).
  final List<String> errors = <String>[];

  /// Soft concerns that do not by themselves fail the package.
  final List<String> warnings = <String>[];

  /// `true` when [errors] is empty.
  bool get ok => errors.isEmpty;

  /// Default cap on the total byte size of all files in a package.
  static const int defaultMaxPackageBytes = 512 * 1024 * 1024; // 512 MiB

  /// Default cap on the size of `manifest.json` alone.
  static const int defaultMaxManifestBytes = 1 * 1024 * 1024; // 1 MiB

  @override
  String toString() => 'PackageValidationReport(ok=$ok, '
      'errors=${errors.length}, warnings=${warnings.length})';

  /// Validates the core package at [package].
  ///
  /// Parameters:
  /// - [allowedFields]: accepted top-level manifest keys; defaults to
  ///   [kKnownManifestFields].
  /// - [maxPackageBytes]: total byte cap for the package tree; defaults to
  ///   [defaultMaxPackageBytes].
  /// - [maxManifestBytes]: byte cap for `manifest.json`; defaults to
  ///   [defaultMaxManifestBytes].
  static Future<PackageValidationReport> validate(
    Directory package, {
    Set<String>? allowedFields,
    int? maxPackageBytes,
    int? maxManifestBytes,
  }) async {
    final report = PackageValidationReport._(
      package.path,
      allowedFields ?? kKnownManifestFields,
    );
    final cap = maxPackageBytes ?? defaultMaxPackageBytes;
    final manifestCap = maxManifestBytes ?? defaultMaxManifestBytes;

    if (!await package.exists()) {
      report.errors.add('package directory does not exist: ${package.path}');
      return report;
    }

    final manifest = File('${package.path}/manifest.json');
    if (!await manifest.exists()) {
      report.errors.add('manifest.json is missing in ${package.path}');
      await _scanPackage(package, report, cap);
      return report;
    }

    List<int> bytes;
    try {
      bytes = await manifest.readAsBytes();
    } catch (e) {
      report.errors.add('manifest.json could not be read: $e');
      await _scanPackage(package, report, cap);
      return report;
    }
    if (bytes.length > manifestCap) {
      report.errors.add(
        'manifest.json exceeds size cap of $manifestCap bytes '
        '(was ${bytes.length})',
      );
    }

    final text = utf8.decode(bytes);
    dynamic json;
    try {
      json = jsonDecode(text);
    } catch (e) {
      report.errors.add('manifest.json is not valid JSON: $e');
      await _scanPackage(package, report, cap);
      return report;
    }
    if (json is! Map) {
      report.errors.add(
        'manifest.json root must be a JSON object, got ${json.runtimeType}',
      );
      await _scanPackage(package, report, cap);
      return report;
    }

    _validateManifest(json as Map<String, dynamic>, report, package);
    await _scanPackage(package, report, cap);
    return report;
  }

  static final RegExp _idRegex = RegExp(r'^[a-z0-9_]+$');
  static final RegExp _pinRegex = RegExp(r'^[0-9a-f]{64}$');
  static const Set<String> _allowedDelivery = <String>{
    'bundled',
    'on-demand',
    'absent',
  };

  static void _validateManifest(
    Map<String, dynamic> manifest,
    PackageValidationReport report,
    Directory package,
  ) {
    // Unknown top-level fields.
    for (final key in manifest.keys) {
      if (!report.allowedFields.contains(key)) {
        report.errors.add('unknown top-level field "$key"');
      }
    }

    // id: present, well-formed, and matching the package directory name.
    final id = manifest['id'];
    if (id == null || id is! String || id.isEmpty) {
      report.errors.add('missing or non-string "id"');
    } else {
      if (!_idRegex.hasMatch(id)) {
        report.errors.add('id "$id" must match [a-z0-9_]+');
      }
      final parts = package.path.split(Platform.pathSeparator);
      final dirName = parts.lastWhere((p) => p.isNotEmpty, orElse: () => package.path);
      if (id != dirName) {
        report.errors.add('id "$id" does not match directory name "$dirName"');
      }
    }

    // artifacts: every pin must be a 64-char lowercase hex string.
    final artifacts = manifest['artifacts'];
    if (artifacts != null) {
      if (artifacts is! Map) {
        report.errors.add('"artifacts" must be an object');
      } else {
        for (final e in artifacts.entries) {
          final pin = e.value;
          if (pin is! String || !_pinRegex.hasMatch(pin)) {
            report.errors.add(
              'artifact pin for "${e.key}" is not a 64-char lowercase hex '
              'string: $pin',
            );
          }
        }
      }
    }

    // delivery: values must be bundled | on-demand | absent.
    final delivery = manifest['delivery'];
    if (delivery != null) {
      if (delivery is! Map) {
        report.errors.add('"delivery" must be an object');
      } else {
        for (final e in delivery.entries) {
          final value = e.value;
          if (value is! String || !_allowedDelivery.contains(value)) {
            report.errors.add(
              'delivery for "${e.key}" must be one of '
              'bundled|on-demand|absent, got: $value',
            );
          }
        }
      }
    }

    // Soft policy: bios_required without bios_files.
    final biosRequired = manifest['bios_required'] == true;
    final biosFiles = manifest['bios_files'];
    if (biosRequired &&
        (biosFiles == null || biosFiles is! List || biosFiles.isEmpty)) {
      report.warnings.add('bios_required is true but no bios_files are declared');
    }
  }

  /// Recursively walks the package, rejecting symlinks and accumulating total
  /// file size against [maxPackageBytes].
  static Future<void> _scanPackage(
    Directory package,
    PackageValidationReport report,
    int maxPackageBytes,
  ) async {
    int totalBytes = 0;
    var oversize = false;
    try {
      await for (final entity in package.list(recursive: true, followLinks: false)) {
        if (entity is Link) {
          report.errors.add('symlink found in package: ${entity.path}');
          continue;
        }
        if (entity is File) {
          int size = 0;
          try {
            size = await entity.length();
          } catch (e) {
            report.warnings.add('cannot read size of ${entity.path}: $e');
          }
          totalBytes += size;
          if (totalBytes > maxPackageBytes && !oversize) {
            oversize = true;
            report.errors.add(
              'package exceeds size cap of $maxPackageBytes bytes '
              '(running total $totalBytes at ${entity.path})',
            );
          }
        }
      }
    } catch (e) {
      report.errors.add('failed to scan package: $e');
    }
  }
}

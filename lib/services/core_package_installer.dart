// SPDX-License-Identifier: MIT
//
// Installs a validated libretro core package into the local vault.
//
// P2 install entry point for the ezCORE core-package platform. Given a
// package directory on disk, this runs the manifest contract end to end:
//
//   manifest presence -> structural validation -> platform-artifact pin
//   verification -> explicit user consent -> vault staging.
//
// Platform invariants (see EZCORE-PACKAGE-PLATFORM-MASTER-PROMPT.md §3-4):
//  * Package data never executes code and never fetches from the network.
//  * Untrusted native code is opt-in: staging a native library requires
//    explicit user consent ([PackageInstaller.install] userConsented == true).
//  * Staged bytes are sha256-verified against the manifest pin before they
//    leave the package; a pin mismatch is refused and stages nothing.
//  * Native code is never silently updated — an "Unverified" trust label
//    is always surfaced because v1 carries no package signatures (the
//    signature slot lands in P7).
//
// No-network proof: this file imports only `dart:io`, `dart:ffi`, and
// `dart:convert` — there is no `package:http`, no `dart:html`, no
// `HttpClient`/socket/WebSocket surface. All work is local filesystem I/O.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../models/core_manifest.dart';
import 'core_package_validator.dart';
import 'hash_verifier.dart';
import 'local_data_dir.dart';
import 'retro_info_parser.dart';

/// Outcome of [PackageInstaller.install].
///
/// [ok] is true exactly when the core was staged into the vault. On failure,
/// [errors] carries a human-readable detail (the validator's own error list,
/// verbatim, for `validation_failed`) and [refusedCode] is a stable,
/// machine-readable reason. [warnings] is always populated — e.g. the
/// "Unverified" trust label — and never blocks an otherwise-valid install.
class PackageInstallReport {
  PackageInstallReport({
    required this.ok,
    this.coreId,
    this.stagedPath,
    List<String>? warnings,
    List<String>? errors,
    this.refusedCode,
  }) : warnings = List<String>.unmodifiable(warnings ?? <String>[]),
       errors = List<String>.unmodifiable(errors ?? <String>[]);

  /// True when the library was staged and verified into the vault.
  final bool ok;

  /// The manifest `id` of the staged core (null on refusal).
  final String? coreId;

  /// Absolute path where the library was staged (null on refusal).
  final String? stagedPath;

  /// Non-fatal, informational concerns (e.g. the Unverified trust label).
  final List<String> warnings;

  /// Hard failures. Empty when [ok] is true. For `validation_failed` these
  /// are the validator's errors, verbatim.
  final List<String> errors;

  /// Stable reason code when the install was refused (null on success).
  ///
  /// Values: `missing_manifest`, `validation_failed`, `no_artifact_pin`,
  /// `no_library`, `pin_mismatch`, `consent_required`, `zip_not_supported`.
  final String? refusedCode;

  @override
  String toString() =>
      'PackageInstallReport(ok=$ok, coreId=$coreId, stagedPath=$stagedPath, '
      'errors=${errors.length}, warnings=${warnings.length}, '
      'refusedCode=$refusedCode)';
}

/// Installs libretro core packages into the local vault.
///
/// See [PackageInstallReport] for outcome semantics and the file header for
/// the platform invariants this class enforces. Instances are stateless
/// aside from the injected [HashVerifier], so a single instance may be reused
/// across installs.
class PackageInstaller {
  PackageInstaller({HashVerifier? hashes})
    : _hashes = hashes ?? const DartHashVerifier();

  final HashVerifier _hashes;

  /// The current platform-arch key, e.g. `linux-x64`, `macos-arm64`.
  ///
  /// Mirrors `CoreDiscovery.platformKey`: `Abi.current()` renders as
  /// `linux_x64` / `macos_arm64` / `windows_x64` / `android_arm64` /
  /// `ios_arm64` (underscore) — replacing `_` with `-` yields the kebab-case
  /// key shape used by manifest `artifacts` pins.
  static String get platformKey =>
      Abi.current().toString().replaceAll('_', '-');

  /// Native library extension for the running platform: `so`, `dylib`, `dll`.
  ///
  /// Mirrors the suffix derivation in `core_discovery.dart` /
  /// `core_staging.dart` / `core_path_resolver.dart`.
  static String get libraryExtension => Platform.isWindows
      ? 'dll'
      : (Platform.isMacOS || Platform.isIOS)
      ? 'dylib'
      : 'so';

  /// Installs the core package at [package] into the vault.
  ///
  /// Steps (in strict order):
  ///  1. A `.zip` path is refused (`zip_not_supported`); otherwise
  ///     `manifest.json` must exist (`missing_manifest`).
  ///  2. [PackageValidationReport.validate] the package; on failure the
  ///     validator's errors are returned verbatim and nothing is staged
  ///     (`validation_failed`).
  ///  3. Locate the platform library (`<$id>_libretro.<ext>` then
  ///     `<$id>.<ext>`, in the package root or an `<$id>/` subdir), sha256 it,
  ///     and compare to the manifest pin for the current platform. A missing
  ///     library is `no_library`; a missing pin is `no_artifact_pin`; a hash
  ///     mismatch is `pin_mismatch`. In every case nothing is staged.
  ///  4. Consent gate: [userConsented] must be true, else `consent_required`.
  ///     Native code is opt-in — an invariant of the platform.
  ///  5. Stage the verified library at `<vaultRoot>/cores/<id>/<id>.<ext>`
  ///     and re-verify the pinned bytes in place (never vault unverified
  ///     bytes; a `.ezpin` sidecar is written for fast re-verification).
  ///  6. Return a [PackageInstallReport] (`ok` on success; the "Unverified"
  ///     trust label is a warning, not an error).
  ///
  /// [vaultOverride] redirects the local-data-dir root for tests; when
  /// absent the app's local data directory is resolved via
  /// [PlatformLocalDataDirProvider].
  ///
  /// Never performs network I/O, never executes package contents, and never
  /// touches save data.
  Future<PackageInstallReport> install(
    Directory package, {
    required bool userConsented,
    Directory? vaultOverride,
  }) async {
    // (1) ZIP packages are not supported in v1: the `archive` package is not a
    // dependency, and P2 ships directory-only. A .zip path is refused up front
    // with a clear, actionable message rather than a half-implemented decode.
    if (package.path.toLowerCase().endsWith('.zip')) {
      return PackageInstallReport(
        ok: false,
        refusedCode: 'zip_not_supported',
        errors: [
          'zip packages are not supported in v1; provide a directory instead '
              'of ${package.path}.',
        ],
      );
    }

    final manifestFile = File('${package.path}/manifest.json');
    // (1 cont.) The package must contain manifest.json — the single source of
    // truth. Checked before the full validator so the failure mode is crisp.
    if (!await manifestFile.exists()) {
      return PackageInstallReport(
        ok: false,
        refusedCode: 'missing_manifest',
        errors: [
          'package must contain manifest.json (not found in ${package.path}).',
        ],
      );
    }

    // (2) Full structural + policy validation. Failures surface verbatim and
    // stage nothing.
    final validation = await PackageValidationReport.validate(package);
    if (!validation.ok) {
      return PackageInstallReport(
        ok: false,
        refusedCode: 'validation_failed',
        errors: List<String>.of(validation.errors),
        warnings: validation.warnings,
      );
    }

    // Parse the (already schema-validated) manifest once for our needs.
    final manifestText = await manifestFile.readAsString();
    final Map<String, dynamic> rawManifest;
    try {
      rawManifest = jsonDecode(manifestText) as Map<String, dynamic>;
    } catch (e) {
      // Unreachable in practice: the validator already JSON-parsed it, but be
      // defensive against a TOCTOU gap.
      return PackageInstallReport(
        ok: false,
        refusedCode: 'validation_failed',
        errors: ['manifest.json is not valid JSON: $e'],
      );
    }
    final manifest = CoreManifest.fromJson(rawManifest);
    final id = manifest.id;
    final warnings = <String>[];

    // (2b) Policy gates. Two distinct refusal classes:
    //
    // - `blocked_reason` marks legal holds (Switch / 3DS / PS2 policy):
    //   never installable through any path. Hard refusal.
    // - `gated_reason` marks license-gated cores (recipe only, never
    //   distributed BY THE PROJECT). A package with a gated_reason manifest
    //   is the user's own locally-built content — installing it is allowed
    //   under the self-serve door (ADR-016), with an explicit warning that
    //   the user is responsible for holding the rights to this build. The
    //   project itself still never ships those binaries.
    final blockedReason = rawManifest['blocked_reason'];
    if (blockedReason is String && blockedReason.isNotEmpty) {
      return PackageInstallReport(
        ok: false,
        refusedCode: 'core_blocked',
        errors: [
          "core '$id' is a legal hold and cannot be installed: $blockedReason",
        ],
      );
    }
    final gatedReason = rawManifest['gated_reason'];
    if (gatedReason is String && gatedReason.isNotEmpty) {
      warnings.add(
        "License-gated core '$id': the project distributes the build recipe "
        'only, never binaries — you are responsible for holding the rights '
        'to this build.',
      );
    }

    // Install-contract step 1 (best-effort, non-blocking): parse shipped
    // `.info` metadata via RetroInfo. Lenient by design — only the parser's
    // own warnings surface, never a hard failure.
    warnings.addAll(_parseInfoWarnings(package, id));

    // (3a) The "Unverified" trust label. v1 ships no package signatures (the
    // `signature` slot lands in P7), and `signature` is not in
    // kKnownManifestFields, so a schema-valid manifest has none. Anything
    // staged here is, by definition, Unverified — native code is opt-in and
    // never auto-updated.
    final signature = rawManifest['signature'];
    if (signature == null || signature == 'dev-unsigned') {
      warnings.add(
        "Unverified: core '$id' has no trusted signature — native code is "
        'opt-in, never auto-updated, and runs only with your consent.',
      );
    }

    // (3b) Verify the platform artifact's pin before staging a single byte.
    final pin = manifest.artifacts[platformKey];
    if (pin == null) {
      return PackageInstallReport(
        ok: false,
        refusedCode: 'no_artifact_pin',
        warnings: warnings,
        errors: [
          "manifest for '$id' has no artifact pin for the current platform "
              '($platformKey); cannot verify before staging.',
        ],
      );
    }

    final library = _findLibrary(package, id);
    if (library == null) {
      return PackageInstallReport(
        ok: false,
        refusedCode: 'no_library',
        warnings: warnings,
        errors: [
          "no platform library found for '$id' in ${package.path} "
              '(expected ${id}_libretro.$libraryExtension or '
              '$id.$libraryExtension in the package root or $id/ subdir).',
        ],
      );
    }

    final expected = pin.toLowerCase();
    final actual = (await _hashes.sha256File(library.path)).toLowerCase();
    if (actual != expected) {
      return PackageInstallReport(
        ok: false,
        refusedCode: 'pin_mismatch',
        warnings: warnings,
        errors: [
          'SHA-256 mismatch for $id on $platformKey: expected $expected, '
              'got $actual.',
        ],
      );
    }

    // (4) Consent gate — native code is opt-in. Checked after pin verification
    // so a wrong pin is never staged even with consent, and before any vault
    // write so refusing consent stages nothing.
    if (userConsented != true) {
      return PackageInstallReport(
        ok: false,
        refusedCode: 'consent_required',
        warnings: warnings,
        errors: [
          'native code staging for $id requires explicit user consent '
              '(userConsented was not true).',
        ],
      );
    }

    // (5) Stage: copy the verified library into the vault, then re-verify the
    // staged bytes in place. The vault layout mirrors core_staging.dart:
    //   <localDataDir>/cores/<id>/<id>.<ext>
    // A `.ezpin` sidecar is written by verifyPinnedFile for fast re-verification
    // on subsequent boots.
    final vaultRoot =
        vaultOverride ?? Directory(PlatformLocalDataDirProvider.path());
    final stagedPath = '${vaultRoot.path}/cores/$id/$id.$libraryExtension';
    final staged = File(stagedPath);
    await staged.create(recursive: true);
    await library.copy(stagedPath);

    // Re-verify the staged bytes. A failed/interrupted copy must never leave
    // unverified bytes in the vault — roll back and refuse.
    if (!await verifyPinnedFile(stagedPath, pin, hashes: _hashes)) {
      await _safeDelete(staged);
      return PackageInstallReport(
        ok: false,
        refusedCode: 'pin_mismatch',
        warnings: warnings,
        errors: [
          'staged artifact for $id failed in-place pin verification; rolled '
              'back.',
        ],
      );
    }

    // (6) Stage the manifest (and shipped .info) alongside the library: the
    // vault directory becomes self-describing, so discovery can register
    // the core on later boots without the bundled catalog knowing it. These
    // are data files — validated before this point, never executed.
    await manifestFile.copy('${vaultRoot.path}/cores/$id/manifest.json');
    final infoFile = File('${package.path}/info/$id.info');
    if (await infoFile.exists()) {
      final infoDir = Directory('${vaultRoot.path}/cores/$id/info');
      await infoDir.create(recursive: true);
      await infoFile.copy('${infoDir.path}/$id.info');
    }

    // (7) Success. The "Unverified" label remains a warning on the report so
    // the caller (UI) can render the trust state plainly.
    return PackageInstallReport(
      ok: true,
      coreId: id,
      stagedPath: stagedPath,
      warnings: warnings,
    );
  }

  /// Locates the platform library inside [package] for core [id].
  ///
  /// Naming follows the libretro + ezcore convention, checked in this order
  /// (first hit wins): `<id>_libretro.<ext>` then `<id>.<ext>`, each looked
  /// for in a `<id>/` subdir first, then flat in the package root — matching
  /// `core_staging.dart` `_findSource` and `core_discovery.dart` `verifiedPath`.
  File? _findLibrary(Directory package, String id) {
    final suffix = '.$libraryExtension';
    for (final name in ['${id}_libretro$suffix', '$id$suffix']) {
      final subdir = File('${package.path}/$id/$name');
      if (subdir.existsSync()) return subdir;
      final flat = File('${package.path}/$name');
      if (flat.existsSync()) return flat;
    }
    return null;
  }

  /// Best-effort parse of `info/<id>.info`; returns the parser's own warnings
  /// (empty for well-formed metadata). Never throws — the [RetroInfo] parser
  /// is lenient by design.
  static List<String> _parseInfoWarnings(Directory package, String id) {
    final info = File('${package.path}/info/$id.info');
    if (!info.existsSync()) return <String>[];
    try {
      final parsed = RetroInfo.parse(info.readAsStringSync());
      return parsed.warnings.toList();
    } catch (_) {
      return <String>['could not parse ${package.path}/info/$id.info'];
    }
  }

  /// Removes a staged artifact together with its `.ezpin` sidecar so the two
  /// never outlive each other (mirrors `core_staging.dart` `_removeDest`).
  static Future<void> _safeDelete(File file) async {
    try {
      await file.delete();
    } catch (_) {}
    try {
      await File('${file.path}.ezpin').delete();
    } catch (_) {}
  }
}

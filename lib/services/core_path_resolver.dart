import 'dart:io';

import '../models/core_manifest.dart';
import 'hash_verifier.dart';
import 'local_data_dir.dart';

/// Resolved artifact path for a core on the current platform.
class CorePath {
  const CorePath({
    required this.path,
    required this.sha256,
    required this.platformKey,
  });

  /// Absolute path to the core artifact.
  final String path;

  /// Expected SHA-256 hash from the manifest.
  final String sha256;

  /// Platform-arch key (e.g. `macos-arm64`) resolved from the manifest.
  final String platformKey;
}

/// Resolves core artifacts on disk and verifies their SHA-256 pins.
///
/// The current platform-arch key is derived from `Platform.operatingSystem`
/// and the host `Platform.version` / `abi`. The artifact lives under
/// `<localDataDir>/cores/<id>/<id>.so|dylib|dll`. Before launch, the file
/// is hashed and compared to the pin in the manifest; mismatches throw.
class CorePathResolver {
  CorePathResolver(this._dirProvider, this._hashVerifier);
  final LocalDataDirProvider _dirProvider;
  final HashVerifier _hashVerifier;

  /// Resolves the platform-arch key for the running host.
  ///
  /// macOS on ARM returns `macos-arm64`, macOS on x64 returns `macos-x64`,
  /// Linux on x64 returns `linux-x64`, Windows on x64 returns `windows-x64`,
  /// Android on ARM64 returns `android-arm64`, iOS on ARM64 returns `ios-arm64`.
  static String currentPlatformKey() {
    final os = Platform.operatingSystem;
    String arch = 'unknown';
    if (Platform.isMacOS) {
      // ARM detection: Process.run 'uname -m' is the canonical check.
      try {
        final r = Process.runSync('uname', ['-m']);
        if (r.exitCode == 0) {
          final out = r.stdout.toString().trim();
          arch = out == 'arm64' ? 'arm64' : 'x64';
        }
      } catch (_) {
        arch = 'arm64'; // assume ARM on modern Apple Silicon
      }
    } else if (Platform.isLinux || Platform.isWindows) {
      arch = 'x64';
    } else if (Platform.isAndroid) {
      arch = 'arm64';
    } else if (Platform.isIOS) {
      arch = 'arm64';
    }
    return '$os-$arch';
  }

  /// Resolves a core's artifact path from the manifest.
  ///
  /// Returns null when the manifest declares no artifact for the current
  /// platform, or when the declared platform key does not match the
  /// running host. Never returns a path to a non-existent file.
  Future<CorePath?> resolve(CoreManifest manifest) async {
    final key = currentPlatformKey();
    final sha = manifest.artifacts[key];
    if (sha == null) return null;
    final dir = await _dirProvider.localDataDir();
    final ext = Platform.isWindows
        ? 'dll'
        : Platform.isMacOS || Platform.isIOS
            ? 'dylib'
            : 'so';
    final file = File('${dir.path}/cores/${manifest.id}/${manifest.id}.$ext');
    if (!file.existsSync()) return null;
    return CorePath(path: file.path, sha256: sha, platformKey: key);
  }

  /// Verifies the SHA-256 pin of a resolved artifact against its manifest.
  ///
  /// Throws [StateError] on hash mismatch, missing file, or missing pin.
  /// Returns the canonical (lowercase) hash on success.
  Future<String> verifyPin(CoreManifest manifest) async {
    if (manifest.blocked) {
      throw StateError(
        '${manifest.name} is on hold: ${manifest.blockedReason}',
      );
    }
    final resolved = await resolve(manifest);
    if (resolved == null) {
      throw StateError(
        'No artifact resolved for ${manifest.id} on ${currentPlatformKey()}',
      );
    }
    final file = File(resolved.path);
    if (!file.existsSync()) {
      throw StateError('Core artifact missing: ${resolved.path}');
    }
    final actual = (await _hashVerifier.sha256File(resolved.path)).toLowerCase();
    final expected = resolved.sha256.toLowerCase();
    if (actual != expected) {
      throw StateError(
        'SHA-256 mismatch for ${manifest.id}: expected $expected, got $actual',
      );
    }
    return actual;
  }
}

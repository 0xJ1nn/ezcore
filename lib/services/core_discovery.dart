import 'dart:ffi';
import 'dart:io';
import '../cores/core_registry.dart';
import '../models/core_manifest.dart';
import 'hash_verifier.dart';

/// Local artifacts only. No download, license bypass, or executable probing.
/// A verified artifact is installed, not necessarily playable by this frontend.
class CoreDiscovery {
  CoreDiscovery(this.root, {HashVerifier? hashes})
    : _hashes = hashes ?? const PlatformHashVerifier();
  final Directory root;
  final HashVerifier _hashes;
  final Map<String, String> errors = {};
  static String get platformKey =>
      Abi.current().toString().replaceAll('_', '-');

  Future<String?> verifiedPath(CoreManifest manifest) async {
    if (manifest.blocked) throw StateError('Core is on legal hold');
    final pin = manifest.artifacts[platformKey];
    if (pin == null) return null;
    final suffix = Platform.isMacOS
        ? '.dylib'
        : Platform.isWindows
        ? '.dll'
        : '.so';
    final dir = Directory('${root.path}/${manifest.id}');
    if (!await dir.exists()) return null;
    final candidates = await dir
        .list(followLinks: false)
        .where(
          (f) =>
              f is File &&
              (f.path.endsWith('_libretro$suffix') ||
                  f.uri.pathSegments.last == '${manifest.id}$suffix'),
        )
        .toList();
    if (candidates.length != 1) return null;
    final path = candidates.single.absolute.path;
    // Sidecar-gated: unchanged files skip re-hashing (mobile startup would
    // otherwise re-hash tens of MB per boot); any change re-verifies fully.
    final ok = await verifyPinnedFile(path, pin, hashes: _hashes);
    if (!ok) {
      throw StateError('SHA-256 mismatch for ${manifest.id}');
    }
    return path;
  }

  Future<Map<String, String>> discover(CoreRegistry registry) async {
    errors.clear();
    final paths = <String, String>{};
    for (final manifest in registry.catalog.where((m) => !m.blocked)) {
      try {
        final path = await verifiedPath(manifest);
        if (path != null) {
          registry.install(
            manifest,
            expectedSha256: manifest.artifacts[platformKey]!,
          );
          paths[manifest.id] = path;
        }
      } catch (error) {
        errors[manifest.id] = error.toString();
      }
    }
    return paths;
  }
}

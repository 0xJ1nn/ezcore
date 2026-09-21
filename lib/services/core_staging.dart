import 'dart:convert';
import 'dart:io';

import '../models/core_manifest.dart';
import 'core_path_resolver.dart';
import 'hash_verifier.dart';
import 'local_data_dir.dart';
import 'native_dirs.dart';
import 'repo_layout.dart';

/// Stages verified core artifacts into the local vault.
///
/// Sources (first hit wins per core): platform-bundled dirs (Android
/// jniLibs extraction dir / iOS bundle copy / desktop release bundle),
/// then the dev-checkout `native/cores` tree. Destination is always
/// `<localData>/cores/<id>/<id>.<ext>` — the single tree [CoreDiscovery]
/// and the player resolve from. Every staged byte is sha256-checked
/// against the manifest pin; mismatches are deleted and recorded, never
/// installed.
class CoreStagingService {
  CoreStagingService({
    LocalDataDirProvider? dirs,
    HashVerifier? hashes,
    NativeDirs? native,
  }) : _dirs = dirs ?? PlatformLocalDataDirProvider(),
       _hashes = hashes ?? const PlatformHashVerifier(),
       _native = native ?? createNativeDirs();

  final LocalDataDirProvider _dirs;
  final HashVerifier _hashes;
  final NativeDirs _native;

  final Map<String, String> errors = {};

  /// Vault destination for staged cores.
  static Directory vaultDir() =>
      Directory('${PlatformLocalDataDirProvider.path()}/cores');

  /// Copies + verifies every shippable core for this platform.
  /// Returns the staged core ids. Up-to-date files are skipped by hash.
  Future<List<String>> ensureStaged({
    required List<CoreManifest> catalog,
  }) async {
    errors.clear();
    final staged = <String>[];
    final sources = await _sources();
    if (sources.isEmpty) return staged;
    final key = CorePathResolver.currentPlatformKey();
    final osKey = key.split('-').first;
    final ext = Platform.isWindows
        ? 'dll'
        : (Platform.isMacOS || Platform.isIOS)
        ? 'dylib'
        : 'so';
    for (final manifest in catalog) {
      if (manifest.blocked) continue;
      // Cores this OS must not carry (delivery: 'absent' — legal holds and
      // pending-review cores) never stage. Without this, a dev checkout
      // sitting next to the app makes staging log noise for cores that
      // cannot ship here anyway.
      if (manifest.delivery[osKey] == 'absent') continue;
      final pin = manifest.artifacts[key];
      if (pin == null) continue;
      try {
        if (await _stageOne(manifest, pin, ext, sources)) {
          staged.add(manifest.id);
        }
      } catch (e) {
        errors[manifest.id] = e.toString();
        // Visible in Console.app / terminal launches; staging failures are
        // otherwise silent (the vault just stays empty).
        stderr.writeln('ezcore: staging failed for ${manifest.id}: $e');
      }
    }
    return staged;
  }

  Future<List<Directory>> _sources() async {
    final out = <Directory>[];
    try {
      final bundled = await _native.bundledCoresDir();
      if (bundled != null) {
        final dir = Directory(bundled);
        if (dir.existsSync()) out.add(dir);
      }
    } catch (_) {}
    // Platform-aware dev-checkout root first (cores-linux-x64 on Linux),
    // then the legacy host default — a populated platform tree must win
    // over an empty native/cores.
    final staged = RepoLayout.stagedCoresRoot(
      executablePath: Platform.resolvedExecutable,
    );
    if (staged != null) {
      out.add(Directory(staged));
    } else {
      final dev =
          RepoLayout.coresRoot(executablePath: Platform.resolvedExecutable) ??
              RepoLayout.coresRoot();
      if (dev != null) out.add(Directory(dev));
    }
    return out;
  }

  Future<bool> _stageOne(
    CoreManifest manifest,
    String pin,
    String ext,
    List<Directory> sources,
  ) async {
    final dest = File(
      '${(await _dirs.localDataDir()).path}/cores/${manifest.id}/${manifest.id}.$ext',
    );
    final candidate = _findSource(manifest, ext, sources);
    final record = _readSidecar(dest.path);
    if (dest.existsSync() && record != null) {
      final want = pin.toLowerCase();
      final dst = dest.statSync();
      final destOk = record['pin'] == want &&
          record['size'] == dst.size &&
          record['mtimeMs'] == dst.modified.millisecondsSinceEpoch;
      var sourceChanged = candidate == null;
      if (candidate != null) {
        final src = candidate.statSync();
        sourceChanged = record['srcSize'] != src.size ||
            record['srcMtimeMs'] != src.modified.millisecondsSinceEpoch;
      }
      // Steady state: verified bytes, unchanged source — no hashing.
      // (Size+mtime equality, never wall-clock recency, so coarse
      // filesystem granularity can't cause false hits.)
      if (destOk && !sourceChanged) return true;
      await _removeDest(dest);
    } else if (dest.existsSync()) {
      await _removeDest(dest);
    }
    if (candidate == null) return false;
    await dest.parent.create(recursive: true);
    await candidate.copy(dest.path);
    if (!await verifyPinnedFile(dest.path, pin, hashes: _hashes)) {
      await _removeDest(dest);
      throw StateError('Staged artifact failed pin check for ${manifest.id}');
    }
    _writeSidecar(dest.path, pin.toLowerCase(), candidate);
    return true;
  }

  /// Removes a staged artifact with its sidecar (never orphan one: a
  /// surviving sidecar could validate replacement bytes on a coarse-
  /// granularity filesystem).
  Future<void> _removeDest(File dest) async {
    try {
      await dest.delete();
    } catch (_) {}
    try {
      await File('${dest.path}.ezpin').delete();
    } catch (_) {}
  }

  Map<String, dynamic>? _readSidecar(String destPath) {
    try {
      final file = File('$destPath.ezpin');
      if (!file.existsSync()) return null;
      return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void _writeSidecar(String destPath, String pin, File source) {
    try {
      final dst = File(destPath).statSync();
      final src = source.statSync();
      File('$destPath.ezpin').writeAsStringSync(json.encode({
        'pin': pin,
        'size': dst.size,
        'mtimeMs': dst.modified.millisecondsSinceEpoch,
        'srcSize': src.size,
        'srcMtimeMs': src.modified.millisecondsSinceEpoch,
      }));
    } catch (_) {
      // Sidecar is a pure optimization; verification already succeeded.
    }
  }

  File? _findSource(
    CoreManifest manifest,
    String ext,
    List<Directory> sources,
  ) {
    for (final source in sources) {
      // Subdir layout (dev checkout, desktop bundles, iOS ezcore-cores/)
      // first, then the flat jniLibs layout (Android nativeLibraryDir).
      for (final name in [
        '${manifest.id}_libretro.$ext',
        '${manifest.id}.$ext',
      ]) {
        final sub = File('${source.path}/${manifest.id}/$name');
        if (sub.existsSync()) return sub;
        final flat = File('${source.path}/$name');
        if (flat.existsSync()) return flat;
      }
    }
    return null;
  }
}

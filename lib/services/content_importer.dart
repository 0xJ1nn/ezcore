import 'dart:io';

import '../models/core_manifest.dart';
import '../models/game_entry.dart';
import 'hash_verifier.dart';
import 'rom_validator.dart';

/// Result of a single file import attempt.
class ImportResult {
  const ImportResult({
    required this.filePath,
    this.game,
    this.skippedReason,
    this.error,
  });

  final String filePath;

  /// Set when the file was successfully imported.
  final GameEntry? game;

  /// Set when the file was skipped (wrong extension, duplicate, etc).
  final String? skippedReason;

  /// Set when the file failed validation.
  final String? error;

  bool get isSuccess => game != null;
  bool get isSkipped => skippedReason != null;
  bool get isError => error != null;
}

/// Outcome of scanning a directory for import candidates.
class ImportScan {
  const ImportScan({
    required this.results,
    this.manifestError,
  });

  final List<ImportResult> results;

  /// Set when the manifest catalog could not be loaded.
  final String? manifestError;

  bool get hasError => manifestError != null;
  int get importedCount => results.where((r) => r.isSuccess).length;
  int get skippedCount => results.where((r) => r.isSkipped).length;
  int get errorCount => results.where((r) => r.isError).length;
}

/// Imports user-owned game files into the library.
///
/// The importer:
/// 1. Validates the file exists and is readable.
/// 2. Matches its extension against the core manifest catalog.
/// 3. Rejects files whose system is on hold (blocked cores).
/// 4. Hashes the file (SHA-256) for deduplication + integrity.
/// 5. Rejects duplicates (same hash already in library).
/// 6. Never rejects based on file name alone — the manifest is the source
///    of truth for which extensions map to which systems.
class ContentImporter {
  ContentImporter(this._hashVerifier, {RomValidator? romValidator})
      : _romValidator = romValidator ?? const RomValidator();
  final HashVerifier _hashVerifier;
  final RomValidator _romValidator;

  /// Imports a single file at [filePath].
  ///
  /// [knownShas] is the set of SHA-256 hashes already in the library; used
  /// to reject duplicates. [catalog] is the parsed core manifest catalog
  /// (id -> manifest) used to match extensions to systems.
  Future<ImportResult> importFile(
    String filePath, {
    required Set<String> knownShas,
    required Map<String, CoreManifest> catalog,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      return ImportResult(filePath: filePath, error: 'File does not exist');
    }

    // Hold cores: reject any file whose system maps to a blocked core.
    final ext = filePath.split('.').last.toLowerCase();
    final matchingCores = catalog.values.where(
      (m) => m.extensions.map((e) => e.toLowerCase()).contains(ext),
    );
    for (final core in matchingCores) {
      if (core.blocked) {
        return ImportResult(
          filePath: filePath,
          skippedReason: 'Rejected: ${core.name} is on hold',
        );
      }
    }
    if (matchingCores.isEmpty) {
      return ImportResult(
        filePath: filePath,
        skippedReason: 'No core for extension .$ext',
      );
    }

    // Validate file content — reject text files, wrong-size files, and
    // files whose bytes don't match the expected ROM format.
    final isValidRom = await _romValidator.validate(filePath, ext);
    if (!isValidRom) {
      return ImportResult(
        filePath: filePath,
        skippedReason: 'Not a valid ROM file (content validation failed)',
      );
    }

    final sha = (await _hashVerifier.sha256File(filePath)).toLowerCase();
    if (knownShas.contains(sha)) {
      return ImportResult(
        filePath: filePath,
        skippedReason: 'Duplicate (already in library)',
      );
    }

    final core = matchingCores.first;
    final system = core.systems.isNotEmpty ? core.systems.first : ext;
    final title = filePath.split(Platform.pathSeparator).last;
    final game = GameEntry(
      id: 'imp-$sha',
      title: title,
      system: system,
      filePath: filePath,
      extension: ext,
      sha1: sha,
      coreId: core.id,
    );
    return ImportResult(filePath: filePath, game: game);
  }

  /// Scans [dirPath] for import candidates.
  ///
  /// Returns an [ImportScan] listing each file's outcome. Does not mutate
  /// the library — the caller decides which results to accept.
  ///
  /// Skips hidden directories, caches, SDKs, and other non-ROM dirs
  /// (see [shouldSkipDir]) to keep the scan fast.
  Future<ImportScan> scanDirectory(
    String dirPath, {
    required Set<String> knownShas,
    required Map<String, CoreManifest> catalog,
  }) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      return ImportScan(
        results: [],
        manifestError: 'Directory does not exist: $dirPath',
      );
    }

    final results = <ImportResult>[];
    await _scanRecursive(dir, knownShas, catalog, results);
    return ImportScan(results: results);
  }

  /// Recursively scans [dir], skipping hidden/cached/system directories.
  Future<void> _scanRecursive(
    Directory dir,
    Set<String> knownShas,
    Map<String, CoreManifest> catalog,
    List<ImportResult> results,
  ) async {
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is Directory) {
        final dirName = entity.path.split(Platform.pathSeparator).last;
        if (shouldSkipDir(dirName)) continue;
        await _scanRecursive(entity, knownShas, catalog, results);
      } else if (entity is File) {
        final result = await importFile(
          entity.path,
          knownShas: knownShas,
          catalog: catalog,
        );
        results.add(result);
      }
    }
  }

  /// Default roots for a "scan everything" pass.
  ///
  /// Platform-aware: returns common ROM storage locations per OS.
  /// Never scans the entire home directory or system directories.
  ///
  /// - Linux: ~/Documents/ROMS, ~/ROMS, ~/Games, ~/Emulation
  /// - Windows: C:\Users\<user>\Documents\ROMS, C:\Users\<user>\Games, C:\ROMs
  /// - macOS: ~/Documents/ROMS, ~/ROMS, ~/Games, ~/Emulation
  /// - iOS: empty — sandboxed, no general storage access
  /// - Android: /sdcard/ROMS, /sdcard/Games, /storage/emulated/0/ROMS
  static List<String> driveRoots() {
    if (Platform.isIOS) return const [];

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return const [];

    final candidates = <String>[];

    if (Platform.isAndroid) {
      // Android: common external-storage ROM locations
      candidates.addAll([
        '/sdcard/ROMS',
        '/sdcard/Roms',
        '/sdcard/roms',
        '/sdcard/Games',
        '/sdcard/games',
        '/storage/emulated/0/ROMS',
        '/storage/emulated/0/Games',
      ]);
    } else if (Platform.isWindows) {
      // Windows: user Documents + Games + root-level ROMs
      candidates.addAll([
        '$home\\Documents\\ROMS',
        '$home\\Documents\\Roms',
        '$home\\Documents\\roms',
        '$home\\Games',
        '$home\\games',
        '$home\\ROMs',
        '$home\\Roms',
        'C:\\ROMs',
        'C:\\ROMS',
        'C:\\Games',
      ]);
    } else {
      // Linux + macOS: common home-dir ROM locations
      candidates.addAll([
        '$home/Documents/ROMS',
        '$home/Documents/Roms',
        '$home/Documents/roms',
        '$home/ROMs',
        '$home/Roms',
        '$home/roms',
        '$home/Games',
        '$home/games',
        '$home/Emulation',
        '$home/emulation',
      ]);
    }

    final out = <String>[];
    for (final path in candidates) {
      final dir = Directory(path);
      if (dir.existsSync()) out.add(dir.path);
    }
    return out;
  }

  /// Returns `true` if [dirName] should be skipped during a scan.
  ///
  /// Skips hidden dirs (starting with `.`), caches, SDKs, and other
  /// non-ROM directories that would slow down the scan or produce
  /// false positives.
  static bool shouldSkipDir(String dirName) {
    // Hidden dirs (.git, .cache, .local, etc.)
    if (dirName.startsWith('.')) return true;

    // Caches and build artifacts
    if (dirName == 'node_modules' ||
        dirName == '__pycache__' ||
        dirName == '.pub-cache' ||
        dirName == '.gradle' ||
        dirName == '.dart_tool' ||
        dirName == 'build' ||
        dirName == 'target' ||
        dirName == '.Trash' ||
        dirName == 'Trash' ||
        dirName == '\$RECYCLE.BIN' ||
        dirName == 'System Volume Information') {
      return true;
    }

    // SDKs and system dirs (Android-specific)
    if (dirName == 'Android' || dirName == 'Sdk') return true;

    return false;
  }

  /// Directory names that are never descended into during a scan.
  static const skippedDirNames = {
    'node_modules',
    '__pycache__',
    '.git',
    '.hg',
    '.svn',
    '.cache',
    '.pub-cache',
    '.gradle',
    '.dart_tool',
    '.Trash',
    'Trash',
    '\$RECYCLE.BIN',
    'System Volume Information',
    'Android',
    'Sdk',
  };

}

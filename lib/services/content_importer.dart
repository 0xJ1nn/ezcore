import 'dart:io';

import '../models/core_manifest.dart';
import '../models/game_entry.dart';
import 'hash_verifier.dart';

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
/// 3. Rejects files whose system is on a legal hold (blocked cores).
/// 4. Hashes the file (SHA-256) for deduplication + integrity.
/// 5. Rejects duplicates (same hash already in library).
/// 6. Never rejects based on file name alone — the manifest is the source
///    of truth for which extensions map to which systems.
class ContentImporter {
  ContentImporter(this._hashVerifier);
  final HashVerifier _hashVerifier;

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

    // Legal holds: reject any file whose system maps to a blocked core.
    final ext = filePath.split('.').last.toLowerCase();
    final matchingCores = catalog.values.where(
      (m) => m.extensions.map((e) => e.toLowerCase()).contains(ext),
    );
    for (final core in matchingCores) {
      if (core.blocked) {
        return ImportResult(
          filePath: filePath,
          skippedReason: 'Rejected: ${core.name} is on legal hold',
        );
      }
    }
    if (matchingCores.isEmpty) {
      return ImportResult(
        filePath: filePath,
        skippedReason: 'No core for extension .$ext',
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
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        final result = await importFile(
          entity.path,
          knownShas: knownShas,
          catalog: catalog,
        );
        results.add(result);
      }
    }
    return ImportScan(results: results);
  }
}

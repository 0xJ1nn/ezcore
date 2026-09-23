import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../cores/core_registry.dart';
import '../models/cheat.dart';
import '../models/game_entry.dart';
import '../services/local_data_dir.dart';
import '../services/core_discovery.dart';
import '../services/core_staging.dart';
import '../services/repo_layout.dart';
import '../services/persistence_service.dart';
import '../services/content_importer.dart';
import '../services/hash_verifier.dart';
import 'save_sync.dart';

/// Summary of a [AppState.rescanRomFolders] pass.
class RescanReport {
  const RescanReport({
    this.added = 0,
    this.pruned = 0,
    this.foldersScanned = 0,
    this.cancelled = false,
  });

  final int added;
  final int pruned;
  final int foldersScanned;
  final bool cancelled;

  bool get changed => added > 0 || pruned > 0;
}

/// Application state: games, favorites, core choices, cheats, settings.
///
/// Default save/sync is [LocalSaveSyncProvider] backed by the platform
/// application-support directory; persistence uses [PersistenceService].
/// The in-memory providers remain available for tests and ephemeral
/// sessions via the named [AppState.ephemeral] constructor.
class AppState extends ChangeNotifier {
  /// Production constructor: uses [LocalSaveSyncProvider] and
  /// [PersistenceService] backed by the platform data directory.
  /// Pass the startup-resolved provider from `main()` on mobile; desktop
  /// resolves synchronously when omitted.
  factory AppState({LocalDataDirProvider? dirProvider}) {
    final resolved =
        dirProvider ?? PlatformLocalDataDirProvider();
    final dir = Directory(resolved.localDataDirPath());
    final saves = LocalSaveSyncProvider(dir);
    final persistence = PersistenceService(resolved);
    return AppState.internal(persistence: persistence, saves: saves);
  }

  /// Creates an in-memory state with no persistence — used by tests.
  /// [documentsProvider] roots the managed "ezCORE ROMs" folder at a
  /// caller-chosen directory (tests point it at a temp dir).
  factory AppState.ephemeral({
    Future<Directory> Function()? documentsProvider,
  }) {
    return AppState.internal(
      persistence: null,
      saves: MemorySaveSyncProvider(),
      documentsProvider: documentsProvider,
    );
  }

  /// Test/injection constructor — accepts explicit persistence + saves.
  @visibleForTesting
  AppState.internal({
    required this.persistence,
    required this.saves,
    this.documentsProvider,
  });

  /// Base directory for the managed "ezCORE ROMs" folder. Null in
  /// production: the platform Documents directory is resolved lazily at
  /// creation time (see [_romsBaseDir]).
  final Future<Directory> Function()? documentsProvider;

  /// The persistence service. Null when ephemeral.
  @visibleForTesting
  final PersistenceService? persistence;

  final CoreRegistry registry = CoreRegistry();
  List<GameEntry> games = [];
  final Map<String, List<CheatEntry>> cheatsByGame = {};

  /// Save/sync seam: local vault by default; swap in a cloud provider
  /// (or memory provider for tests) without touching callers.
  final SaveSyncProvider saves;

  bool loaded = false;
  String? loadError;
  Map<String, String> coreDiscoveryErrors = {};

  /// Persisted settings map (backed by PersistenceService).
  Map<String, dynamic> _settings = {};

  Map<String, dynamic> get settings => Map.unmodifiable(_settings);

  /// Stages bundled/dev cores into the local vault (verified copies), then
  /// returns the vault path when it holds anything. Never throws: staging
  /// failures surface per-core through discovery errors instead.
  Future<String?> _stagedVaultRoot() async {
    try {
      await CoreStagingService().ensureStaged(catalog: registry.catalog);
    } catch (_) {
      // Fall through to dev-checkout roots below.
    }
    final vault = CoreStagingService.vaultDir();
    if (!vault.existsSync()) return null;
    try {
      if (vault.listSync().isEmpty) return null;
    } catch (_) {
      return null;
    }
    return vault.path;
  }

  /// Release-bundle cores — the read-only fallback when staging hasn't
  /// populated the vault yet (or the vault was cleared):
  /// macOS `<app>/Contents/Resources/ezcore/cores`, Windows/Linux
  /// `<exeDir>/cores`.
  String? _bundledCoresRoot() {
    final roots = RepoLayout.bundledCoreRoots(
      executablePath: Platform.resolvedExecutable,
    );
    return roots.isEmpty ? null : roots.first;
  }

  Future<void> load() async {
    try {
      // Load the merged catalog (single file — reliable asset bundling)
      final catalogRaw = await rootBundle.loadString('cores/catalog.json');
      final catalog = json.decode(catalogRaw) as Map<String, dynamic>;
      final manifests = <String, String>{};
      for (final entry in catalog.entries) {
        manifests[entry.key] = json.encode(entry.value);
      }
      final errors = registry.loadCatalog(manifests);
      if (errors.isNotEmpty) {
        loadError = errors.entries
            .map((e) => '${e.key}: ${e.value.join(', ')}')
            .join('; ');
      }
      registry.addListener(notifyListeners);

      // Load persisted state from local storage
      final p = persistence;
      if (p != null) {
        final persisted = await p.load();
        games = List.of(persisted.games);
        cheatsByGame.clear();
        cheatsByGame.addAll(persisted.cheatsByGame);
        _settings = Map<String, dynamic>.from(persisted.settings);
      }
      final coreRoot = _settings['coreDirectory'] as String? ??
          Platform.environment['EZCORE_CORES_DIR'] ??
          await _stagedVaultRoot() ??
          _bundledCoresRoot() ??
          RepoLayout.stagedCoresRoot(executablePath: Platform.resolvedExecutable) ??
          RepoLayout.coresRoot(executablePath: Platform.resolvedExecutable) ??
          RepoLayout.coresRoot() ?? 'native/cores';
      final discovery = CoreDiscovery(Directory(coreRoot));
      await discovery.discover(registry);
      coreDiscoveryErrors = Map.unmodifiable(discovery.errors);
    } catch (e) {
      loadError = e.toString();
    }
    loaded = true;
    notifyListeners();
  }

  /// Persists current state; await before reporting a durable UI operation.
  Future<void> persist() async {
    final p = persistence;
    if (p == null) return;
    await p.saveAll(PersistedState(
      games: games,
      cheatsByGame: cheatsByGame,
      settings: _settings,
    ));
  }

  Future<void> _persist() => persist();

  // --- games ---
  void toggleFavorite(String id) {
    games = games
        .map((g) => g.id == id ? g.copyWith(favorite: !g.favorite) : g)
        .toList();
    notifyListeners();
    _persist();
  }

  void setCore(String id, String coreId) {
    games =
        games.map((g) => g.id == id ? g.copyWith(coreId: coreId) : g).toList();
    notifyListeners();
    _persist();
  }

  void addGame(GameEntry game) {
    games = [...games, game];
    notifyListeners();
    _persist();
  }

  void removeGame(String id) {
    games = games.where((g) => g.id != id).toList();
    notifyListeners();
    _persist();
  }

  void recordPlay(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    games = games
        .map((g) => g.id == id ? g.copyWith(lastPlayedMs: now) : g)
        .toList();
    notifyListeners();
    _persist();
  }

  void setStateCount(String id, int count) {
    games =
        games.map((g) => g.id == id ? g.copyWith(stateCount: count) : g)
            .toList();
    notifyListeners();
    _persist();
  }

  // --- cheats ---
  List<CheatEntry> cheatsFor(String gameId) =>
      List.unmodifiable(cheatsByGame[gameId] ?? const []);

  void addCheat(String gameId, CheatEntry cheat) {
    cheatsByGame[gameId] = [...cheatsFor(gameId), cheat];
    _syncCheatCount(gameId);
    _persist();
  }

  void toggleCheat(String gameId, int index) {
    cheatsByGame[gameId] =
        cheatsFor(gameId).map((c) => c.index == index ? c.toggled() : c).toList();
    _syncCheatCount(gameId);
    _persist();
  }

  void deleteCheat(String gameId, int index) {
    cheatsByGame[gameId] =
        cheatsFor(gameId).where((c) => c.index != index).toList();
    _syncCheatCount(gameId);
    _persist();
  }

  void importCheats(String gameId, String chtText) {
    cheatsByGame[gameId] = parseCht(chtText);
    _syncCheatCount(gameId);
    _persist();
  }

  void _syncCheatCount(String gameId) {
    final on = cheatsFor(gameId).where((c) => c.enabled).length;
    games = games.map((g) => g.id == gameId ? g.copyWith(cheatsOn: on) : g)
        .toList();
    notifyListeners();
  }

  // --- ROM folders: watched roots, auto-scanned on launch + on demand ---
  static const romFoldersKey = 'romFolders';

  /// Folders the user registered via "Add ROM folder". Persisted in settings.
  List<String> get romFolders {
    final raw = _settings[romFoldersKey];
    if (raw is! List) return const [];
    return [for (final e in raw) if (e is String && e.isNotEmpty) e];
  }

  Future<void> addRomFolder(String path) async {
    final next = [...romFolders];
    if (!next.contains(path)) next.add(path);
    await setSetting(romFoldersKey, next);
  }

  Future<void> removeRomFolder(String path) async {
    await setSetting(
      romFoldersKey,
      [for (final p in romFolders) if (p != path) p],
    );
  }

  // --- managed "ezCORE ROMs" folder: one home for imported games ---

  /// Setting keys for the managed folder path and its one-time offer.
  static const romsFolderKey = 'ezcoreRomsFolder';
  static const romsFolderPromptKey = 'ezcoreRomsFolderPrompted';

  /// Path of the managed folder, once the user opted in (null otherwise).
  String? get ezcoreRomsFolder {
    final raw = _settings[romsFolderKey];
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  /// Whether the create-folder question has been answered (either way).
  bool get romsFolderPrompted => _settings[romsFolderPromptKey] == true;

  /// Base directory hosting the managed folder: injected seam in tests;
  /// production resolves the platform Documents directory (user-visible —
  /// the point of the folder is that the player can find it directly),
  /// with a `~/Documents` fallback where path_provider is unavailable.
  Future<Directory> _romsBaseDir() async {
    final inject = documentsProvider;
    if (inject != null) return inject();
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
      final docs = Directory('$home${Platform.pathSeparator}Documents');
      if (!docs.existsSync()) docs.createSync(recursive: true);
      return docs;
    }
  }

  /// Creates `<Documents>/ezCORE ROMs`, registers it as a watched ROM
  /// folder, and records the prompt as answered. Idempotent: repeat
  /// calls return the same path without duplicating watch entries.
  Future<String> createEzcoreRomsFolder() async {
    final base = await _romsBaseDir();
    final dir = Directory('${base.path}${Platform.pathSeparator}ezCORE ROMs');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    if (ezcoreRomsFolder != dir.path) {
      await setSetting(romsFolderKey, dir.path);
    }
    if (!romFolders.contains(dir.path)) await addRomFolder(dir.path);
    if (!romsFolderPrompted) await setSetting(romsFolderPromptKey, true);
    return dir.path;
  }

  /// Records a dismissed prompt — offered once, never nagged again.
  Future<void> declineEzcoreRomsFolder() =>
      setSetting(romsFolderPromptKey, true);

  /// Copies files in [paths] into the managed folder and returns the
  /// paths to import from. Identity for directories (scanned in place),
  /// missing paths (per-item errors must survive), and files already
  /// inside the folder. A same-name collision with identical content
  /// reuses the existing copy (SHA-256, not just size); different
  /// content gets a ` (2)` suffix. No-op without an opted-in folder.
  Future<List<String>> copyGamesIntoRomsFolder(Iterable<String> paths) async {
    final folder = ezcoreRomsFolder;
    if (folder == null) return paths.toList();
    final dir = Directory(folder);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final sep = Platform.pathSeparator;
    final inside = '$folder$sep';
    final hashes = const PlatformHashVerifier();
    final out = <String>[];
    for (final p in paths) {
      final src = File(p);
      if (p.startsWith(inside) ||
          !src.existsSync() ||
          FileSystemEntity.isDirectorySync(p)) {
        out.add(p);
        continue;
      }
      var destPath = '$folder$sep${p.split(sep).last}';
      if (File(destPath).existsSync()) {
        final srcSha = await hashes.sha256File(p);
        if (srcSha == await hashes.sha256File(destPath)) {
          out.add(destPath); // already home with the same bytes
          continue;
        }
        final name = p.split(sep).last;
        final dot = name.lastIndexOf('.');
        final stem = dot > 0 ? name.substring(0, dot) : name;
        final ext = dot > 0 ? name.substring(dot) : '';
        var n = 2;
        destPath = '$folder$sep$stem ($n)$ext';
        while (File(destPath).existsSync() &&
            await hashes.sha256File(destPath) != srcSha) {
          n++;
          destPath = '$folder$sep$stem ($n)$ext';
        }
      }
      if (!File(destPath).existsSync()) await src.copy(destPath);
      out.add(destPath);
    }
    return out;
  }

  /// Re-scans every registered folder (recursive, core-matched) and adds
  /// anything new to the library. Also prunes entries whose file vanished
  /// while its folder still exists — but never prunes when the folder
  /// itself is gone (unplugged drive), so missing mounts can't wipe games.
  Future<RescanReport> rescanRomFolders() async {
    final folders = romFolders.where((p) => Directory(p).existsSync()).toList();
    if (folders.isEmpty || registry.catalog.isEmpty) {
      return const RescanReport();
    }
    final importer = ContentImporter(const PlatformHashVerifier());
    final catalog = {for (final m in registry.catalog) m.id: m};
    final known = games.map((g) => g.sha1).toSet();
    var added = 0;
    var scanned = 0;
    for (final folder in folders) {
      final scan = await importer.scanDirectory(
        folder,
        knownShas: known,
        catalog: catalog,
      );
      for (final result in scan.results) {
        if (result.isSuccess && result.game != null) {
          addGame(result.game!);
          known.add(result.game!.sha1);
          added++;
        }
      }
      scanned++;
    }
    // Prune: remove games whose file is gone but folder still exists
    var pruned = 0;
    final liveRoots = romFolders.where((p) => Directory(p).existsSync());
    final livePaths = <String>{};
    for (final root in liveRoots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is File) livePaths.add(entity.path);
      }
    }
    final before = games.length;
    games = games.where((g) {
      if (livePaths.contains(g.filePath)) return true;
      // File gone — only prune if its folder still exists
      final parent = Directory(g.filePath).parent.path;
      if (romFolders.contains(parent) && Directory(parent).existsSync()) {
        return false; // prune
      }
      return true; // keep (unplugged drive)
    }).toList();
    pruned = before - games.length;
    if (added > 0 || pruned > 0) {
      notifyListeners();
      await _persist();
    }
    return RescanReport(added: added, pruned: pruned, foldersScanned: scanned);
  }

  // --- settings ---
  Future<void> setSetting(String key, dynamic value) async {
    _settings = {..._settings, key: value};
    notifyListeners();
    await _persist();
  }

  Future<void> removeSetting(String key) async {
    final next = Map<String, dynamic>.from(_settings)..remove(key);
    _settings = next;
    notifyListeners();
    await _persist();
  }

  @override
  void dispose() {
    registry.removeListener(notifyListeners);
    super.dispose();
  }
}

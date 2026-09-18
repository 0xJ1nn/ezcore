import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../cores/core_registry.dart';
import '../models/cheat.dart';
import '../models/game_entry.dart';
import '../services/local_data_dir.dart';
import '../services/core_discovery.dart';
import '../services/core_staging.dart';
import '../services/repo_layout.dart';
import '../services/persistence_service.dart';
import 'save_sync.dart';

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
  factory AppState.ephemeral() {
    return AppState.internal(persistence: null, saves: MemorySaveSyncProvider());
  }

  /// Test/injection constructor — accepts explicit persistence + saves.
  @visibleForTesting
  AppState.internal({
    required this.persistence,
    required this.saves,
  });

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

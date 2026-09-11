import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../cores/core_registry.dart';
import '../data/mock_library.dart';
import '../models/cheat.dart';
import '../models/game_entry.dart';
import 'save_sync.dart';

/// Ephemeral v0 state holder. Migration path: Riverpod + Drift (see plan).
class AppState extends ChangeNotifier {
  final CoreRegistry registry = CoreRegistry();
  List<GameEntry> games = List.of(mockGames);
  final Map<String, List<CheatEntry>> cheatsByGame = {};
  final Map<String, String> biosStatus = {};

  /// Save/sync seam: memory by default; swap in LocalSaveSyncProvider
  /// (or a future cloud provider) without touching callers.
  SaveSyncProvider saves = MemorySaveSyncProvider();

  bool loaded = false;
  String? loadError;

  Future<void> load() async {
    try {
      final regRaw = await rootBundle.loadString('cores/registry.json');
      final decoded = json.decode(regRaw) as Map<String, dynamic>;
      final ids = (decoded['cores'] as List).map((e) => e.toString());
      final manifests = <String, String>{};
      for (final id in ids) {
        manifests[id] =
            await rootBundle.loadString('cores/$id/manifest.json');
      }
      final errors = registry.loadCatalog(manifests);
      if (errors.isNotEmpty) {
        loadError = errors.entries
            .map((e) => '${e.key}: ${e.value.join(', ')}')
            .join('; ');
      }
      registry.addListener(notifyListeners);
    } catch (e) {
      loadError = e.toString();
    }
    loaded = true;
    notifyListeners();
  }

  // --- games ---
  void toggleFavorite(String id) {
    games = games
        .map((g) => g.id == id ? g.copyWith(favorite: !g.favorite) : g)
        .toList();
    notifyListeners();
  }

  void setCore(String id, String coreId) {
    games =
        games.map((g) => g.id == id ? g.copyWith(coreId: coreId) : g).toList();
    notifyListeners();
  }

  void addGame(GameEntry game) {
    games = [...games, game];
    notifyListeners();
  }

  void removeGame(String id) {
    games = games.where((g) => g.id != id).toList();
    notifyListeners();
  }

  // --- cheats ---
  List<CheatEntry> cheatsFor(String gameId) =>
      List.unmodifiable(cheatsByGame[gameId] ?? const []);

  void addCheat(String gameId, CheatEntry cheat) {
    cheatsByGame[gameId] = [...cheatsFor(gameId), cheat];
    _syncCheatCount(gameId);
  }

  void toggleCheat(String gameId, int index) {
    cheatsByGame[gameId] =
        cheatsFor(gameId).map((c) => c.index == index ? c.toggled() : c).toList();
    _syncCheatCount(gameId);
  }

  void deleteCheat(String gameId, int index) {
    cheatsByGame[gameId] =
        cheatsFor(gameId).where((c) => c.index != index).toList();
    _syncCheatCount(gameId);
  }

  void importCheats(String gameId, String chtText) {
    cheatsByGame[gameId] = parseCht(chtText);
    _syncCheatCount(gameId);
  }

  void _syncCheatCount(String gameId) {
    final on = cheatsFor(gameId).where((c) => c.enabled).length;
    games = games.map((g) => g.id == gameId ? g.copyWith(cheatsOn: on) : g)
        .toList();
    notifyListeners();
  }
}

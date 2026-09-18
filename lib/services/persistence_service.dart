import 'dart:convert';
import 'dart:io';

import '../models/cheat.dart';
import '../models/game_entry.dart';
import 'local_data_dir.dart';

/// Snapshot of all persisted application state.
///
/// Serialized as a single JSON object to `state.json`. Schema version
/// is the `schema` key so future migrations can detect old formats.
class PersistedState {
  PersistedState({
    this.games = const [],
    this.cheatsByGame = const {},
    this.settings = const {},
  });

  static const int schemaVersion = 1;

  final List<GameEntry> games;
  final Map<String, List<CheatEntry>> cheatsByGame;
  final Map<String, dynamic> settings;

  factory PersistedState.fromJson(Map<String, dynamic> json) {
    final gamesRaw = (json['games'] as List?) ?? [];
    final cheatsRaw = (json['cheats'] as Map<String, dynamic>?) ?? {};
    return PersistedState(
      games: gamesRaw
          .map((g) => GameEntry.fromJson(g as Map<String, dynamic>))
          .toList(),
      cheatsByGame: cheatsRaw.map((k, v) => MapEntry(
            k,
            (v as List)
                .map((c) => CheatEntry.fromJson(c as Map<String, dynamic>))
                .toList(),
          )),
      settings: (json['settings'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
        'schema': schemaVersion,
        'games': games.map((g) => g.toJson()).toList(),
        'cheats': cheatsByGame.map((k, v) => MapEntry(
              k,
              v.map((c) => c.toJson()).toList(),
            )),
        'settings': settings,
      };
}

/// JSON-file-backed persistence for games, cheats, and settings.
///
/// The entire state is serialized to a single `state.json` file in the
/// local data directory. Every mutating operation writes the full state
/// atomically (write temp + rename) so a crash mid-write cannot corrupt
/// the store. On read, a corrupt file yields an empty state rather than
/// crashing the app.
class PersistenceService {
  PersistenceService(
    this._dirProvider, {
    this.filename = 'state.json',
  });
  final LocalDataDirProvider _dirProvider;
  final String filename;
  Future<void> _pending = Future<void>.value();

  // Serialize entire read/modify/write transactions, not just renames.
  // The caller retains the error; a failure must not poison later writes.
  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<File> _stateFile() async {
    final dir = await _dirProvider.localDataDir();
    return File('${dir.path}/$filename');
  }

  Future<void> _ensureParent() async {
    final file = await _stateFile();
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
  }

  /// Reads the persisted state. Returns an empty state when no file
  /// exists or the file is corrupt.
  Future<PersistedState> load() async {
    final file = await _stateFile();
    if (!file.existsSync()) return PersistedState();
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return PersistedState.fromJson(decoded);
    } catch (_) {
      return PersistedState();
    }
  }

  Future<void> _write(PersistedState state) async {
    await _ensureParent();
    final file = await _stateFile();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json.encode(state.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  /// Replaces the games list in the persisted state.
  Future<void> saveGames(List<GameEntry> games) => _enqueue(() async {
    final current = await load();
    await _write(PersistedState(
      games: games,
      cheatsByGame: current.cheatsByGame,
      settings: current.settings,
    ));
  });

  /// Replaces the cheats map in the persisted state.
  Future<void> saveCheats(Map<String, List<CheatEntry>> cheats) => _enqueue(() async {
    final current = await load();
    await _write(PersistedState(
      games: current.games,
      cheatsByGame: cheats,
      settings: current.settings,
    ));
  });

  /// Replaces the settings map in the persisted state.
  Future<void> saveSettings(Map<String, dynamic> settings) => _enqueue(() async {
    final current = await load();
    await _write(PersistedState(
      games: current.games,
      cheatsByGame: current.cheatsByGame,
      settings: settings,
    ));
  });

  /// Replaces the entire persisted state atomically.
  Future<void> saveAll(PersistedState state) {
    final snapshot = PersistedState.fromJson(
      jsonDecode(jsonEncode(state.toJson())) as Map<String, dynamic>,
    );
    return _enqueue(() => _write(snapshot));
  }

  /// Deletes the persisted state file (used by tests and reset flows).
  Future<void> deleteAll() async {
    final file = await _stateFile();
    if (file.existsSync()) await file.delete();
  }
}

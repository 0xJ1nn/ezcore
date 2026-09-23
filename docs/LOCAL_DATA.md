# ezCore — Local Data & Persistence

> **Version:** 1.0
> **Date:** 2026-09-18

---

## Overview

ezCore persists all user-owned data locally. No games, BIOS, or copyrighted assets ship with the app — every byte of content is supplied by the user through the import flow and stored under the platform application-support directory.

---

## Local Data Directory

```
macOS:   ~/Library/Application Support/ezcore/
Windows: %APPDATA%\ezcore\
Linux:   ~/.local/share/ezcore/
Mobile:  ./.ezcore/ (temporary fallback; native app-directory integration NOT implemented)
```

Resolved by `PlatformLocalDataDirProvider`. Tests inject a temp directory via `LocalDataDirProvider` seam.

---

## Files

```
<localDataDir>/
├── state.json          # PersistenceService: games, cheats, settings
├── cores/
│   └── <id>/
│       └── <id>.so|dylib|dll   # Installed core artifacts
└── saves/                      # SaveSyncProvider (LocalSaveSyncProvider)
    └── <gameId>/
        └── <slot>.bin
```

---

## PersistenceService

`lib/services/persistence_service.dart`

Single JSON document holding the persisted application state. Writes use a flushed temporary file and rename. Save transactions are serialized per service instance, including partial-update reads, to prevent concurrent renames and lost updates. `saveAll` snapshots its input when called. Cross-process locking and concurrent reset/delete handling are not implemented.

Schema (`state.json`):

```json
{
  "schema": 1,
  "games": [ { "id": "...", "title": "...", ... } ],
  "cheats": { "game-id": [ { "index": 0, "desc": "...", "code": "...", "enabled": true } ] },
  "settings": { "theme": "dark", ... }
}
```

| Method | Behavior |
|---|---|
| `load()` | Reads `state.json`, returns `PersistedState`. Corrupt or missing → empty. |
| `saveGames(List<GameEntry>)` | Replaces games, preserves cheats + settings. |
| `saveCheats(Map<String,List<CheatEntry>>)` | Replaces cheats, preserves games + settings. |
| `saveSettings(Map<String,dynamic>)` | Replaces settings, preserves games + cheats. |
| `saveAll(PersistedState)` | Atomic full-state replace. |
| `deleteAll()` | Removes `state.json`. |

---

## GameEntry JSON

`lib/models/game_entry.dart` now exposes `fromJson`/`toJson` and `operator ==` / `hashCode`.

```json
{
  "id": "imp-abc123",
  "title": "My GBA Dump",
  "system": "gba",
  "filePath": "/Users/me/games/mydump.gba",
  "extension": "gba",
  "fileSize": 8388608,
  "sha1": "deadbeef...",
  "favorite": true,
  "coreId": "mgba",
  "lastPlayedMs": 1725900000000,
  "cheatsOn": 2,
  "stateCount": 4
}
```

---

## CheatEntry JSON

`lib/models/cheat.dart` now exposes `fromJson`/`toJson` and `operator ==` / `hashCode`.

```json
{
  "index": 0,
  "desc": "Infinite lives",
  "code": "DEADBEEF",
  "enabled": true
}
```

---

## ContentImporter

`lib/services/content_importer.dart`

Validates user-supplied files against the core manifest catalog:

1. **File existence** — rejects non-existent paths.
2. **Extension match** — looks up extension in catalog artifacts. No match → skip.
3. **Hold rejection** — if any matching core is `blocked`, the file is rejected with `skippedReason` naming the hold.
4. **SHA-256 dedup** — rejects files whose hash already exists in the library.
5. **Game entry creation** — produces a `GameEntry` with `id = 'imp-<sha>'`, `coreId` set to the first matching core.

---

## CorePathResolver

`lib/services/core_path_resolver.dart`

Resolves and verifies installed core artifacts before launch:

1. **Platform key** — `currentPlatformKey()` derives `os-arch` (e.g. `macos-arm64`).
2. **Artifact lookup** — matches platform key to `manifest.artifacts` map.
3. **File check** — artifact must exist at `<localDataDir>/cores/<id>/<id>.so|dylib|dll`.
4. **Hold check** — blocked cores throw `StateError` before any hashing.
5. **SHA-256 pin verification** — actual hash must equal manifest pin; mismatch throws.

---

## HashVerifier

`lib/services/hash_verifier.dart`

`PlatformHashVerifier` tries `shasum -a 256`, `sha256sum`, `certutil` in order. Tests inject via `HashVerifier` seam.

---

## AppState Integration

`lib/state/app_state.dart`

- `AppState()` uses local persistence; `AppState.ephemeral()` is explicitly in-memory.
- `load()` loads the catalog, persisted games, cheats, and settings.
- Mutators call persistence after notifying listeners. Legacy void mutators do not yet expose write completion/failure to UI callers; do not use them alone as proof of a successful disk write.
- `LocalSaveSyncProvider` is the production default; memory saves remain available for tests.

---

## AppState Defaults

`AppState` now defaults to local persistence:

| Field | Default |
|---|---|
| `saves` | `LocalSaveSyncProvider(<platformDataDir>)` |
| persistence | `PersistenceService(PlatformLocalDataDirProvider())` |

The `AppState.ephemeral()` named factory returns an in-memory state with no disk backing — used by tests. The `AppState.internal` constructor accepts explicit persistence + saves for injection in tests.

Settings (`setSetting`/`removeSetting`) are persisted alongside games and cheats in `state.json`.

---

## Removed

- `lib/data/mock_library.dart` — deleted. `mockGames` no longer used by AppState. `systemLabels` moved to `lib/services/system_labels.dart`.

---

## Tests

```
test/game_entry_json_test.dart        — GameEntry/CheatEntry JSON round-trip + equality
test/persistence_service_test.dart    — PersistenceService load/save/delete round-trips
test/core_path_resolver_test.dart    — CorePathResolver platform key, resolve, verifyPin
test/content_importer_test.dart      — ContentImporter file validation, holds, dedup
test/local_data_dir_test.dart        — PlatformLocalDataDirProvider + fake
test/hash_verifier_test.dart         — PlatformHashVerifier computes SHA-256
test/app_state_defaults_test.dart    — AppState factory defaults to LocalSaveSyncProvider
test/app_state_persist_test.dart     — AppState persists games/cheats/settings to disk
```

All new tests pass. Existing `core_registry_test.dart`, `save_sync_test.dart`, `core_manifest_test.dart`, `library_smoke_test.dart` remain green.

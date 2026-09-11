# ezCore Architecture

```
Flutter UI  →  C ABI / FFI  →  ezCore Runtime  →  modular cores
 lib/          lib/runtime/     runtime/           cores/ + native/
```

Rules:

1. **Cores never touch Flutter.** Every core speaks the runtime ABI
   (`runtime/include/ezcore_runtime.h`, versioned `EZCORE_ABI_VERSION`).
   A core that satisfies the ABI works on every platform unchanged.
2. **The runtime owns execution.** Lifecycle, game loading, frame
   execution, video/audio plumbing, input, save states, cheats,
   host directories, and core quirks live in `runtime/src/runtime.c`.
   The frontend only drives sessions and renders textures.
3. **Platform execution strategy lives in data, not code.**
   Each core manifest declares `execution`: per-OS `interpreter` or
   `dynarec` (`unknown` when undeclared). iOS must never resolve to
   dynarec — enforced by manifest validation. The Flutter layer never
   branches on JIT capability.
4. **Save bytes are opaque.** `ezcore_serialize` produces bytes the
   frontend never interprets. `lib/state/save_sync.dart` defines the
   `SaveSyncProvider` seam: `MemorySaveSyncProvider` (default),
   `LocalSaveSyncProvider` (vault), and future cloud providers
   (iCloud / OneDrive / account sync) implement the same four methods.
5. **Game → Play.** The library resolves a game to a core
   (`CoreRegistry.compatibleCores`); when the user never picked one,
   the first compatible installed core is used and remembered.
   No core/renderer/BIOS thinking required.

## Layer map

| Layer | Dir | Owns |
|---|---|---|
| UI | `lib/screens`, `lib/theme` | library, player chrome, settings, import |
| State | `lib/state` | `AppState`, `SaveSyncProvider` seam |
| Core catalog | `lib/models`, `lib/cores` (registry only) | manifests, install/update/remove, cheat formats |
| FFI | `lib/runtime/ezcore_runtime.dart` | zero-dep Dart bindings over the C ABI |
| Runtime | `runtime/` | session lifecycle, AV plumbing, cheats, saves, quirks |
| Cores | `cores/<id>/manifest.json`, `native/` | versioned plugins, sha-pinned artifacts |

## What stays out (for now, by design)

3D/spatial library, cloud providers, cheat database, achievements,
metadata/artwork service, account sync — all have reserved seams
(`SaveSyncProvider`, `execution`, per-game `coreId`/cheat counts),
none is implemented ahead of need.

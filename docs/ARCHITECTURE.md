# ezCORE Architecture

> **Version:** 3.0 — rewritten against the shipping code (v0.1.0)
> **Stack:** Flutter/Dart (UI) · C11 runtime, ABI v1 (no external deps) ·
> libretro cores (C/C++)

---

## The whole picture

```
┌───────────────────────────────────────────────────────────────┐
│                     Flutter UI  (Dart)                        │
│  Orbit console: screens · theme (final-01) · widgets          │
│  AppState (ChangeNotifier) · services · player controller     │
│  Import via system picker → hash-identify → library           │
└──────────────────────────┬────────────────────────────────────┘
                           │ dart:ffi  (lib/runtime/ezcore_runtime.dart)
┌──────────────────────────▼────────────────────────────────────┐
│                ezCore Runtime  (C11, ABI v1)                  │
│  runtime/src/runtime.c        session lifecycle · frame loop  │
│  runtime/src/dynload_*.c      dlopen / LoadLibrary seam       │
│  AV buffers · input · save states · SRAM handoff · cheats     │
│  Exports: runtime/include/ezcore_runtime.h                    │
└──────────────────────────┬────────────────────────────────────┘
                           │ libretro C API
┌──────────────────────────▼────────────────────────────────────┐
│                    Modular cores (C/C++)                      │
│  cores/<id>/manifest.json     metadata · pins · policy        │
│  staged artifact (dylib/so/dll) sha256-verified vs manifest   │
│  delivered: bundled | on-demand, sha256-verified (ADR-013)     │
└───────────────────────────────────────────────────────────────┘
```

The runtime has **no external library dependencies** — the only headers it
uses beyond the C standard library are the vendored `libretro-common`
headers (`scripts/build_core.sh --fetch-headers`), and its CMake build fails
loudly if they are missing.

---

## Rules

1. **Cores never touch Flutter.** Every core speaks the runtime ABI
   (`runtime/include/ezcore_runtime.h`, versioned `EZCORE_ABI_VERSION`).
   A core that satisfies the ABI works on every platform unchanged.

2. **The runtime owns execution.** Lifecycle, game loading, frame
   execution, video/audio plumbing, input, save states, cheats,
   host directories, and core quirks live in `runtime/src/`.
   The frontend drives sessions and renders frames — nothing else.

3. **Platform execution strategy lives in data, not code.**
   Each core manifest declares `execution`: per-OS `interpreter` or
   `dynarec` (`unknown` when undeclared). iOS must never resolve to
   dynarec — enforced by manifest validation. The Flutter layer never
   branches on JIT capability.

4. **Save bytes are opaque.** `ezcore_serialize` produces bytes the
   frontend never interprets. `lib/state/save_sync.dart` defines the
   `SaveSyncProvider` seam: `MemorySaveSyncProvider` (tests),
   `LocalSaveSyncProvider` (the Time Capsule vault — the v1 default),
   and future cloud providers implement the same methods.

5. **Game → Play.** The library resolves a game to a core
   (`CoreRegistry.compatibleCores`); when the user never picked one,
   the first compatible installed core is used and remembered.
   No core/renderer/BIOS thinking required.

6. **C ABI boundary, verified before load.** The runtime is C11 and
   exports a pure C ABI; Dart's FFI binds to it. Desktop/Android load
   cores through the dynload seam only after the artifact's sha256 is
   verified against the manifest pin. iOS ships cores as frameworks
   embedded at build time and never downloads anything.

---

## Layer map

| Layer | Dir | Language | Owns |
|---|---|---|---|
| UI | `lib/screens`, `lib/theme`, `lib/widgets` | Dart | Library, systems, player chrome, vault, settings, import |
| State | `lib/state` | Dart | `AppState` (ChangeNotifier), `SaveSyncProvider` seam |
| Catalog | `lib/models`, `lib/cores` | Dart | Manifests, add/remove/update bookkeeping, cheat formats |
| Emulation | `lib/emu` | Dart | `EmulationService` + worker, player controller, PCM sinks |
| Services | `lib/services` | Dart | Import, discovery, sha256, BIOS check, dirs, gamepads, covers |
| FFI | `lib/runtime/ezcore_runtime.dart` | Dart | Dependency-free bindings over the C ABI |
| Runtime | `runtime/` | C11 | Session lifecycle, AV plumbing, cheats, saves, quirks |
| Cores | `cores/<id>/manifest.json`, staged artifacts | C/C++ | Versioned plugins, sha-pinned builds |

## Runtime structure (as built)

```
runtime/
├── CMakeLists.txt              # C11, no external deps
├── include/
│   └── ezcore_runtime.h        # C ABI v1 (the contract)
├── src/
│   ├── runtime.c               # session, frame loop, AV, cheats, saves
│   ├── dynload.h               # one seam, two implementations
│   ├── dynload_posix.c         # dlopen / dlsym
│   └── dynload_win32.c         # LoadLibrary / GetProcAddress
└── test/
    ├── test_abi.c              # ABI surface checks
    ├── test_load.c             # load/init/unload
    ├── test_core_boot.c        # fork()-isolated core boot (synth core)
    ├── test_core_player.c      # frames + audio + saves against synth core
    └── synth_core/             # deterministic synthetic libretro core
```

CTest runs the native suite (`cd runtime/build-<platform> && ctest`); the
synthetic core means boot/player tests need no game content. Per-core boot
tests fork() a child so a native crash can't take down the harness.

## Cores: manifests and pins

- `cores/<id>/manifest.json` — id, version, license + license URL,
  upstream, systems, extensions, cheat support, BIOS requirements,
  `delivery` (bundled in v1), `execution` policy per OS, artifact sha256
  pins per platform.
- `cores/catalog.json` — merged index the app loads as an asset
  (`scripts/build_catalog.py`; nested per-core manifest assets are not
  reliably bundled by Flutter, so the catalog is the single source).
- Staged artifacts live in `native/` (gitignored) and are produced by
  `scripts/build_core.sh`; `scripts/pin_artifacts.py --check` verifies the
  staged set matches the committed pins before any release.
- Hold manifests (`cores/*_hold/`) are manifests without build recipes —
  reserved slots that never build and never ship.

## Build system

CMake (runtime) + shell/Python scripts (cores, catalog, pins, release) +
the Flutter toolchain. There is no package manager involved beyond
Homebrew (macOS) / distro packages (Linux) / MSYS2 (Windows) for
compilers and headers.

```
scripts/
├── prereqs.sh            # macOS toolchain install
├── build_core.sh         # fetch headers, build single core or tiers
├── build_runtime.sh      # per-platform runtime + CTest
├── build_catalog.py      # merge manifests → cores/catalog.json
├── pin_artifacts.py      # record/verify sha256 pins
├── fill_manifest_data.py # policy maps (execution/delivery/cheats)
├── core_platform.sh      # per-core build recipes
└── release.sh            # assemble a shippable release per platform
```

## What stays out (by design, for now)

Cloud sync, achievements, metadata/artwork services, account sync,
netplay, rewind, per-game core options (ABI v2) — all have reserved seams
(`SaveSyncProvider`, `execution`, per-game `coreId`), none is implemented
ahead of need. See `docs/RELEASE_PLAN.md` for what v1 deliberately
excludes and why.

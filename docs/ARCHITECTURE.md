# ezCore Architecture

> **Version:** 2.0
> **Date:** 2026-09-16
> **Stack:** C++ (runtime) + Flutter/Dart (UI) + C/C++ (libretro cores)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        Flutter UI (Dart)                     │
│  3D rendering (Flutter 3D / custom shaders)                  │
│  State management (Riverpod)                                 │
│  Cloud sync client                                           │
│  Auto-scan / auto-cheat engine                               │
└──────────────────────────┬──────────────────────────────────┘
                           │ dart:ffi
┌──────────────────────────▼──────────────────────────────────┐
│                   C++ Runtime (ezcore_runtime)                │
│  Session lifecycle  │  AV plumbing  │  Input  │  Saves       │
│  Core loader (dlopen/dlsym)  │  Cheat engine                 │
│  Cloud sync bridge  │  Auto-scan bridge                      │
│  Exports C ABI (ezcore_runtime.h)                           │
└──────────────────────────┬──────────────────────────────────┘
                           │ C ABI
┌──────────────────────────▼──────────────────────────────────┐
│                    Modular Cores (C/C++)                      │
│  cores/<id>/manifest.json  │  cores/<id>/libretro_core.so     │
│  Versioned, sha-pinned, sandboxed                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Rules

1. **Cores never touch Flutter.** Every core speaks the runtime ABI
   (`runtime/include/ezcore_runtime.h`, versioned `EZCORE_ABI_VERSION`).
   A core that satisfies the ABI works on every platform unchanged.

2. **The runtime owns execution.** Lifecycle, game loading, frame
   execution, video/audio plumbing, input, save states, cheats,
   host directories, and core quirks live in `runtime/src/`.
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

6. **C++ runtime, C ABI boundary.** The runtime is written in C++ but
   exports a pure C ABI (`ezcore_runtime.h`). Dart's FFI binds to the
   C ABI — it never sees C++ types. This keeps the boundary simple
   and portable.

---

## Layer Map

| Layer | Dir | Language | Owns |
|---|---|---|---|
| UI | `lib/screens`, `lib/theme` | Dart | Library, player chrome, settings, import |
| State | `lib/state` | Dart | `AppState`, `SaveSyncProvider` seam |
| Core catalog | `lib/models`, `lib/cores` | Dart | Manifests, install/update/remove, cheat formats |
| FFI | `lib/runtime/ezcore_runtime.dart` | Dart | Zero-dep Dart bindings over the C ABI |
| Runtime | `runtime/` | C++ | Session lifecycle, AV plumbing, cheats, saves, quirks |
| Cores | `cores/<id>/manifest.json`, `native/` | C/C++ | Versioned plugins, sha-pinned artifacts |

---

## C++ Runtime Structure

```
runtime/
├── CMakeLists.txt
├── include/
│   └── ezcore_runtime.h       # C ABI header (the contract)
├── src/
│   ├── runtime.cpp            # Main runtime, C ABI exports
│   ├── session.cpp            # Session management (ezcore_session)
│   ├── session.hpp
│   ├── audio.cpp              # Audio ring buffer
│   ├── audio.hpp
│   ├── video.cpp              # Frame buffer management
│   ├── video.hpp
│   ├── input.cpp              # Input handling
│   ├── input.hpp
│   ├── saves.cpp              # Save state management
│   ├── saves.hpp
│   ├── cheats.cpp             # Cheat engine
│   ├── cheats.hpp
│   ├── core_loader.cpp        # dlopen/dlsym wrapper
│   ├── core_loader.hpp
│   └── cloud_bridge.cpp       # Cloud sync bridge
│   └── cloud_bridge.hpp
└── test/
    ├── test_session.cpp
    ├── test_audio.cpp
    ├── test_saves.cpp
    └── test_cheats.cpp
```

### C++ Design Principles

- **RAII everywhere** — no raw `new`/`delete` in application code
- **Smart pointers** — `std::unique_ptr` for ownership, `std::shared_ptr` for shared
- **Error handling** — `std::expected` (C++23) or `Result<T, E>` pattern
- **No exceptions across ABI boundary** — C ABI returns error codes
- **Thread-safe** — audio/video threads use `std::mutex` and `std::atomic`
- **Platform abstraction** — `#ifdef` only in platform-specific files

---

## What stays out (for now, by design)

3D/spatial library, cloud providers, cheat database, achievements,
metadata/artwork service, account sync — all have reserved seams
(`SaveSyncProvider`, `execution`, per-game `coreId`/cheat counts),
none is implemented ahead of need.

---

## Build System

```
CMake (top-level)
├── runtime/           # C++ runtime → libezcore_runtime.so/dylib/dll
├── cores/<id>/        # Individual core builds
├── flutter/           # Flutter project
└── platform/          # Platform-specific configs
    ├── windows/
    ├── macos/
    ├── linux/
    ├── android/
    └── ios/
```

Package management: **vcpkg** (desktop) + **Conan** (mobile)

---

## Migration from C to C++

The existing `runtime/src/runtime.c` is functional and tested. The
migration to C++ is incremental:

1. **Phase 1:** Create C++ project structure, CMake build
2. **Phase 2:** Port `runtime.c` → `runtime.cpp` function by function
3. **Phase 3:** Add C++ features (RAII, smart pointers, error handling)
4. **Phase 4:** Delete `runtime.c`, keep only C++ implementation

The C ABI (`ezcore_runtime.h`) remains unchanged throughout — Dart
FFI bindings don't need to be rewritten.

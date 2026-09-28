# ezCORE Architecture State

> Snapshot date: 2026-09-25
> This file describes the current implementation, not the long-term wish list.
> Detailed as-built documentation remains in
> [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md).

## Current layer map

```text
Flutter UI / Orbit screens
        ↓ Dart services and AppState
Application state + local persistence
        ↓ isolate message boundary
Emulation worker / player controller
        ↓ dart:ffi
C11 ezCORE runtime (ABI v1)
        ↓ libretro C API / dynamic loader
Pinned modular core artifacts
```

## Implemented

### UI

- `lib/main.dart` and `lib/screens/` implement the Orbit shell, Library,
  Systems, Time Capsule, Player, Settings, Import, game detail, and cheats
  surfaces.
- `lib/theme/tokens.dart` and `lib/widgets/` provide the current visual system.
- `lib/theme/layout.dart` centralizes five responsive layout families for the
  shell and screens. Desktop and phone use the cover flow; both tablet
  orientations retain the Continue/Recently Added hub. Platform-specific
  visual verification remains separate from this source-level contract.
- Responsive portrait/landscape branches exist; platform-specific visual
  verification is not complete.

### Application state and services

- `lib/state/app_state.dart` owns games, selected core IDs, cheats, settings,
  catalog state, watched folders, and persistence coordination.
- `lib/services/persistence_service.dart` stores a versioned JSON snapshot with
  serialized atomic temp-file + rename writes.
- `lib/services/content_importer.dart` and `rom_validator.dart` provide
  user-owned content import, extension matching, plausibility checks, and
  SHA-256 deduplication.
- `lib/services/core_registry.dart`, `core_discovery.dart`,
  `core_staging.dart`, `core_path_resolver.dart`, and `core_downloader.dart`
  isolate core bookkeeping, staging, verification, and hybrid delivery.
- `lib/services/bios_check.dart` checks manifest-declared firmware files and
  produces user-facing guidance.
- `lib/services/gamepad.dart` normalizes physical input; platform adapters are
  separated for Windows and Linux, with mobile/Apple channel seams.
- `lib/services/runtime_loader.dart` and `native_dirs.dart` resolve the
  runtime without crossing a `DynamicLibrary` handle between isolates.

### Emulation

- `lib/emu/emulation_worker.dart` owns the native session in an isolate.
- `lib/emu/emulation_service.dart` wraps the ABI and cleans up failed starts.
- `lib/emu/player_controller.dart` schedules bounded frame requests, decodes
  RGBA frames, handles pause/close, and forwards input.
- `lib/emu/pcm_*.dart` and platform runners provide PCM output seams.
- `lib/screens/player_screen.dart` wires content, verified core selection, BIOS
  gating, saves, screenshots, cheats, touch input, and lifecycle handling.

### Runtime and cores

- `runtime/include/ezcore_runtime.h` defines ABI v1.
- `runtime/src/runtime.c` adapts libretro callbacks for lifecycle, video,
  audio, input, and optional cheat/save-state entry points.
- `runtime/src/dynload_posix.c` and `dynload_win32.c` isolate dynamic loading.
- Cores are separate, manifest-described libretro artifacts. Manifests carry
  license/provenance, system and extension data, execution policy, delivery,
  BIOS requirements, and artifact pins.
- Desktop giant cores use the on-demand GitHub Release path and are verified
  before staging; iOS is prohibited from downloading executable code.

### Storage

- `state.json`: games, cheats, and flat settings.
- `cores/<id>/`: verified local core artifacts and optimization sidecars.
- `<gameId>/<slot>.bin`: opaque local save-state bytes under the platform
  data directory (the provider receives that directory directly).
- `sram/<gameId>/`: per-game battery-save handoff directory.
- `system/`: user-provided firmware location.
- `art/` and `screenshots/`: local visual assets.

### Configuration

Current configuration is a flat `Map<String, dynamic>` in `AppState.settings`
plus `GameEntry.coreId`. There is no complete global → system → core → game
resolver, typed configuration schema, or portable settings package yet.

### Controller system

The current controller system has a normalized vocabulary and a fixed
RetroPad mapping. It does not yet expose profile objects, per-system/core/game
overrides, custom layouts, analog configuration, or package import/export.

### Theme and graphics systems

Orbit tokens, settings, generated covers, screenshots, and hardware art exist.
There is no installable theme/graphics package format, shader abstraction, or
renderer-independent graphics service.

### Save system

The runtime exposes opaque serialization. `SaveSyncProvider` and
`LocalSaveSyncProvider` provide a local vault seam. Named slots and timestamps
work; thumbnails, history, migration, backup policy, and portable packages are
planned. Battery-save content round trips are not verified for every core.

### Diagnostics and package systems

Manifest validation, pin checks, build scripts, and the core matrix are
implemented. There is no centralized structured diagnostics service and no
general import/export package system for themes, controllers, shaders, mods,
profiles, settings, or saves.

## Planned boundaries

These are architectural targets, not current features:

```text
UI → application services → runtime interfaces → core abstraction → core
```

The intended runtime contract should eventually expose explicit capabilities
(video, audio, saves, battery saves, cheats, rumble, analog, disc swap,
rewind, netplay, shaders, light gun, microphone, camera, and media/BIOS
requirements). Cores must not depend on Flutter, and shared behavior must not
accumulate `if core == ...` branches in the UI.

## Platform boundaries

- Flutter is the shared UI layer.
- Dart services hide filesystem, hashing, input, audio, and platform channels.
- C11 owns emulation execution and the ABI boundary.
- Native cores remain isolated behind manifests and the runtime.
- Android/iOS use method-channel native directory/runtime seams; desktop uses
  bundle and dev-checkout path resolution.
- Platform verification is recorded in [`CORE_MATRIX.md`](CORE_MATRIX.md) and
  [`../docs/MATRIX.md`](../docs/MATRIX.md).

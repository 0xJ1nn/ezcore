# ezCORE Modular Core System

> **Version:** 2.0 — rewritten to the shipping system (v1, bundled delivery)
> **Date:** 2026-09-19
> **Status:** Current

---

## Overview

ezCORE uses a **modular core architecture** — every emulated system is a
separate libretro binary (C/C++) behind a small stable C ABI. Cores are
versioned, license-tagged, and **sha256-pinned** in per-core manifests.

**v1 delivery is `bundled`:** cores ship inside the app bundle (desktop,
Android) or as embedded frameworks (iOS) and update together with app
releases. There is **no core-download infrastructure in v1** — nothing is
fetched at runtime, and iOS never downloads anything by policy (App Review
2.5.2/4.7). A download/store path is a possible later addition, not a v1
feature.

Why modular still matters: each core keeps its own upstream license, a core
update can't silently change the runtime ABI, and a crashed or unfinished
core can simply not ship.

---

## Core structure

Each core is a manifest + a staged artifact:

```
cores/<id>/manifest.json      # metadata, pins, policy (committed)
native/cores*/<id>/<lib>      # staged artifact (gitignored, built by scripts)
```

```json
{
  "id": "mgba",
  "name": "mGBA",
  "version": "0.11-dev",
  "license": "MPL-2.0",
  "license_url": "https://github.com/mgba-emu/mgba/blob/master/LICENSE",
  "homepage": "https://mgba.io",
  "upstream": "libretro/mgba",
  "systems": ["gba", "gb", "gbc"],
  "extensions": ["gba", "gb", "gbc", "zip"],
  "cheats_supported": true,
  "cheat_families": ["gba_actionreplay", "gba_codebreaker", "gba_gameshark", "gb_gameshark"],
  "bios_required": false,
  "bios_files": [],
  "delivery": { "macos": "bundled", "windows": "bundled", "linux": "bundled",
                "android": "bundled", "ios": "absent" },
  "artifacts": { "macos-arm64": "8a256a…" },
  "execution": { "macos": "dynarec", "windows": "dynarec", "linux": "dynarec",
                 "android": "dynarec", "ios": "interpreter" }
}
```

### Manifest fields

| Field | Type | Meaning |
|---|---|---|
| `id` | string | Unique core identifier |
| `name` / `version` | string | Display name, upstream version |
| `license` / `license_url` | string | Upstream license (surfaced in-app per core) |
| `homepage` / `upstream` | string | Source of truth for the recipe |
| `systems` | string[] | System short codes this core serves |
| `extensions` | string[] | Import extensions it can open |
| `cheats_supported`, `cheat_families` | bool / string[] | Cheat engine surface |
| `bios_required`, `bios_files` | bool / string[] | Exact firmware filenames the player gates on |
| `delivery` | object | Per-OS delivery: `bundled` (or `absent`/hold states) |
| `artifacts` | object | Per-platform **sha256 pins** of the staged artifact |
| `execution` | object | Per-OS strategy: `interpreter` or `dynarec` |

### Execution modes

| Mode | Meaning | iOS allowed? |
|---|---|---|
| `dynarec` | Dynamic recompilation (JIT) — fastest | ❌ Never |
| `interpreter` | Interpreted — slower, safe everywhere | ✅ Yes |

**iOS rule:** manifests declaring `dynarec` for iOS are rejected by
validation; the iOS tier only builds interpreter-safe cores.

---

## Loading flow (desktop / Android)

```
game selected in Library
   ↓  CoreRegistry.compatibleCores(extension) — installed cores only
   ↓  core path resolved (bundled dir; macOS sandbox via bookmarks)
   ↓  artifact sha256 verified against the manifest pin
   ↓  ezcore_load()  → dynload seam (dlopen / LoadLibrary, RTLD_LOCAL)
   ↓  ABI version checked (must be 1) → libretro symbols resolved
   ↓  ezcore_init() → environment, video, audio, input callbacks
   ↓  ezcore_load_game() → ezcore_run_frame() loop
```

If no compatible core is installed, the app says so — it never fetches one
(v1 has no download path). The player gates BIOS-dependent cores on an
exact-file check before boot (`lib/services/bios_check.dart`).

## Core registry (app-side bookkeeping)

`lib/cores/core_registry.dart` is pure logic (unit-testable, never touches
native code):

- `loadCatalog(...)` — parse + validate the merged catalog
- `install(m, expectedSha256:)` — marks a core added **only if** the given
  artifact hash is pinned in its manifest; blocked cores always throw
- `remove(id)` — removes; games and saves are kept
- `statusOf(m)` — `notInstalled` / `installed` / `updateAvailable` / `blocked`
- `compatibleCores(extension)` — the Game → Play resolver

## Catalog loading

The app reads one merged asset, `cores/catalog.json`
(`scripts/build_catalog.py`), instead of per-core manifest assets — Flutter's
asset bundler doesn't reliably copy nested `cores/<id>/` subdirectories into
app bundles. The catalog is committed and regenerated whenever manifests
change; `fill_manifest_data.py --check` keeps policy fields consistent.

## Bundling per platform

| Platform | How cores ship | Notes |
|---|---|---|
| macOS | `ezCore.app/Contents/Resources/ezcore/cores/` | runtime dylib in `Contents/Frameworks/` |
| Windows / Linux | `cores/` next to the executable | release zip / tarball |
| Android | `jniLibs/arm64-v8a/` in the APK | flat `.so` names, loaded by absolute path |
| iOS | embedded frameworks (build-time) | never downloaded |

`scripts/pin_artifacts.py --check` refuses to assemble a release when the
staged artifacts don't match the committed pins.

## Sandboxing & safety

Cores run **in-process** (a libretro requirement) with these boundaries:

| Boundary | Mechanism |
|---|---|
| Symbol isolation | `RTLD_LOCAL` — core symbols don't leak into the process namespace |
| File access | Host dirs handed to the core explicitly (`ezcore_set_dirs`): system + per-game save dirs |
| Network | Cores are built without network code paths; the app ships no network permissions (Android manifest: `VIBRATE` only) |
| Integrity | Artifact sha256 checked against the manifest pin before load |
| Crash containment | Harness tests fork() per core so a native crash can't kill the test VM; in-app crash isolation is post-v1 |

## Supported systems (as verified)

The authoritative per-system × platform status is
[`docs/MATRIX.md`](MATRIX.md). Summary of the desktop set:

GB/GBC · GBA · NES/FDS · SNES · Genesis/SMS/GG/SG-1000 · Atari 2600 · DOS ·
PC Engine/TG-16 · PS1 · N64 · DS · PSP · Dreamcast · GameCube/Wii (desktop) ·
Saturn · Arcade/Neo Geo (gated) · ScummVM (pending macOS build).

### Core naming map (codename → upstream)

Every core ships under an ezCORE-owned codename; the upstream project is
credited by name wherever the core appears (repo description, core README,
`THIRD_PARTY_NOTICES.md`). See ADR-012 in [`docs/DECISIONS.md`](DECISIONS.md).

| Codename | System | Upstream project | Upstream licence |
|---|---|---|---|
| NesByte | NES / FDS | Mesen (libretro/Mesen) | GPL-3.0-or-later |
| PocketBit | GB / GBC | SameBoy (LIJI32/SameBoy) | Expat (MIT) |
| ColorBit | GBC | ezCORE first-party (fresh-written) | GPL-3.0 (ours) |
| AdvanceBit | GBA | mGBA (libretro/mgba) | MPL-2.0 |
| SuperFX | SNES | Snes9x (snes9xgit/snes9x) | Snes9x custom (non-commercial) — recipe only |
| BlastProc | Genesis/SMS/GG/SG-1000 | Genesis Plus GX (libretro/Genesis-Plus-GX) | custom non-commercial — recipe only |
| Joystick | Atari 2600 | Stella (libretro/stella2023) | GPL-2.0-or-later |
| CardCon | PC Engine / TG-16 | Beetle PCE Fast (libretro/beetle-pce-fast-libretro) | GPL-2.0-or-later |
| TwinSH | Saturn | Beetle Saturn (libretro/beetle-saturn-libretro) | GPL-2.0-or-later |
| Geometry1 | PS1 | SwanStation (libretro/swanstation) | GPL-3.0 |
| RCP64 | N64 | Mupen64Plus-Next (libretro/mupen64plus-libretro-nx) | GPL-2.0-or-later |
| DualScreen | DS | melonDS (libretro/melonDS) | GPL-3.0 |
| PortComp | PSP | PPSSPP (hrydgard/ppsspp) | GPL-2.0-or-later |
| DreamArc | Dreamcast / NAOMI | Flycast (flyinghead/flycast) | GPL-2.0-or-later |
| PowerCube | GameCube / Wii | Dolphin (libretro/dolphin) | GPL-2.0-or-later |
| CoinBox | Arcade / Neo Geo | FinalBurn Neo (libretro/FBNeo) | FBNeo custom (non-commercial) — recipe only |
| RealMode | DOS | DOSBox Pure (libretro/dosbox-pure) | GPL-2.0-or-later |
| PointClick | SCUMM / adventure | ScummVM (scummvm/scummvm) | GPL-3.0-or-later |

"Recipe only" cores are never distributed as binaries — their upstream
licence is non-commercial. The repository verifies the build recipe in CI
and publishes nothing.

### Holds (never built, never shipped)

| System | Status |
|---|---|
| Switch | Hold — upstream projects fell to Nintendo's 2024 anti-circumvention actions |
| 3DS | Hold — same |
| PS2 | Hold — no shippable open libretro core exists |

Hold manifests live in `cores/*_hold/manifest.json`; validation refuses
blocked cores that carry artifacts.

## Adding a core (contributors)

1. **Verify licensing**: open-source libretro core, compatible license, no
   Nintendo/Sony/Sega IP, no DMCA §1201 exposure.
2. **Add the manifest**: `cores/<id>/manifest.json` (see schema above).
3. **Add the build recipe**: `scripts/core_platform.sh` — `build_<id>()`.
4. **Build + prove it**: `scripts/build_core.sh <id>`, then the Dart matrix
   (`flutter test test/core_matrix_test.dart`) — at least IDENTIFIES.
5. **Pin artifacts**: `scripts/pin_artifacts.py <platform> --out native/cores`.
6. **Policy maps**: `scripts/fill_manifest_data.py` (execution/delivery/cheats).
7. **Regenerate catalog**: `python3 scripts/build_catalog.py`.
8. **PR with**: manifest diff, catalog diff, pin evidence, test output.

Submission rules: libretro API, valid manifest, pins for every shipped
platform, no proprietary firmware requirement, no Switch/3DS/PS2.

## Security

- **Pins are evidence, never aspirational** — `pin_artifacts.py` refuses
  blocked cores and missing hashes; releases assemble only from verified
  staged sets.
- **Manifest validation** rejects: missing id/name/version/license/systems,
  missing extensions (unless blocked), `ios: download` delivery, iOS
  `dynarec`, blocked cores with artifacts.
- **`dlopen` with `RTLD_LOCAL`** so core symbols can't collide with the
  process or other cores.

## Future (not v1)

A core download/store path, per-game core options (ABI v2), out-of-process
crash isolation, and rewind all have reserved seams but no implementation
yet — see [`docs/RELEASE_PLAN.md`](RELEASE_PLAN.md).

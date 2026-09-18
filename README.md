# ezCORE

[![Build Status](https://github.com/JinUltimate1995/ezcore/actions/workflows/ci.yml/badge.svg)](https://github.com/JinUltimate1995/ezcore/actions/workflows/ci.yml)
[![Matrix Build](https://github.com/JinUltimate1995/ezcore/actions/workflows/matrix.yml/badge.svg)](https://github.com/JinUltimate1995/ezcore/actions/workflows/matrix.yml)
[![License: GPL-3.0-only](https://img.shields.io/badge/License-GPL--3.0--only-blue.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS%20(arm64)-lightgrey.svg)](docs/INSTALL.md)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows%20(x64)-lightgrey.svg)](docs/INSTALL.md)
[![Platform: Linux](https://img.shields.io/badge/platform-Linux%20(x64)-lightgrey.svg)](docs/INSTALL.md)
[![Platform: Android](https://img.shields.io/badge/platform-Android%20(arm64)-green.svg)](docs/INSTALL.md)
[![iOS: TestFlight](https://img.shields.io/badge/iOS-TestFlight%20only-lightgrey.svg)](docs/RELEASE_PLAN.md)
[![Core Matrix](https://img.shields.io/badge/core%20matrix-docs%2FMATRIX.md-blue.svg)](docs/MATRIX.md)
[![Release Plan](https://img.shields.io/badge/release%20plan-docs%2FRELEASE__PLAN.md-orange.svg)](docs/RELEASE_PLAN.md)

One beautiful, unified emulator for as many systems as realistically possible. **Game → Play** — pick a game and play; cores, saves and cheats stay out of the way. (Bring your own BIOS dumps where a core needs them — the app tells you exactly which file is missing and where it goes.)

Open-source frontend for macOS, Windows, Linux, iOS and Android. Modular, replaceable emulator cores behind a small stable C ABI. Full cheat support. Zero bundled games, BIOS, keys, or cheat databases.

```
Flutter UI → C ABI / FFI → ezCore Runtime → modular libretro cores
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the layer rules and [`docs/MATRIX.md`](docs/MATRIX.md) for per-system verified status on each platform.

## ⚠️ First Release Notice

**This is v0.1.0 — an early public release. Things may not work as expected.**

- Some cores are verified only on macOS (see [MATRIX.md](docs/MATRIX.md))
- Windows/Linux/Android builds are from CI; limited local verification
- iOS is TestFlight-only (no GitHub Release artifact)
- Known issues: typed folder import in macOS sandbox, some GL cores need core options (ABI v2)
- **Found a bug?** [Open an issue](../../issues/new/choose) — use the bug template
- **Want a feature?** [Open a feature request](../../issues/new/choose) — use the feature template
- **Want to help?** [Contributing](CONTRIBUTING.md) — PRs welcome!

## Bring Your Own Dumps

This app plays **only** files you supply yourself. It ships no ROMs, BIOS/firmware, decryption keys, game art, or cheat databases, and links to none. See [`TRADEMARKS.md`](TRADEMARKS.md), [`DMCA.md`](DMCA.md), [`CONTRIBUTING.md`](CONTRIBUTING.md).

ezCORE is a standalone product, unrelated to any other brand.

## Interface (Orbit Console)

Four spaces, one viewport budget — no page scroll, only rails scroll:

- **Library** — CoverFlow browser + bottom game dock (or grid view), collection strip (Time Capsule → Favorites → All Systems → per core), search (`/`), keyboard browse (`←→`, `↵` for details, `1–4` to switch space). Game hub: core picker, Play, cheats, snapshot slots (resume & load).
- **Systems** — 3D core browser with per-hardware silhouettes + bottom core dock (All / Added / Available), sha-pinned install, remove (games & saves kept), per-core licenses.
- **Time Capsule** — local save-snapshot vault across every game; tapping a snapshot resumes the game and loads it.
- **Player** — verified-core launch, worker frames, pause, quick-save, fast-forward speed, screenshot (also pinned as the game's cover), touch pad with haptics, live cheats, slot save/load, reset, Take-a-breather session overlay with autosave.
- **Settings** — six local-preference tabs (Appearance, Emulation, Controllers, Audio, Library & Storage, About). Every control does something; nothing leaves the device.

Landscape ≥700px docks navigation to a left command rail; portrait uses a top command dock. Dark only: near-black `#0A0A0A`, electric blue `#007BFF`, silver-white `#DDE6F4`. Display type Space Grotesk, body Manrope — both bundled offline under `assets/fonts` (SIL OFL 1.1, see `assets/fonts/README.md`).

No game art ships with the app: every import gets a deterministic generative cover in the app identity, and player screenshots are pinned as that game's cover automatically. Hardware cards use the finalized per-system silhouette artwork.

Cheats apply live: stored codes push into the running session on toggle/add/import (reset-first, rejected indices reported), and at boot otherwise.

## Quick Links

| Document | Description |
|----------|-------------|
| [`docs/INSTALL.md`](docs/INSTALL.md) | User installation guide (all platforms) |
| [`docs/BUILDING.md`](docs/BUILDING.md) | Developer build guide (from source) |
| [`docs/MATRIX.md`](docs/MATRIX.md) | Core × Platform verification matrix |
| [`docs/RELEASE_PLAN.md`](docs/RELEASE_PLAN.md) | v1 release checklist and status |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Layer rules, ABI, data flow |
| [`docs/CORE_SYSTEM.md`](docs/CORE_SYSTEM.md) | Core plugin system deep dive |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Contribution rules (hard + normal) |
| [`SECURITY.md`](SECURITY.md) | Vulnerability reporting |
| [`SUPPORT.md`](SUPPORT.md) | FAQ, support channels |

## Quick Start (macOS Dev)

```bash
git clone https://github.com/JinUltimate1995/ezcore.git
cd ezcore
scripts/prereqs.sh                      # one-shot toolchain (macOS/arm64)
scripts/build_core.sh --fetch-headers   # vendor libretro.h
scripts/build_runtime.sh macos          # runtime + CTest (4/4)
scripts/build_core.sh --tier1           # run-verified cores
python3 scripts/build_catalog.py        # merge manifests (required asset)
flutter analyze && flutter test         # gates (incl. core matrix)
python3 scripts/pin_artifacts.py macos-arm64 --out native/cores --check
flutter run -d macos                    # run shell
```

Core artifacts are verified (sha256 vs manifest pin) before `dlopen`. iOS cores are bundled at build time only — never downloaded (App Review 2.5.2/4.7).

## Systems at Launch Scope

GB/GBC (SameBoy, Gambatte) · GBA (mGBA) · NES (Mesen) · SNES (Snes9x) · Genesis/SMS/GG (Genesis Plus GX) · Atari 2600 (Stella) · DOS (DOSBox Pure) · TG-16 (Beetle PCE) · PS1 (SwanStation) · N64 (Mupen64Plus) · DS (melonDS) · PSP (PPSSPP) · Dreamcast (Flycast) · GameCube/Wii (Dolphin, desktop/Android) · Saturn (Beetle Saturn) · Arcade (FBNeo, gated) · ScummVM.

Scope is intent; [`docs/MATRIX.md`](docs/MATRIX.md) records what is actually verified per system per platform (built → pinned → identifies → renders → shipped).

**Legal holds (reserved slots, never built):** 3DS, Switch, PS2. Reasons live in `cores/*_hold/manifest.json`. In short: Citra/Yuzu fell to Nintendo's 2024 anti-circumvention actions, and no shippable open PS2 libretro core exists. This protects the project and its users.

## Layout

```
lib/                    # Orbit shell, screens, widgets, services, theme, FFI
assets/fonts/           # Space Grotesk + Manrope (OFL 1.1)
assets/branding/        # App icon, lockups
runtime/                # ezCore native runtime (C99, ABI v1)
cores/                  # Per-core manifest.json + registry.json
scripts/                # Build, pin, catalog, release automation
test/                   # Dart tests (unit + integration)
integration_test/       # Flutter integration tests
design/ezcore-orbit/    # Brand system + Playwright verification (36-state)
docs/                   # All documentation
```

## License

App shell: GPL-3.0-only ([`LICENSE`](LICENSE)). Each core keeps its upstream license — see `cores/<id>/manifest.json` (`license`, `license_url`).

## Brand Protection

**The ezCORE name, logo, and brand assets are trademarked and NOT licensed for reuse.** See [`TRADEMARKS.md`](TRADEMARKS.md) for details.

- Code: GPL-3.0 — fork, modify, build freely
- Brand: **All Rights Reserved** — only official maintainer may publish "ezCORE" to app stores
- Forks must use different name, icon, and bundle ID

## Support & Community

- [GitHub Discussions](../../discussions) — questions, ideas, community help
- [GitHub Issues](../../issues) — bugs, feature requests (use templates)
- [Security Advisories](../../security/advisories) — vulnerability reporting
- [SUPPORT.md](SUPPORT.md) — detailed FAQ
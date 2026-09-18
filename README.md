<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/branding/lockup-light.png">
    <source media="(prefers-color-scheme: light)" srcset="assets/branding/lockup-dark.png">
    <img alt="ezCORE" src="assets/branding/lockup-dark.png" width="380">
  </picture>
</p>

<p align="center">
  <strong>One beautiful, unified emulator.</strong><br>
  <em>Game → Play</em> — pick a game and play; cores, saves and cheats stay out of the way.
</p>

<p align="center">
  <a href="https://github.com/JinUltimate1995/ezcore/actions/workflows/ci.yml"><img alt="ci" src="https://github.com/JinUltimate1995/ezcore/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/JinUltimate1995/ezcore/releases"><img alt="release" src="https://img.shields.io/github/v/release/JinUltimate1995/ezcore?include_prereleases&color=007BFF"></a>
  <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-GPL--3.0--only-blue"></a>
  <a href="docs/MATRIX.md"><img alt="core matrix" src="https://img.shields.io/badge/core%20matrix-docs%2FMATRIX.md-informational"></a>
  <img alt="macOS arm64" src="https://img.shields.io/badge/macOS-arm64-success">
  <img alt="Android arm64" src="https://img.shields.io/badge/Android-arm64-success">
  <img alt="Windows · Linux · iOS" src="https://img.shields.io/badge/Windows%20·%20Linux%20·%20iOS-from%20source-lightgrey">
</p>

An open-source frontend for your own game dumps: modular emulator cores
behind a small stable C ABI, a polished console-style interface, full cheat
support, and local save snapshots. Zero bundled games, BIOS, keys, or cheat
databases — you bring your dumps, ezCORE does the rest.

```
Flutter UI → C ABI / FFI → ezCore Runtime → modular libretro cores
```

## Screens

| Library | Systems |
|:---:|:---:|
| ![Library — your collection](docs/images/library.png) | ![Systems — the core collection](docs/images/systems.png) |
| **Time Capsule** | **Settings** |
| ![Time Capsule — local save snapshots](docs/images/time-capsule.png) | ![Settings — six local tabs](docs/images/settings.png) |

*(Real screenshots of the v0.1.0 build on macOS — not mockups.)*

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the layer rules and
[`docs/MATRIX.md`](docs/MATRIX.md) for per-system verified status on each
platform.

## ⚠️ First release (v0.1.0) — please read

**This is an early public build. Things may not work as expected.** We ship
it because it's already genuinely fun, and because the fastest way to make
it better is in the open.

What we know going in:

- **macOS arm64** is the most verified target: the app runs, imports, plays,
  saves; 17 cores are built and load-and-identify on this machine (3 of them
  are boot-and-render verified with test content — see [MATRIX.md](docs/MATRIX.md)).
- **Android arm64** builds and installs; cores are cross-compiled and
  symbol-verified, but on-device boot verification is still pending a device
  lab.
- **Windows and Linux** have no release binaries yet — the CI matrix that
  builds them is currently paused (GitHub Actions billing on the maintainer
  account), so for now they are build-from-source platforms.
- **iOS** support exists in the codebase (interpreter-only policy enforced
  in manifests) but is not distributed yet — it needs an Apple Developer
  identity. There is no TestFlight, no App Store, no iOS artifact.
- **FBNeo (arcade)** is held from this release: its own manifest requires
  compatibility-allowlist review before shipping.
- **ScummVM** is in the build matrix but not in this release on macOS.

**Found a bug?** [Open an issue](https://github.com/JinUltimate1995/ezcore/issues/new/choose) — the bug template asks for exactly what we need.
**Already fixed it?** PRs are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md).
**Want a feature?** Use the feature template; small and honest beats big and
vague.

## Bring your own dumps

ezCORE plays **only** files you supply yourself. It ships no ROMs,
BIOS/firmware, decryption keys, game art, or cheat databases, and links to
none. Game imports stay where you keep them — the library references your
folders; nothing leaves your device. See [`TRADEMARKS.md`](TRADEMARKS.md),
[`DMCA.md`](DMCA.md), [`CONTRIBUTING.md`](CONTRIBUTING.md).

ezCORE is a standalone product, unrelated to any console maker or publisher.

## Interface (Orbit console)

Four spaces, one viewport budget — no page scroll, only rails scroll:

- **Library** — CoverFlow browser + bottom game dock (or grid view),
  collection strip (All systems → Favorites → per-core), search (`/`),
  keyboard browse (`←→` browse, `↵` details, `1–4` switch space). Game hub:
  core picker, Play, cheats, snapshot slots.
- **Systems** — core browser with per-hardware silhouettes + bottom core
  dock (All / Added / Available). Cores ship inside the app (nothing is
  downloaded); add/remove only changes what's active, and removal keeps your
  games and saves. Per-core license is shown in-app.
- **Time Capsule** — local save-snapshot vault across every game; tapping a
  snapshot resumes the game and loads it.
- **Player** — pause, quick-save, fast-forward, screenshot (pinned as the
  game's cover), touch pad with haptics, live cheats, slot save/load, reset,
  and a "Take a breather" overlay that autosaves on exit.
- **Settings** — six local-preference tabs (Appearance, Emulation,
  Controllers, Audio, Library & storage, About). Every control does
  something; nothing leaves the device.

Landscape ≥700px docks navigation to a left command rail; portrait uses a
top command dock. Dark only: near-black `#0A0A0A`, electric blue `#007BFF`,
silver-white `#DDE6F4`. Display type Space Grotesk, body Manrope — both
bundled offline under `assets/fonts` (SIL OFL 1.1, see
[`assets/fonts/OFL.txt`](assets/fonts/OFL.txt)).

No game art ships with the app: every import gets a deterministic generative
cover in the app identity, and player screenshots can be pinned as that
game's cover.

## Systems & cores

Built and load-verified on macOS arm64 (16 bundled in v0.1.0; FBNeo held,
ScummVM pending its first macOS build):

GB/GBC (SameBoy, Gambatte) · GBA (mGBA) · NES/FDS (Mesen) · SNES (Snes9x) ·
Genesis/SMS/GG/SG-1000 (Genesis Plus GX) · Atari 2600 (Stella) ·
DOS (DOSBox Pure) · TG-16 / PC Engine (Beetle PCE) · PS1 (SwanStation) ·
N64 (Mupen64Plus) · DS (melonDS) · PSP (PPSSPP) · Dreamcast (Flycast) ·
GameCube/Wii (Dolphin, desktop/Android) · Saturn (Beetle Saturn).

Scope is intent; [`docs/MATRIX.md`](docs/MATRIX.md) records what is actually
verified per system per platform (built → pinned → identifies → renders →
shipped). A few cores boot-and-render verified today; the rest load and
identify, with render verification in progress — the matrix is the honest
source.

**Legal holds (reserved slots, never built):** 3DS, Switch, PS2. Reasons live
in `cores/*_hold/manifest.json` — in short: the 3DS/Switch upstreams fell to
Nintendo's 2024 anti-circumvention actions, and no shippable open PS2
libretro core exists. This protects the project and its users.

## Install

| Platform | Artifact | How |
|---|---|---|
| macOS (Apple Silicon) | `ezcore-<version>-macos-arm64.zip` | [Releases](https://github.com/JinUltimate1995/ezcore/releases) → [`docs/INSTALL.md`](docs/INSTALL.md) |
| Android (arm64) | `ezcore-<version>-android-arm64.apk` | [Releases](https://github.com/JinUltimate1995/ezcore/releases) → [`docs/INSTALL.md`](docs/INSTALL.md) |
| Windows / Linux | — | build from source for now (see below) |
| iOS | — | not distributed yet (needs an Apple identity) |

The macOS build is ad-hoc signed (not notarized): first launch needs the
usual `xattr -cr /Applications/ezCore.app` dance — details in
[`docs/INSTALL.md`](docs/INSTALL.md).

## Build from source (macOS quick start)

```bash
git clone https://github.com/JinUltimate1995/ezcore.git
cd ezcore
scripts/prereqs.sh                      # one-shot toolchain (macOS/arm64)
scripts/build_core.sh --fetch-headers   # vendor libretro.h
scripts/build_runtime.sh macos          # runtime + CTest
scripts/build_core.sh --tier1           # first six cores
python3 scripts/build_catalog.py        # merge manifests (required asset)
flutter analyze && flutter test         # gates
flutter run -d macos                    # run the app
```

Full platform matrix, tiers and release assembly:
[`docs/BUILDING.md`](docs/BUILDING.md). Maintainer release checklist:
[`docs/RELEASING.md`](docs/RELEASING.md).

## Documentation

| Document | What's in it |
|---|---|
| [`docs/INSTALL.md`](docs/INSTALL.md) | User install guide (per platform) + BIOS placement |
| [`docs/BUILDING.md`](docs/BUILDING.md) | Developer build guide (all platforms, tiers, gates) |
| [`docs/RELEASING.md`](docs/RELEASING.md) | How releases are cut (local + CI, secrets, checksums) |
| [`docs/MATRIX.md`](docs/MATRIX.md) | Core × platform verification matrix |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Layers, ABI, data flow (as-built) |
| [`docs/CORE_SYSTEM.md`](docs/CORE_SYSTEM.md) | Core plugin system deep dive |
| [`docs/RELEASE_PLAN.md`](docs/RELEASE_PLAN.md) | v1 scope, decisions, what's excluded |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history |
| [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) | Every bundled component + its license |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Contribution rules (hard rules + normal) |
| [`SECURITY.md`](SECURITY.md) · [`SUPPORT.md`](SUPPORT.md) | Vulnerability reporting · FAQ |
| [`TRADEMARKS.md`](TRADEMARKS.md) · [`DMCA.md`](DMCA.md) | Brand policy · takedown policy |

## License & credits

- **App shell + runtime:** GPL-3.0-only ([`LICENSE`](LICENSE)).
- **Emulator cores:** each keeps its upstream license — see
  `cores/<id>/manifest.json` and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
- **Fonts:** Space Grotesk (Florian Karsten) and Manrope (Mikhail Sharanda),
  SIL OFL 1.1.
- **Brand:** the ezCORE name, logo and brand assets are **not** licensed for
  reuse — [`TRADEMARKS.md`](TRADEMARKS.md).

ezCORE stands on the shoulders of the [libretro](https://www.libretro.com/)
ecosystem and the emulator projects behind each core. Thank you.

## Support

- [GitHub Discussions](https://github.com/JinUltimate1995/ezcore/discussions) — questions, ideas, community help
- [GitHub Issues](https://github.com/JinUltimate1995/ezcore/issues) — bugs and feature requests (use the templates)
- [SECURITY.md](SECURITY.md) — vulnerabilities, privately

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/branding/lockup-light.png">
    <source media="(prefers-color-scheme: light)" srcset="assets/branding/lockup-dark.png">
    <img alt="ezCORE" src="assets/branding/lockup-dark.png" width="400">
  </picture>
</p>

<p align="center">
  <strong>One emulator. Every system. No nonsense.</strong><br>
  <em>Pick a game, press play — cores, saves and cheats stay out of the way.</em>
</p>

<p align="center">
  <a href="https://github.com/JinUltimate1995/ezcore/releases"><img alt="Latest Release" src="https://img.shields.io/github/v/release/JinUltimate1995/ezcore?include_prereleases&label=release&color=007BFF&style=flat-square"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-GPL--3.0--only-blue?style=flat-square"></a>
  <a href="https://github.com/JinUltimate1995/ezcore/actions"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/JinUltimate1995/ezcore/ci.yml?branch=main&label=CI&style=flat-square"></a>
  <a href="docs/MATRIX.md"><img alt="Core Matrix" src="https://img.shields.io/badge/core%20matrix-14%20bundled-success?style=flat-square"></a>
  <a href="https://github.com/JinUltimate1995/ezcore/issues"><img alt="Issues" src="https://img.shields.io/github/issues/JinUltimate1995/ezcore?style=flat-square&color=orange"></a>
  <a href="https://github.com/sponsors/JinUltimate1995"><img alt="Sponsor" src="https://img.shields.io/badge/sponsor-%E2%9D%A4-ff69b4?style=flat-square"></a>
</p>

<p align="center">
  <img alt="macOS arm64 — verified" src="https://img.shields.io/badge/macOS%20arm64-verified-brightgreen?style=flat-square">
  <img alt="Android arm64 — builds + staged" src="https://img.shields.io/badge/Android%20arm64-builds%20%2B%20staged-yellow?style=flat-square">
  <img alt="Windows x64 — from source" src="https://img.shields.io/badge/Windows%20x64-from%20source-lightgrey?style=flat-square">
  <img alt="Linux x64 — from source" src="https://img.shields.io/badge/Linux%20x64-from%20source-lightgrey?style=flat-square">
  <img alt="iOS — not distributed yet" src="https://img.shields.io/badge/iOS-not%20distributed%20yet-lightgrey?style=flat-square">
</p>

---

ezCORE is a **free, open-source, multi-system emulator** built on a modular libretro core architecture and a polished console-style UI called **Orbit**. It ships no ROMs, BIOS images, or decryption keys — you bring your own legal dumps. Cheat codes ship built-in (agent-curated and verified to actually work); no ROM content is ever bundled.

```
Flutter UI (Orbit)  →  C ABI / FFI  →  ezCore Runtime (C11)  →  modular libretro cores
```

> **v0.1.1 is an early public build.** Things may not work as expected on every system. macOS arm64 is the most tested target; Android is built and staged but not device-verified yet. Windows and Linux have no binaries yet. Read the [platform status table](#platform-status) before reporting issues.

---

## Screenshots

| Library | Systems |
|:---:|:---:|
| ![Library — CoverFlow browser](docs/images/library.png) | ![Systems — core browser](docs/images/systems.png) |
| **Time Capsule** | **Settings** |
| ![Time Capsule — local save vault](docs/images/time-capsule.png) | ![Settings — six preference tabs](docs/images/settings.png) |

*Real v0.1.1 screenshots on macOS arm64 — not mockups.*

---

## Platform Status

> Honest, point-in-time. [`docs/MATRIX.md`](docs/MATRIX.md) is the canonical source.

| Platform | Binaries | App Verified | Cores Bundled | Notes |
|---|:---:|:---:|:---:|---|
| **macOS arm64** | ✅ [Releases](https://github.com/JinUltimate1995/ezcore/releases) | ✅ launches, Library renders | **14** | Ad-hoc signed (not notarized). First launch needs `xattr -cr /Applications/ezCore.app` — see [`docs/INSTALL.md`](docs/INSTALL.md) |
| **Android arm64** | ✅ [Releases](https://github.com/JinUltimate1995/ezcore/releases) | ⚡ builds + installs | **7** | Core ELFs built + symbol-verified; on-device boot pending device lab |
| **Windows x64** | ❌ not yet | — | — | Build from source; CI matrix being brought up |
| **Linux x64** | ❌ not yet | — | — | Build from source; CI matrix being brought up |
| **iOS arm64** | ❌ not yet | — | — | Code is iOS-ready (interpreter-only policy enforced in manifests); needs an Apple Developer identity to distribute |

---

## Cores & Compatibility

ezCORE uses its own codenames for all cores — upstream engines are credited in the table and in every manifest's `provenance` block. The full rationale is in [`docs/CORE_NAMING.md`](docs/CORE_NAMING.md).

**Verification tiers** (see [`docs/MATRIX.md`](docs/MATRIX.md) for the complete legend):

| Icon | Tier | What it means |
|:---:|---|---|
| 🎮 | **RENDERS** | Boots content, 30 frames confirmed nonzero pixels, save/restore verified |
| ✅ | **IDENTIFIES** | Loads, initialises, and names itself correctly in the test harness |
| 🔨 | **BUILT** | Compiles and links for the target — arch/platform/symbols verified |
| — | — | Not attempted on this platform |

### Bundled Cores

These ship inside the app binary on the platforms marked. "Cheat Engine" means the core exposes the libretro cheat API — codes from the built-in database are applied automatically for these cores.

| System | ezCORE Core | Upstream Engine | macOS | Android | iOS | BIOS? | Cheat Engine |
|---|---|---|:---:|:---:|:---:|:---:|:---:|
| **Game Boy / GBC** | PocketBit | [SameBoy](https://github.com/LIJI32/SameBoy) (MIT) | 🎮 RENDERS | 🔨 BUILT | 🔨 BUILT | No | ✅ GS · GG |
| **Game Boy Advance** | AdvanceBit | [mGBA](https://mgba.io) (MPL-2.0) | 🎮 RENDERS | 🔨 BUILT | — ¹ | No | ✅ AR · CB · GS |
| **NES / FDS** | NesByte | [Mesen](https://github.com/libretro/Mesen) (GPL-3.0+) | ✅ IDENTIFIES | 🔨 BUILT | 🔨 BUILT | No | ✅ Game Genie |
| **PS1** | Geometry1 | [SwanStation](https://github.com/libretro/swanstation) (GPL-3.0) | ✅ IDENTIFIES ² | — | — | **Required** | ✅ GameShark |
| **Nintendo 64** | RCP64 | [Mupen64Plus-Next](https://github.com/libretro/mupen64plus-libretro-nx) (GPL-2.0+) | ✅ IDENTIFIES ² | — | — | No | ✅ GameShark |
| **Nintendo DS** | DualScreen | [melonDS](https://melonds.kuribo64.net) (GPL-3.0) | ✅ IDENTIFIES ² | — | — | Optional | ✅ Action Replay |
| **PSP** | PortComp | [PPSSPP](https://www.ppsspp.org) (GPL-2.0+) | ✅ IDENTIFIES ² | — | — | No | ✅ CWCheat |
| **Dreamcast** | DreamArc | [Flycast](https://github.com/flyinghead/flycast) (GPL-2.0+) | ✅ IDENTIFIES ² | — | — | **Required** | ✅ CodeBreaker |
| **GameCube / Wii** | PowerCube | [Dolphin](https://dolphin-emu.org) (GPL-2.0+) | ✅ IDENTIFIES ² | — | — | No | ✅ Gecko |
| **Saturn** | TwinSH | [Beetle Saturn](https://github.com/libretro/beetle-saturn-libretro) (GPL-2.0+) | ✅ IDENTIFIES ² | — | — | **Required** | ✅ GameShark |
| **Atari 2600** | Joystick | [Stella](https://stella-emu.github.io) (GPL-2.0+) | ✅ IDENTIFIES | 🔨 BUILT | 🔨 BUILT | No | — |
| **PC Engine / TG-16** | CardCon | [Beetle PCE Fast](https://github.com/libretro/beetle-pce-fast-libretro) (GPL-2.0+) | ✅ IDENTIFIES | 🔨 BUILT | 🔨 BUILT | Optional | — |
| **DOS** | RealMode | [DOSBox Pure](https://github.com/libretro/dosbox-pure) (GPL-2.0+) | ✅ IDENTIFIES | 🔨 BUILT | 🔨 BUILT | No | — |
| **SCUMM / Adventure** | PointClick | [ScummVM](https://www.scummvm.org) (GPL-3.0+) | ✅ IDENTIFIES | 🔨 BUILT | — | No | — |

> **¹ AdvanceBit / iOS:** dynarec default is unverified on iOS; excluded until interpreter flags are confirmed.
>
> **² GL-dependent cores** (Geometry1, RCP64, DualScreen, PortComp, DreamArc, PowerCube, TwinSH): identify cleanly in the test harness but frame rendering requires an OpenGL context the current runtime doesn't yet provide outside the running app. End-to-end in-app frame verification is in progress.
>
> **Cheat abbreviations:** GS = GameShark · GG = Game Genie · AR = Action Replay · CB = CodeBreaker

### Build-Recipe Cores (not bundled — compile your own)

These cores exist in the repository as complete build recipes but are **not included in any binary release** due to their upstream non-commercial licence terms. You can build them locally from source.

| System | ezCORE Core | Upstream Engine | macOS Status | Why not bundled |
|---|---|---|:---:|---|
| **SNES** | SuperFX | [Snes9x](https://github.com/snes9xgit/snes9x) | IDENTIFIES | Non-commercial upstream licence — free distribution only |
| **Genesis / MD / SMS / GG** | BlastProc | [Genesis Plus GX](https://github.com/libretro/Genesis-Plus-GX) | IDENTIFIES | Non-commercial upstream licence — free distribution only |
| **Arcade / Neo Geo** | CoinBox | [FinalBurn Neo](https://github.com/libretro/FBNeo) | IDENTIFIES | Non-commercial licence + compatibility-allowlist review pending |

> **Gambatte** (GB/GBC) is also retained as a build recipe for local experimentation but **can never ship** with ezCORE — its source files grant GPL-2.0-only (no "or later"), which is incompatible with ezCORE's GPL-3.0-only licence. GB/GBC is covered by PocketBit (SameBoy, MIT licence). See [`docs/CORE_NAMING.md § Licence finding`](docs/CORE_NAMING.md#5-licence-finding--gambatte-cannot-ship).

### Legal Holds (never built, never shipped)

These slots are permanently reserved — manifests exist in `cores/*_hold/` but there are no build recipes and these cores will never ship without a fundamental legal change.

| System | Reason |
|---|---|
| **3DS** | Upstream projects fell to Nintendo's 2024 anti-circumvention actions |
| **Switch** | Same — Nintendo legal action |
| **PS2** | No shippable open-source PS2 libretro core exists |

`scripts/legal_audit.py` enforces these holds automatically on every release.

---

## The Orbit Interface

Four spaces, one viewport — no page scroll, rails only:

- **Library** — CoverFlow browser + game dock (or grid), collection strip (All / Favorites / per-system), `/` search, keyboard navigation (`←→` browse, `↵` details, `1–4` switch space). Game hub: core picker, Play, cheats, snapshot slots.
- **Systems** — core browser with hardware silhouettes + core dock (All / Added / Available). Cores ship inside the app; add/remove only changes what's active, and removal keeps your games and saves. Per-core licence shown in-app.
- **Time Capsule** — local save-snapshot vault across every game. Tap a snapshot → resume and load instantly.
- **Player** — pause, quick-save, fast-forward, screenshot (pins as the game's cover), touch overlay with haptics, live cheats, slot save/load, reset, and a "Take a breather" overlay that autosaves on exit.
- **Settings** — six local-preference tabs: Appearance, Emulation, Controllers, Audio, Library & Storage, About. Every control does something; nothing leaves your device.

**Design:** Dark-only. `#0A0A0A` near-black / `#007BFF` electric blue / `#DDE6F4` silver-white. Display: Space Grotesk. Body: Manrope. Both bundled offline (SIL OFL 1.1). Landscape ≥700 px docks navigation to a left command rail; portrait uses a top command dock.

No game art ships with the app: every import gets a deterministic generative cover, and player screenshots can be pinned as the cover.

---

## Bring Your Own Dumps

ezCORE plays **only files you supply yourself.** It ships no ROMs, BIOS/firmware, or decryption keys, and links to none. Your imports stay on your device — the library references your folders; nothing leaves. See [`TRADEMARKS.md`](TRADEMARKS.md) and [`DMCA.md`](DMCA.md).

**What ezCORE ships built-in:**
- **Cheat codes** — a curated, agent-verified database of cheat codes that are tested to actually work on each core. Codes are toggled per-game in the Player; the engine applies them at boot or live while playing. No ROM content whatsoever is included.

**What you supply:**
- **Your game dumps** — ROMs and disc images you own
- **BIOS files** (only for cores that require them: PS1 / Geometry1, Dreamcast / DreamArc, Saturn / TwinSH, optionally PC Engine / CardCon and DS / DualScreen). Full file names and placement paths: [`docs/INSTALL.md`](docs/INSTALL.md)

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│           Flutter UI  (Dart)                    │
│  Orbit console · AppState · services · player   │
└─────────────────┬───────────────────────────────┘
                  │ dart:ffi
┌─────────────────▼───────────────────────────────┐
│       ezCore Runtime  (C11, ABI v1)             │
│  session lifecycle · frame loop · AV buffers    │
│  save states · cheats · sha256-verified load    │
│  dynload_posix.c / dynload_win32.c              │
└─────────────────┬───────────────────────────────┘
                  │ libretro C API
┌─────────────────▼───────────────────────────────┐
│      Modular cores  (C/C++, sha256-pinned)      │
│  cores/<id>/manifest.json  ·  staged .dylib/.so │
└─────────────────────────────────────────────────┘
```

**Key design rules:**
- **Cores never touch Flutter.** Every core speaks the runtime ABI (`runtime/include/ezcore_runtime.h`). A core that satisfies the ABI works on every platform unchanged.
- **No external library dependencies in the runtime.** Only C stdlib + vendored `libretro-common` headers.
- **Execution policy lives in data, not code.** Each manifest declares `interpreter` or `dynarec` per OS — iOS is always interpreter (enforced by manifest validation and the CI legal audit).
- **SHA-256 verified before every load.** Artifacts are pinned at build time; the runtime rejects anything that doesn't match.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full layer breakdown and [`docs/CORE_SYSTEM.md`](docs/CORE_SYSTEM.md) for the core plugin system deep-dive.

---

## Install

| Platform | Artifact | Instructions |
|---|---|---|
| macOS (Apple Silicon) | `ezcore-<ver>-macos-arm64.zip` | [Releases](https://github.com/JinUltimate1995/ezcore/releases) → [`docs/INSTALL.md`](docs/INSTALL.md) |
| Android (arm64) | `ezcore-<ver>-android-arm64.apk` | [Releases](https://github.com/JinUltimate1995/ezcore/releases) → [`docs/INSTALL.md`](docs/INSTALL.md) |
| Windows / Linux | — | Build from source (below) |
| iOS | — | Not distributed yet |

**macOS first-launch note:** the app is ad-hoc signed but not notarized. Run `xattr -cr /Applications/ezCore.app` once after copying it to Applications. Full details in [`docs/INSTALL.md`](docs/INSTALL.md).

---

## Build from Source

### macOS quick start

```bash
git clone https://github.com/JinUltimate1995/ezcore.git
cd ezcore
scripts/prereqs.sh                      # one-shot toolchain (Homebrew + Flutter)
scripts/build_core.sh --fetch-headers   # vendor libretro.h
scripts/build_runtime.sh macos          # C11 runtime + CTest
scripts/build_core.sh --tier1           # first six cores (PocketBit, AdvanceBit, NesByte, ...)
python3 scripts/build_catalog.py        # merge manifests → cores/catalog.json
flutter analyze && flutter test         # must be green before running
flutter run -d macos                    # launch the app
```

Full platform matrix (Windows, Linux, Android, iOS), all tiers, and release assembly: [`docs/BUILDING.md`](docs/BUILDING.md).

---

## Documentation

| Document | What's in it |
|---|---|
| [`docs/INSTALL.md`](docs/INSTALL.md) | User install guide per platform + BIOS file placement |
| [`docs/BUILDING.md`](docs/BUILDING.md) | Developer build guide — all platforms, all tiers, CI gates |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Layer rules, ABI, data flow (as-built against shipping code) |
| [`docs/MATRIX.md`](docs/MATRIX.md) | **Core × platform verification matrix** — the honest source |
| [`docs/CORE_SYSTEM.md`](docs/CORE_SYSTEM.md) | Core plugin system: manifests, pins, execution policy |
| [`docs/CORE_NAMING.md`](docs/CORE_NAMING.md) | Core codename rationale, upstream attribution, licence findings |
| [`docs/RELEASE_PLAN.md`](docs/RELEASE_PLAN.md) | v1 scope, settled decisions, what's deliberately excluded |
| [`docs/RELEASING.md`](docs/RELEASING.md) | How releases are cut (local + CI, secrets, checksums) |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history |
| [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) | Every bundled component + its licence |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Contribution rules — hard rules and normal ones |
| [`SECURITY.md`](SECURITY.md) | Vulnerability reporting (private disclosure) |
| [`SUPPORT.md`](SUPPORT.md) | FAQ and support paths |
| [`TRADEMARKS.md`](TRADEMARKS.md) · [`DMCA.md`](DMCA.md) | Brand policy · takedown policy |

---

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) first — there are a few hard rules (no ROMs, no BIOS, no commercial game content, one task at a time). Beyond that, contributions are genuinely welcome.

**Found a bug?** [Open an issue](https://github.com/JinUltimate1995/ezcore/issues/new/choose) using the bug template — it asks for exactly what we need.  
**Already fixed it?** PRs are welcome. Branch from `main`, one logical change per PR.  
**Want a feature?** Use the feature request template; small and specific beats big and vague.  
**Want to add a core?** Read [`docs/CORE_SYSTEM.md`](docs/CORE_SYSTEM.md) and [`docs/CORE_NAMING.md`](docs/CORE_NAMING.md) first — there are licensing and naming rules.  
**Want to discuss first?** [GitHub Discussions](https://github.com/JinUltimate1995/ezcore/discussions) is the right place.

### Recognition

**Contributors and sponsors are credited inside the app itself** — in the About tab in Settings, by GitHub username. If you ship a merged PR or sponsor the project, your name is in the product, not just the commit log.

---

## License & Credits

- **App shell + runtime:** GPL-3.0-only — see [`LICENSE`](LICENSE)
- **Emulator cores:** each keeps its upstream licence — see the table above, `cores/<id>/manifest.json`, and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)
- **Fonts:** Space Grotesk (Florian Karsten) and Manrope (Mikhail Sharanda) — SIL OFL 1.1 (see [`assets/fonts/OFL.txt`](assets/fonts/OFL.txt))
- **Brand:** the ezCORE name, logo and brand assets are **not** licensed for reuse — [`TRADEMARKS.md`](TRADEMARKS.md)

ezCORE stands on the shoulders of the [libretro](https://www.libretro.com/) ecosystem and every emulator project behind each core. Thank you.

---

## Support & Community

- [**GitHub Discussions**](https://github.com/JinUltimate1995/ezcore/discussions) — questions, ideas, community help
- [**GitHub Issues**](https://github.com/JinUltimate1995/ezcore/issues) — bugs and feature requests (please use the templates)
- [**SECURITY.md**](SECURITY.md) — report vulnerabilities privately

### Support the Project

ezCORE is free and open source and **stays that way** — no ads, no closed cores, no paywalled features. Every feature (fast-forward, save states, cheats, themes — all of it) is free, forever. Paid options are additive only:

- **[Sponsor on GitHub](https://github.com/sponsors/JinUltimate1995)** — fund development directly. Sponsors get:
  - 🏷️ **Your name in the app** — credited in the About tab in Settings by GitHub username
  - ⚡ Early access to features and builds before public release
- **ezCORE Platinum** *(planned)* — a paid convenience build on Google Play. Same engine, same features, premium icon and theme. One-time purchase. Your money funds the project; the source stays public.
- **ezCORE Cloud** *(planned, v1.1+)* — optional sync & backup. You pay for the service (servers, storage, version history), not for software features. Local saves are always complete and free.

**We will never:** sell ads, close-source any core, paywall emulation features, or sell user data. Full commitment in [`docs/MONETIZATION.md`](docs/MONETIZATION.md).


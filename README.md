<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/branding/lockup-light.png">
    <source media="(prefers-color-scheme: light)" srcset="assets/branding/lockup-dark.png">
    <img alt="ezCORE Logo" src="assets/branding/lockup-dark.png" width="420">
  </picture>
</p>

<p align="center">
  <strong>One unified console. Every retro system. Zero setup.</strong><br>
  <em>Drop your games, press play, and let the console get out of your way.</em>
</p>

<p align="center">
  <a href="#-quick-start--downloads"><b>Quick Start</b></a> •
  <a href="#-the-orbit-console-experience"><b>Orbit Features</b></a> •
  <a href="#-systems--core-matrix"><b>Supported Systems</b></a> •
  <a href="#-screenshots"><b>Screenshots</b></a> •
  <a href="#-architecture"><b>Architecture</b></a> •
  <a href="#-community--support"><b>Community & Credits</b></a>
</p>

<p align="center">
  <a href="https://github.com/JinUltimate1995/ezcore/releases"><img alt="Latest Release" src="https://img.shields.io/github/v/release/JinUltimate1995/ezcore?include_prereleases&label=release&color=007BFF&style=for-the-badge"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-GPL--3.0--only-007BFF?style=for-the-badge"></a>
  <a href="https://github.com/JinUltimate1995/ezcore/actions"><img alt="CI Matrix" src="https://img.shields.io/github/actions/workflow/status/JinUltimate1995/ezcore/ci.yml?branch=main&label=CI%20Matrix&style=for-the-badge"></a>
  <a href="docs/MATRIX.md"><img alt="14 Bundled Cores" src="https://img.shields.io/badge/cores-14%20bundled-28a745?style=for-the-badge"></a>
  <a href="https://github.com/sponsors/JinUltimate1995"><img alt="Sponsor" src="https://img.shields.io/badge/sponsor-❤-ff69b4?style=for-the-badge"></a>
</p>

<p align="center">
  <img alt="macOS arm64 — verified" src="https://img.shields.io/badge/macOS%20arm64-verified-brightgreen?style=flat-square">
  <img alt="Android arm64 — staged" src="https://img.shields.io/badge/Android%20arm64-built%20%2B%20staged-yellow?style=flat-square">
  <img alt="Windows x64 — from source" src="https://img.shields.io/badge/Windows%20x64-from%20source-lightgrey?style=flat-square">
  <img alt="Linux x64 — from source" src="https://img.shields.io/badge/Linux%20x64-from%20source-lightgrey?style=flat-square">
  <img alt="iOS — interpreter ready" src="https://img.shields.io/badge/iOS-interpreter%20ready-lightgrey?style=flat-square">
</p>

---

### What is ezCORE?

**ezCORE** is a modern, high-performance multi-system emulator crafted for players who value elegance, speed, and privacy. 

Retro gaming shouldn't feel like navigating enterprise spreadsheet software. ezCORE delivers a unified, console-grade experience: modular libretro emulation cores wrapped behind a lightweight C11 ABI, fronted by the sleek **Orbit** console interface.

> 🚀 **v0.1.1 is an early public build.** macOS Apple Silicon is fully verified end-to-end; Android is compiled and staged; Windows and Linux build cleanly from source. Verified status is tracked with total transparency in [`docs/MATRIX.md`](docs/MATRIX.md).

---

## 📸 Screenshots

| 🖼️ Orbit Library | 🌌 Systems Hub |
|:---:|:---:|
| ![Library — CoverFlow browser](docs/images/library.png) | ![Systems — core browser](docs/images/systems.png) |
| *Fluid CoverFlow browser, instant search (`/`), and quick game dock.* | *Hardware silhouettes, license transparency, and active core toggles.* |
| **⏳ Time Capsule** | **⚙️ Unified Settings** |
| ![Time Capsule — local save vault](docs/images/time-capsule.png) | ![Settings — six preference tabs](docs/images/settings.png) |
| *Visual save snapshot timeline — tap any card to resume that exact frame.* | *Six local preference tabs: Audio, Input, Video, Storage, Appearance, About.* |

*(Real screenshots captured from the v0.1.1 build on macOS arm64)*

---

## ⏱️ The Orbit Console Experience

Designed around the strict philosophy of **Game → Play**:

* **🚀 Zero-Friction Emulation**: No core selection menus or binding rituals just to boot a game. Pick a title, and ezCORE auto-routes it to the optimal verified core, binds your controller, and launches immediately.
* **⏳ Time Capsule (Visual Save Vault)**: Forget cryptic slot numbers (`slot0.state`). Every quick-save captures a timestamped visual snapshot card. Browse your timeline and teleport right back into the action with one tap.
* **🎨 Generative Vector Box Art**: Never suffer through broken scraper databases or missing artwork. Every game automatically generates a bespoke geometric cover matching the Orbit palette (`#0A0A0A` near-black and `#007BFF` electric blue). Prefer your own? Pin any in-game screenshot as the permanent box art.
* **🕹️ Pro Gamepad & Tactile Touch**: Zero-latency plug-and-play mapping for Xbox, PlayStation (DualShock / DualSense), Switch Pro, and MFi controllers. On mobile, enjoy a bespoke virtual gamepad with calibrated haptic pulses.
* **⚡ Curated Live Cheats**: Built-in, agent-verified cheat codes (GameShark, Action Replay, Game Genie, CodeBreaker). Toggle cheats live during gameplay without crashing your session.
* **🛡️ 100% Offline & Sovereign**: No telemetry, no analytics, no accounts, and no DRM. Your ROMs, save states, and configurations remain strictly on your local machine.

---

## 🚀 Quick Start & Downloads

### Official Releases

| Platform | Format | Status | Download |
|:---|:---:|:---:|:---:|
| **macOS (Apple Silicon)** | `.zip` | ✅ **Verified** | [Download latest macOS Release](https://github.com/JinUltimate1995/ezcore/releases) |
| **Android (arm64-v8a)** | `.apk` | ⚡ **Built & Staged** | [Download latest Android APK](https://github.com/JinUltimate1995/ezcore/releases) |
| **Windows (x64)** | Source | 🔨 **CI Maturing** | [Build Guide](docs/BUILDING.md) |
| **Linux (x64)** | Source | 🔨 **CI Maturing** | [Build Guide](docs/BUILDING.md) |
| **iOS (arm64)** | Framework | 🔒 **Code Ready** | [Manifest Policy](docs/ARCHITECTURE.md) |

> [!TIP]
> **macOS First-Launch Note:** Releases are ad-hoc signed without Apple notarization. Run this single command in Terminal after dragging ezCORE to your Applications folder:
> ```bash
> xattr -cr /Applications/ezCore.app
> ```
> See [`docs/INSTALL.md`](docs/INSTALL.md) for step-by-step guides and BIOS placement paths.

---

## 🎮 Systems & Core Matrix

ezCORE invents and owns its core codenames to respect upstream projects and ensure clean attribution. Full details live in [`docs/CORE_NAMING.md`](docs/CORE_NAMING.md).

### 📦 Bundled Cores (Ready Out of the Box)

| System | ezCORE Core | Upstream Engine & Licence | macOS | Android | BIOS? | Cheat Engine |
|:---|:---|:---|:---:|:---:|:---:|:---:|
| **Handhelds** | | | | | | |
| Game Boy / GBC | **PocketBit** | [SameBoy](https://github.com/LIJI32/SameBoy) (MIT) | 🎮 **RENDERS** | 🔨 BUILT | None | ✅ GS · GG |
| Game Boy Advance | **AdvanceBit** | [mGBA](https://mgba.io) (MPL-2.0) | 🎮 **RENDERS** | 🔨 BUILT | None | ✅ AR · CB · GS |
| Nintendo DS | **DualScreen** | [melonDS](https://melonds.kuribo64.net) (GPL-3.0) | ✅ IDENTIFIES ᵇ | — | Optional | ✅ Action Replay |
| PSP | **PortComp** | [PPSSPP](https://www.ppsspp.org) (GPL-2.0+) | ✅ IDENTIFIES ᵇ | — | None | ✅ CWCheat |
| **8-Bit & 16-Bit Classics** | | | | | | |
| NES / Famicom | **NesByte** | [Mesen](https://github.com/libretro/Mesen) (GPL-3.0+) | ✅ IDENTIFIES | 🔨 BUILT | None | ✅ Game Genie |
| Atari 2600 | **Joystick** | [Stella](https://stella-emu.github.io) (GPL-2.0+) | ✅ IDENTIFIES | 🔨 BUILT | None | — |
| PC Engine / TG-16 | **CardCon** | [Beetle PCE Fast](https://github.com/libretro/beetle-pce-fast-libretro) (GPL-2.0+) | ✅ IDENTIFIES | 🔨 BUILT | Optional | — |
| **3D & Disc Consoles** | | | | | | |
| PlayStation 1 | **Geometry1** | [SwanStation](https://github.com/libretro/swanstation) (GPL-3.0) | ✅ IDENTIFIES ᵇ | — | **Required** | ✅ GameShark |
| Nintendo 64 | **RCP64** | [Mupen64Plus-Next](https://github.com/libretro/mupen64plus-libretro-nx) (GPL-2.0+) | ✅ IDENTIFIES ᵇ | — | None | ✅ GameShark |
| Sega Saturn | **TwinSH** | [Beetle Saturn](https://github.com/libretro/beetle-saturn-libretro) (GPL-2.0+) | ✅ IDENTIFIES ᵇ | — | **Required** | ✅ GameShark |
| Sega Dreamcast | **DreamArc** | [Flycast](https://github.com/flyinghead/flycast) (GPL-2.0+) | ✅ IDENTIFIES ᵇ | — | **Required** | ✅ CodeBreaker |
| GameCube / Wii | **PowerCube** | [Dolphin](https://dolphin-emu.org) (GPL-2.0+) | ✅ IDENTIFIES ᵇ | — | None | ✅ Gecko |
| **Retro PC & Adventure** | | | | | | |
| DOS | **RealMode** | [DOSBox Pure](https://github.com/libretro/dosbox-pure) (GPL-2.0+) | ✅ IDENTIFIES | 🔨 BUILT | None | — |
| SCUMM / Adventure | **PointClick** | [ScummVM](https://www.scummvm.org) (GPL-3.0+) | ✅ IDENTIFIES | 🔨 BUILT | None | — |

> 🎮 **RENDERS**: Boots ROM content, sustains 30+ frames, nonzero pixels verified, state serialization checked.  
> ✅ **IDENTIFIES**: Dynamically loads and cleanly executes in the fork-isolated test harness.  
> 🔨 **BUILT**: Verified target compilation and symbol export.  
> ᵇ **GL-dependent cores**: Load and identify in the native harness; frame rendering requires an active OpenGL context provided by the app shell.  
> *Cheat Key:* **GS** = GameShark · **GG** = Game Genie · **AR** = Action Replay · **CB** = CodeBreaker · **CW** = CWCheat.

---

### 🛠️ Build-Recipe Cores (Non-Commercial Upstream)

To strictly protect users and preserve GPL-3.0 integrity, cores with non-commercial upstream licenses are **never pre-bundled** in releases. Complete, tested automated build recipes remain in-tree:

| System | ezCORE Core | Upstream Engine | Reason | Build Command |
|:---|:---|:---|:---|:---|
| **Super Nintendo (SNES)** | **SuperFX** | [Snes9x](https://github.com/snes9xgit/snes9x) | Non-commercial upstream terms | `scripts/build_core.sh superfx` |
| **Genesis / MD / SMS / GG** | **BlastProc** | [Genesis Plus GX](https://github.com/libretro/Genesis-Plus-GX) | Non-commercial upstream terms | `scripts/build_core.sh blastproc` |
| **Arcade / Neo Geo** | **CoinBox** | [FinalBurn Neo](https://github.com/libretro/FBNeo) | Non-commercial upstream terms | `scripts/build_core.sh coinbox` |

> [!NOTE]
> **Gambatte (GB/GBC):** Gambatte's upstream codebase is licensed strictly under **GPL-2.0-only** (without "or later"). It cannot legally link into a GPL-3.0 application bundle. ezCORE serves GB/GBC out-of-the-box via **PocketBit** (SameBoy, MIT).

### ⛔ Legal Holds (Permanently Reserved)

| System | Status | Legal Reason |
|:---|:---:|:---|
| **Nintendo 3DS** | `citra_hold` | Upstream repos enjoined under Nintendo's 2024 DMCA actions. |
| **Nintendo Switch** | `switch_hold` | Upstream repos enjoined under Nintendo's 2024 DMCA actions. |
| **PlayStation 2** | `ps2_hold` | No legally shippable, open-source libretro PS2 core exists. |

---

## 💾 Bring Your Own Dumps (BYOD)

ezCORE maintains a clean-room legal boundary. We do not distribute ROMs, BIOS images, or cryptographic keys.

* **What ezCORE Includes:**
  * Complete emulation runtime, interface, and 14 bundled open-source cores.
  * Curated, agent-verified cheat database for instant in-game use.
  * Generative vector box art engine.
* **What You Supply:**
  * Your legal game dumps (`.gb`, `.gba`, `.nes`, `.iso`, `.chd`, etc.).
  * BIOS files for systems that require them (PS1, Dreamcast, Saturn). See [`docs/INSTALL.md`](docs/INSTALL.md).

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────┐
│                   Flutter UI  (Dart)                     │
│   Orbit console · Navigation rails · Time Capsule vault  │
└────────────────────────────┬─────────────────────────────┘
                             │ dart:ffi
┌────────────────────────────▼─────────────────────────────┐
│             ezCore Runtime  (C11, ABI v1)                │
│   Session lifecycle · Frame loop · Audio/Video buffers   │
│   SRAM handoff · State serialization · Live cheat hook   │
└────────────────────────────┬─────────────────────────────┘
                             │ libretro C API
┌────────────────────────────▼─────────────────────────────┐
│         Modular Cores  (C/C++, SHA-256 Pinned)           │
│   PocketBit · AdvanceBit · NesByte · Geometry1 · etc.    │
└──────────────────────────────────────────────────────────┘
```

* **Core Isolation**: Cores never communicate directly with Flutter. They adhere strictly to the stable C ABI (`runtime/include/ezcore_runtime.h`).
* **Zero External Dependencies**: The native runtime relies solely on standard C11 and vendored `libretro-common` headers.
* **Execution Strategy in Data**: Manifests declare `interpreter` or `dynarec` per target OS. iOS mandates interpreter mode by policy.
* **Cryptographic Pinning**: Every staged core binary is verified against its manifest SHA-256 before loading.

Read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/CORE_SYSTEM.md`](docs/CORE_SYSTEM.md) for technical deep-dives.

---

## 💻 Building from Source

```bash
# 1. Clone repository
git clone https://github.com/JinUltimate1995/ezcore.git
cd ezcore

# 2. Setup toolchain & dependencies (macOS/Linux)
scripts/prereqs.sh
scripts/build_core.sh --fetch-headers

# 3. Build C11 runtime & run CTest
scripts/build_runtime.sh macos

# 4. Build Tier 1 cores & generate catalog
scripts/build_core.sh --tier1
python3 scripts/build_catalog.py

# 5. Run tests & launch Orbit
flutter analyze && flutter test
flutter run -d macos
```

See [`docs/BUILDING.md`](docs/BUILDING.md) for full Windows, Linux, Android, and iOS toolchains.

---

## 📚 Project Documentation

| Document | Description |
|:---|:---|
| [`docs/INSTALL.md`](docs/INSTALL.md) | Platform installation guides and BIOS path specifications |
| [`docs/BUILDING.md`](docs/BUILDING.md) | Compiling runtime, cores, and app targets from scratch |
| [`docs/MATRIX.md`](docs/MATRIX.md) | **Canonical verification matrix** — tests, tiers, and platform status |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | System architecture, runtime C ABI, and isolation boundaries |
| [`docs/CORE_SYSTEM.md`](docs/CORE_SYSTEM.md) | Core plugin manifest format, SHA pinning, and execution policies |
| [`docs/CORE_NAMING.md`](docs/CORE_NAMING.md) | Core codename conventions, upstream licensing, and attribution |
| [`docs/RELEASE_PLAN.md`](docs/RELEASE_PLAN.md) | Milestone roadmap, platform release gates, and exclusions |
| [`docs/RELEASING.md`](docs/RELEASING.md) | Release packaging, checksum verification, and CI signing |
| [`CHANGELOG.md`](CHANGELOG.md) | Version history, added features, and deprecations |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Engineering discipline, hard rules, and pull request guidelines |
| [`SECURITY.md`](SECURITY.md) | Security vulnerability reporting and disclosure policy |
| [`SUPPORT.md`](SUPPORT.md) | Community FAQ and troubleshooting channels |

---

## 🤝 Contributing & Recognition

We welcome pull requests for bug fixes, core enhancements, and documentation. Please review [`CONTRIBUTING.md`](CONTRIBUTING.md) before submitting code.

### 🌟 Your Name in ezCORE
We believe in honoring everyone who helps build this project:
* **All code contributors and GitHub Sponsors are permanently credited inside the live application** under **Settings → About** by GitHub username.
* Sponsors also receive early access to experimental builds and feature previews.

👉 **[Become a GitHub Sponsor](https://github.com/sponsors/JinUltimate1995)**

---

## 📜 License & Acknowledgments

* **Application Shell & Runtime:** [GNU General Public License v3.0](LICENSE) (`GPL-3.0-only`).
* **Emulator Cores:** Each core retains its original open-source license. Consult `cores/<id>/manifest.json` and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
* **Typography:** Space Grotesk (Florian Karsten) and Manrope (Mikhail Sharanda), licensed under [SIL Open Font License 1.1](assets/fonts/OFL.txt).
* **Trademarks:** The ezCORE name, branding, and logo assets are protected under [`TRADEMARKS.md`](TRADEMARKS.md).

ezCORE is indebted to the pioneering work of the [libretro](https://www.libretro.com/) project and the tireless open-source emulator developers worldwide.

---

<p align="center">
  <sub>Built with passion for retro gaming preservation.</sub>
</p>

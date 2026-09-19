# Third-Party Notices

ezCORE bundles or links the components below. Each keeps its own license;
this file is the human-readable index. The machine-readable source of truth
for core licenses is `cores/<id>/manifest.json` (`license`, `license_url`),
regenerated into `cores/catalog.json` by `scripts/build_catalog.py`.

**No game content is bundled, ever.** No ROMs, BIOS/firmware, decryption
keys, game art, or cheat databases ship with this project or its releases —
see [`TRADEMARKS.md`](TRADEMARKS.md) and [`DMCA.md`](DMCA.md).

---

## 1. ezCORE itself

| Component | License |
|---|---|
| App shell (Flutter/Dart, `lib/`) | GPL-3.0-only |
| ezCore Runtime (C11, `runtime/`) | GPL-3.0-only |
| Core manifests, scripts, docs | GPL-3.0-only |

Full text: [`LICENSE`](LICENSE). SPDX: `GPL-3.0-only`.

## 2. Emulator cores

Each core is an independent upstream project, built from source by
`scripts/build_core.sh`. Only cores whose licenses permit distribution are
shipped as separate binaries (sha256-pinned in their manifests); the rest
remain in-tree as build recipes. Licenses and upstream sources:

| Core | Project | License | Upstream |
|---|---|---|---|
| `cardcon` | Beetle PCE Fast | GPL-2.0-or-later | libretro/beetle-pce-fast-libretro |
| `twinsh` | Beetle Saturn | GPL-2.0-or-later | libretro/beetle-saturn-libretro |
| `powercube` | Dolphin | GPL-2.0-or-later | libretro/dolphin |
| `realmode` | DOSBox Pure | GPL-2.0-or-later | libretro/dosbox-pure |
| `coinbox` | FinalBurn Neo | FBNeo-custom (non-commercial) — **not distributed in any binary** | libretro/FBNeo |
| `dreamarc` | Flycast | GPL-2.0-or-later | flyinghead/flycast (libretro build target) |
| `gambatte` | Gambatte | GPL-2.0-**only** — **not distributed in any binary** (cannot form a combined work with our GPL-3.0-only app) | libretro/gambatte-libretro |
| `blastproc` | Genesis Plus GX | Genesis-Plus-GX-custom (non-commercial) — **not distributed in any binary** | libretro/Genesis-Plus-GX |
| `dualscreen` | melonDS | GPL-3.0 | libretro/melonDS |
| `nesbyte` | Mesen | GPL-3.0 | libretro/Mesen |
| `advancebit` | mGBA | MPL-2.0 | libretro/mgba |
| `rcp64` | Mupen64Plus-Next | GPL-2.0-or-later | libretro/mupen64plus-libretro-nx |
| `portcomp` | PPSSPP | GPL-2.0-or-later | hrydgard/ppsspp (libretro build target) |
| `pocketbit` | SameBoy | MIT | libretro/SameBoy (built from LIJI32/SameBoy) |
| `pointclick` | ScummVM | GPL-3.0 | scummvm/scummvm (libretro port in-tree) |
| `superfx` | Snes9x | Snes9x-custom (non-commercial, attribution required) — **not distributed in any binary** | libretro/snes9x |
| `joystick` | Stella | GPL-2.0-or-later | libretro/stella2023 |
| `geometry1` | SwanStation | GPL-3.0 | libretro/swanstation |

Notes:

- **Non-commercial cores** (FBNeo, Genesis Plus GX, Snes9x) are **not
  distributed in any binary — free or paid**. Their upstream licenses
  forbid commercial redistribution, and ezCORE ships one artifact for
  everyone. They remain in-tree as build recipes for users who compile
  their own. Enforced by `scripts/legal_audit.py` (removed from
  distribution 2026-09-19; see `CHANGELOG.md`).
- **`rcp64`** builds on the mupen64plus-libretro-nx tree (GPL-2.0);
  the classic Mupen64Plus project license text is included in that tree.
- **Holds (never built, never distributed):** `citra_hold` (3DS),
  `switch_hold` (Switch), `ps2_hold` (PS2). Their manifests explain the
  legal posture and ship no artifacts.
- Upstream projects may carry additional per-file notices; when you
  redistribute a bundled core, keep the license files that ship with its
  build tree (`native/src/<core>/`, produced by `scripts/build_core.sh`).

## 3. Fonts

| Font | Copyright | License |
|---|---|---|
| Space Grotesk | Florian Karsten / Space Grotesk Project Authors | SIL OFL 1.1 |
| Manrope | Mikhail Sharanda / Manrope Project Authors | SIL OFL 1.1 |

Full license text with copyright notices: [`assets/fonts/OFL.txt`](assets/fonts/OFL.txt).
Files are unmodified from the Google Fonts distribution.

## 4. Flutter, Dart packages, and platform runtimes

The app is built with **Flutter** (BSD-3-Clause, © Google) and uses these
packages (all permissively licensed; exact versions in `pubspec.lock`):

| Package | License |
|---|---|
| `cupertino_icons` | MIT |
| `flutter_svg` | MIT |
| `path_provider` | BSD-3-Clause |
| `file_selector` | BSD-3-Clause |
| `flutter_test`, `integration_test` | BSD-3-Clause (Flutter) |

Platform runtimes (Android system libraries, Apple system frameworks) are
used per their platform terms and are not redistributed by this project.

## 5. Verification and provenance

- Core artifacts are built from the upstream sources named above and
  **sha256-pinned** per platform in `cores/<id>/manifest.json`.
- `scripts/pin_artifacts.py --check` refuses to assemble a release when the
  staged artifacts don't match the reviewed pins.
- `scripts/banned_content_scan.sh` fails the build if ROM/BIOS/key artifacts
  ever land in the repo; `scripts/release.sh` re-runs it over what ships.

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
| Core catalog artwork (`assets/core_art/`) | GPL-3.0-only; project-generated — see [`docs/CORE_ART_PROVENANCE.md`](docs/CORE_ART_PROVENANCE.md) and [`docs/CORE_ART_PROVENANCE.json`](docs/CORE_ART_PROVENANCE.json) |
| ezCore Runtime (C11, `runtime/`) | GPL-3.0-only |
| Core manifests, scripts, docs | GPL-3.0-only |

Full text: [`LICENSE`](LICENSE), with the [Core Module Exception](LICENSE-EXCEPTION.md). SPDX: `GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception`.

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
| `dreamarc` | Flycast | GPL-2.0-or-later | flyinghead/flycast (libretro build target) |
| `dualscreen` | melonDS | GPL-3.0 | libretro/melonDS |
| `nesbyte` | Mesen | GPL-3.0 | libretro/Mesen |
| `advancebit` | mGBA | MPL-2.0 | libretro/mgba |
| `rcp64` | Mupen64Plus-Next | GPL-2.0-or-later | libretro/mupen64plus-libretro-nx |
| `portcomp` | PPSSPP | GPL-2.0-or-later | hrydgard/ppsspp (libretro build target) |
| `pocketbit` | SameBoy | MIT | libretro/SameBoy (built from LIJI32/SameBoy) |
| `pointclick` | ScummVM | GPL-3.0 | scummvm/scummvm (libretro port in-tree) |
| `joystick` | Stella | GPL-2.0-or-later | libretro/stella2023 |
| `geometry1` | SwanStation | GPL-3.0 | libretro/swanstation |
| `lrps2` | LRPS2 (libretro port of PCSX2) | GPL-3.0-or-later | libretro/ps2 |
| `dualvu` | Play! | BSD-2-Clause | jpd002/Play- (in-tree `ui_libretro` target) |
| `gw` | PocketTick (invented ezCORE name) | Zlib (zlib/libpng, © 2015 Andre Leiradella) | libretro/gw-libretro (Andre Leiradella) |
| `potator` | SpritePocket (invented ezCORE name) | Unlicense (public-domain dedication) | libretro/potator (based on Normmatt's emulator) |

Notes:

- **Non-commercial cores** are not part of ezCORE and are not distributed
  in any binary, free or paid. The licence audit enforces this rule.
- **`rcp64`** builds on the mupen64plus-libretro-nx tree (GPL-2.0);
  the classic Mupen64Plus project license text is included in that tree.
- **Holds (never built, never distributed):** `citra_hold` (3DS),
  `switch_hold` (Switch). Their manifests explain the legal posture and
  ship no artifacts.
- Upstream projects may carry additional per-file notices; when you
  redistribute a bundled core, keep the license files that ship with its
  build tree (`native/src/<core>/`, produced by `scripts/build_core.sh`).

## 3. Fonts and icons

| Font | Copyright | License |
|---|---|---|
| Space Grotesk | Florian Karsten / Space Grotesk Project Authors | SIL OFL 1.1 |
| Manrope | Mikhail Sharanda / Manrope Project Authors | SIL OFL 1.1 |
| Material Symbols Rounded | Copyright 2026 Google LLC. All Rights Reserved. | Apache License 2.0 |

Full license text with copyright notices: [`assets/fonts/OFL.txt`](assets/fonts/OFL.txt)
for the text faces, and
[`assets/fonts/LICENSE-MaterialSymbolsRounded.txt`](assets/fonts/LICENSE-MaterialSymbolsRounded.txt)
for the icon font.

Space Grotesk and Manrope are unmodified from the Google Fonts
distribution. `assets/fonts/MaterialSymbolsRounded.ttf` is a glyph subset of
the upstream variable font (axes `FILL`, `wght`, `GRAD`, `opsz`), prepared for
ezCORE and distributed under the same Apache License 2.0. The subset keeps the
upstream copyright notice; see `lib/theme/symbols.dart` for the bundled glyph
list.

## 4. Flutter, Dart packages, and platform runtimes

The app is built with **Flutter** (BSD-3-Clause, © Google) and uses the
packages below. Exact versions are in `pubspec.lock`, which pins 76 packages
in total; the table covers the 36 entries a shipped build uses, with the
licence read from each package's own `LICENSE` file. Every entry in the table
is permissive (MIT, BSD-3-Clause or Apache-2.0); one Gradle dependency the
Android build links is not, and it is noted below.

| Package | License |
|---|---|
| `flutter`, `sky_engine` | BSD-3-Clause (Flutter SDK; engine third-party notices ship in `NOTICES.Z`) |
| `characters` | BSD-3-Clause |
| `collection` | BSD-3-Clause |
| `cross_file` | BSD-3-Clause |
| `cupertino_icons` | MIT |
| `ffi` | BSD-3-Clause |
| `file_selector` | BSD-3-Clause |
| `file_selector_android` | Apache-2.0 (also bundles aFileChooser, Apache-2.0) |
| `file_selector_ios` | BSD-3-Clause |
| `file_selector_linux` | BSD-3-Clause |
| `file_selector_macos` | BSD-3-Clause |
| `file_selector_platform_interface` | BSD-3-Clause |
| `file_selector_windows` | BSD-3-Clause |
| `in_app_purchase` | BSD-3-Clause |
| `in_app_purchase_android` | BSD-3-Clause |
| `in_app_purchase_platform_interface` | BSD-3-Clause |
| `in_app_purchase_storekit` | BSD-3-Clause |
| `jni` | BSD-3-Clause |
| `jni_flutter` | BSD-3-Clause |
| `json_annotation` | BSD-3-Clause |
| `material_color_utilities` | Apache-2.0 |
| `meta` | BSD-3-Clause |
| `objective_c` | BSD-3-Clause |
| `path` | BSD-3-Clause |
| `path_provider` | BSD-3-Clause |
| `path_provider_android` | BSD-3-Clause |
| `path_provider_foundation` | BSD-3-Clause |
| `path_provider_linux` | BSD-3-Clause |
| `path_provider_platform_interface` | BSD-3-Clause |
| `path_provider_windows` | BSD-3-Clause |
| `platform` | BSD-3-Clause |
| `plugin_platform_interface` | BSD-3-Clause |
| `pub_semver` | BSD-3-Clause |
| `vector_math` | BSD-3-Clause |
| `xdg_directories` | BSD-3-Clause |

Dev-only packages are the test and lint set: `flutter_test`, `integration_test`,
`flutter_driver`, `flutter_lints`, `lints`, `leak_tracker`,
`leak_tracker_flutter_testing`, `leak_tracker_testing`, `matcher`, `test_api`,
`fake_async`, `clock`, `boolean_selector`, `file`, `process`, `stack_trace`,
`stream_channel`, `sync_http`, `webdriver`, `vm_service` and
`fuchsia_remote_debug_protocol`. None is in a shipped bundle; each is
BSD-3-Clause, Apache-2.0 or the Flutter SDK licence.

Another 19 entries in `pubspec.lock` are resolved at build time but no path in
a native build imports them, so nothing from them is compiled into a shipped
bundle: `args`, `async`, `code_assets`, `crypto`, `hooks`, `http`,
`http_parser`, `jni_util`, `logging`, `package_config`, `record_use`,
`source_span`, `string_scanner`, `term_glyph`, `typed_data` and `yaml`, plus
`web`, `file_selector_web` and `flutter_web_plugins`, which only cross-file's
web-only conditional import or a web target would pull in (this tree has no
`web/` directory). They are BSD-3-Clause or MIT; `yaml` also carries Kirill
Simonov's MIT notice for the Python port it derives from.

`in_app_purchase` resolves one implementation per platform, and only that one
is bundled: `in_app_purchase_android` on Android, `in_app_purchase_storekit`
on iOS and macOS (StoreKit is an Apple system framework). Linux and Windows
have no store implementation — the app reports no store there and the purchase
UI falls back to the Sponsors card. `file_selector` works the same way: the
Android, iOS, Linux, macOS and Windows implementations ship and
`file_selector_web` does not, because there is no web target.

One Android-only exception to "permissive", stated plainly: the Android build
links Google Play Billing (`com.android.billingclient:billing:9.1.0`, pulled
in by `in_app_purchase_android`) under the Android Software Development Kit
License, which is a Google platform licence rather than an OSI one. Flutter's
`NOTICES.Z` covers Flutter and Dart packages only and contains no AndroidX,
Kotlin or Billing entry, so it does not reach a Gradle dependency like this
one; the AAR's own `third_party_licenses.txt` lists 65 notices (AndroidX,
Kotlin, Guava and others) and is the attribution set for it, so check that it
still reaches the shipped APK before a Play release. `file_selector_android`'s
bundled aFileChooser notice is a Dart-package notice and does appear in
`NOTICES.Z`.

Platform runtimes (Android system libraries, Apple system frameworks) are
used per their platform terms and are not redistributed by this project.

### Native audio (miniaudio)

| Component | Version | Copyright | License |
|---|---|---|---|
| miniaudio (single header, `runtime/external/miniaudio/miniaudio.h`) | 0.11.26 | David Reid and contributors | Public domain (Unlicense) or MIT-0, at your option |

The unmodified header and its dual licence text are vendored in
`runtime/external/miniaudio/`. Upstream: `mackron/miniaudio`. The runtime
compiles the implementation into `ezcore_runtime`; miniaudio selects the
system audio backend at run time (AAudio/OpenSL on Android, Core Audio on
Apple platforms, WASAPI on Windows, ALSA/PulseAudio/PipeWire on Linux) and
needs no firmware, keys or game content.

## 5. Verification and provenance

- Core catalog artwork records its maintainer-supplied creation statement,
  generation service terms, limitations, and complete file list in
  [`docs/CORE_ART_PROVENANCE.md`](docs/CORE_ART_PROVENANCE.md); the exact
  machine-readable file set and SHA-256 pins live in
  [`docs/CORE_ART_PROVENANCE.json`](docs/CORE_ART_PROVENANCE.json).
- Core artifacts are built from the upstream sources named above and
  **sha256-pinned** per platform in `cores/<id>/manifest.json`.
- `scripts/pin_artifacts.py --check` refuses to assemble a release when the
  staged artifacts don't match the reviewed pins.
- `scripts/banned_content_scan.sh` fails the build if ROM/BIOS/key artifacts
  ever land in the repo; `scripts/release.sh` re-runs it over what ships.

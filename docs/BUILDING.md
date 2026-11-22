# Building from Source

## Prerequisites

Build with **Flutter 3.47.8** on the stable channel. That is the SDK this tree
is developed and tested against, and it ships Dart 3.13, which satisfies the
`^3.12.2` constraint in `pubspec.yaml`. `pubspec.lock` was resolved against it.
Install that version rather than whatever `stable` resolves to on the day you
start: a newer SDK can change analyzer and test results.

### macOS (Apple Silicon)
```bash
# Xcode 26+ (macOS deployment target is 12.0+)
xcode-select --install

# Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Toolchain
brew install cmake ninja pkg-config make rgbds libpng libmad flutter
```

### Linux (Ubuntu 22.04+ / Debian 12+)
```bash
sudo apt update
sudo apt install -y \
  cmake ninja-build pkg-config libpng-dev libgtk-3-dev clang \
  git curl unzip make
# Flutter 3.47.8: https://docs.flutter.dev/get-started/install/linux
```

`--tier-desktop` builds 17 cores, and the toolchain needs two things beyond
that package list:

- **GNU make 4 or newer.** `--tier-desktop` includes `pocketbit` (SameBoy),
  whose BootROM rules use `$(realpath)`, which make 3.81 does not have. The
  recipe checks this and refuses with "GNU make 4+ required for SameBoy"
  rather than building a wrong boot ROM. Check with `make --version`; if your
  distribution still ships 3.81, install GNU make 4 or newer before the
  desktop tier.
- **rgbds.** The SameBoy boot ROMs are assembled from clean-room sources with
  RGBDS. The project's own Linux CI records that RGBDS is unavailable through
  `apt` and therefore runs a core set *without* SameBoy
  (`ci.yml`: "SameBoy excluded: its BootROMs need rgbds (unavailable via
  apt)"); the macOS and iOS CI legs build it. Install RGBDS from
  https://github.com/gbdev/rgbds/releases and put it on `PATH`. The macOS leg
  gets it from Homebrew, as in the macOS block above.

### Windows (x64)
```powershell
# MSYS2
winget install MSYS2.MSYS2
# Then in MSYS2 UCRT64 terminal:
pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja make python git
# Flutter: https://docs.flutter.dev/get-started/install/windows
```

### Android
```bash
# Android Studio or command line tools
# NDK r27c (27.2.12479018), CMake 3.22.1, Platform android-34
# Set ANDROID_NDK_HOME, ANDROID_SDK_ROOT
```

### iOS
```bash
# macOS only
# Xcode 15+, CocoaPods: `sudo gem install cocoapods`
# Apple Developer account for device deploy / TestFlight
```

## One-Command Bootstrap (macOS arm64 host)

`scripts/prereqs.sh` installs the toolchain with Homebrew, so this sequence
runs on an Apple Silicon Mac only:

```bash
git clone https://github.com/0xJ1nn/ezcore.git
cd ezcore
scripts/prereqs.sh                    # installs toolchain via Homebrew
scripts/build_core.sh --fetch-headers # vendors libretro.h
scripts/build_runtime.sh macos        # builds runtime + CTest
scripts/build_core.sh --tier1         # first five cores (GB/GBC, GBA, SNES, Genesis, DOS)
python3 scripts/build_catalog.py      # merges manifests → cores/catalog.json (required asset)
flutter analyze && flutter test       # gates
flutter run -d macos                  # debug run
```

On the other four hosts, install the tools in their sections above and use
the matching row below; `scripts/prereqs.sh` is not a Linux, Windows, Android
or iOS installer. The header, catalog and gate commands are host-independent,
and `flutter run -d <target>` names the device for that host (`linux`,
`windows`, `android` or an attached iOS device). Building for iOS needs macOS
and Xcode; Windows needs an MSYS2 host; Android needs the NDK.

## Platform Build Commands

| Target | Build host | Runtime | Cores | Flutter |
|--------|-----------|---------|-------|---------|
| macOS arm64 | macOS arm64 | `scripts/build_runtime.sh macos` | `scripts/build_core.sh --tier1` | `flutter build macos --release` |
| Linux x64 | Linux x64 | `scripts/build_runtime.sh linux` | `EZCORE_PLATFORM=linux scripts/build_core.sh --tier-desktop` | `flutter build linux --release` |
| Windows x64 | Windows x64 (MSYS2) | `scripts/build_runtime.sh windows` (MSYS2) | `EZCORE_PLATFORM=windows scripts/build_core.sh --tier-desktop` | `flutter build windows --release` (MSYS2) |
| Android arm64 | host with the Android NDK (CI uses Linux x64) | `scripts/build_runtime.sh android` | `EZCORE_PLATFORM=android scripts/build_core.sh --tier-android` | `flutter build apk --release` |
| iOS arm64 | macOS with Xcode | `scripts/build_runtime.sh ios` | `EZCORE_PLATFORM=ios scripts/build_core.sh --tier-ios` | `flutter build ios --no-codesign` (compile check only) |

## Core Tiers

| Tier | Cores | Platforms |
|------|---------|-----------|
| `--tier1` | GB/GBC, GBA, SNES, Genesis, DOS (5 cores) | All |
| `--tier-desktop` | All desktop cores (17) | macOS, Linux, Windows |
| `--tier-android` | Mobile tier (10 cores) | Android |
| `--tier-ios` | Interpreter-only tier (9 cores) | iOS |

`--tier1` is five cores, not six, and not all five are run-verified. On Linux
x64 `pocketbit` (GB/GBC) and `advancebit` (GBA) hold RENDERS against recorded
frames. `realmode` (DOS) has a recorded boot that opens the DOS start menu, but
it refuses to serialize until a program runs, so no frame was kept. `superfx`
(SNES) has no Linux cell at all and stops at IDENTIFIES on macOS; `blastproc`
(Genesis) is BUILT on Linux with no recorded frame. Both are non-commercial
upstream, so no binary of either ever ships — those two recipes exist to prove
the build.

The same tier means different evidence on the other targets: Android cells
are ELF and symbol checks on the built arm64 artifacts, with no on-device core
run recorded here; iOS cells are dated build evidence with no current
`ios-arm64` artifact pins; Windows x64 has no per-core boot evidence. A core
result on one target proves that target alone. [`MATRIX.md`](MATRIX.md) is the
per-core record; read it before quoting a tier as proven on any platform.

## Fetching the emulator sources

Cores are not vendored. `scripts/build_core.sh` clones **23 upstream
repositories** at build time — one for the libretro header (`--fetch-headers`,
into `runtime/external/libretro-common`) plus one per core recipe — and six of
those recipes then run `git submodule update --init --recursive` (PPSSPP,
Flycast, FBNeo, Dolphin, LRPS2, and Play!, which nests zstd/xxHash/zlib). Both
destination directories are gitignored and never committed, so a second
checkout starts empty.

Building cores therefore needs network access and enough disk for the upstream
trees (PPSSPP and Dolphin are the large ones). Only **three** recipes pin a
commit: `dualvu` (`d44bfa1`), `potator` (`227c5f6`) and `gw` (`91d599b`); they
check out that SHA after cloning and fetch it when the shallow clone does not
have it. Every other recipe tracks the upstream default branch as of the day
you build, so two builds weeks apart can produce different binaries and
different `SHA256SUMS`. The sha256 pins in `cores/<id>/manifest.json` describe
the bytes the maintainers built and reviewed, not whatever a fresh clone
produces — verify rather than assume a local build matches.

## Release Build

A release needs the signing secrets for the platform (below), notes taken from
`CHANGELOG.md`, and a checksum file a reader can verify against what they
downloaded. The release workflow generates that file over the artifacts it
attaches; the same file can be produced and re-verified locally:

```bash
python3 scripts/checksums.py --write --root dist --record SHA256SUMS.txt
python3 scripts/checksums.py --check --root dist --record SHA256SUMS.txt
```

A directory is described by every regular file below it, sorted; `.git`
internals are never included, and the record never lists itself. `--check`
names any file whose bytes changed, any file the record omits and any entry
for a path that is no longer there, so a run after the final build names
exactly what changed. No record of the source tree is committed: it would go
stale as soon as any pull request edits a tracked file, and git already names
every commit by the hash of its contents.

```bash
# Requires: all cores built + pinned for target platform
# macOS (ad-hoc sign):
scripts/release.sh macos --out dist/
# macOS (notarized, needs Apple Dev identity):
EZCORE_CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/release.sh macos --out dist/

# Windows:
scripts/release.sh windows --out dist/

# Linux:
scripts/release.sh linux --out dist/

# Android (needs the maintainer's release keystore):
EZCORE_KEYSTORE_FILE="$PWD/ezcore-release.keystore" \
EZCORE_KEYSTORE_PASSWORD=... EZCORE_KEY_ALIAS=ezcore EZCORE_KEY_PASSWORD=... \
scripts/release.sh android --out dist/

# iOS: no signed release pipeline exists in this tree. The script stops
# after an unsigned `flutter build ios --no-codesign` and exits without an
# archive or an .ipa. A device build needs a signing identity and embedded
# core frameworks outside this repository.
scripts/release.sh ios --out dist/
```

### Android release signing

Android release builds read four values: `EZCORE_KEYSTORE_FILE`,
`EZCORE_KEYSTORE_PASSWORD`, `EZCORE_KEY_ALIAS` and `EZCORE_KEY_PASSWORD`. Each
may be set in the environment or as a Gradle property of the same name in
`~/.gradle/gradle.properties`. When none are set the build falls back to the
debug keys, which is enough for a local check but not for distribution. Never
commit the keystore or its passwords. For Play releases, Google Play App
Signing holds the app signing key; the key used to sign the uploaded bundle is
the upload key.

Outputs:
- macOS arm64: `dist/ezcore-<version>-macos-arm64.zip` (ad-hoc signed without an Apple Developer identity)
- Windows x64: `dist/ezcore-<version>-windows-x64.zip`
- Linux x64: `dist/ezcore-<version>-linux-x64.tar.gz`
- Android arm64: `dist/ezcore-<version>-android-arm64.apk` (debug-signed without the release keystore)
- iOS arm64: none. `scripts/release.sh ios` produces an unsigned compile check
  only — no archive, no `.ipa` and no signed frameworks — and reports success
  without a shippable artifact.

An end-to-end release needs all five targets: iOS, Android, macOS arm64,
Linux x64 and Windows x64. The Linux x64 chain is the only one with published
and pinned core assets; Android has an app artifact but no on-device core boot
evidence. macOS arm64 and Windows x64 need their own build hosts, and a
notarised macOS build needs Apple credentials. iOS needs a Mac with Xcode, a
signed archive pipeline and a device or TestFlight run, none of which this
tree provides. The release workflow currently drafts only macOS, Windows and
Linux. These are blockers to a complete release, not targets that can be
dropped; see [`MATRIX.md`](MATRIX.md) for the evidence behind each row.

## Verification Gates (CI Equivalent)

```bash
# Data integrity
python3 scripts/fill_manifest_data.py --check
python3 scripts/build_catalog.py
bash scripts/banned_content_scan.sh

# Native pins (must match committed manifest.json; requires the full
# desktop tier staged — a tier1-only checkout will (correctly) fail this)
python3 scripts/pin_artifacts.py macos-arm64 --out native/cores --check

# Dart
flutter analyze lib/ test/
flutter test

# Native CTest (runtime); run the build directory for your host:
# runtime/build-macos on macOS, runtime/build-linux on Linux
cd runtime/build-macos && ctest --output-on-failure

# Core matrix (Dart-driven, fork-isolated)
flutter test test/core_matrix_test.dart
```

## Adding a New Core

1. **Verify licensing**: Open-source libretro core, compatible license (MPL-2.0, MIT, BSD, GPL-2.0+, LGPL), no DMCA 1201 exposure, no Nintendo/Sony/Sega IP.
2. **Add manifest**: `cores/<id>/manifest.json` (see existing for schema)
3. **Add the build recipe**: `scripts/build_core.sh` — `build_<id>()` (the
   platform variables it uses come from `scripts/core_platform.sh`).
4. **Build & test**: `scripts/build_core.sh <id>` → verify `RENDERS` on target platform
5. **Pin artifacts**: `python3 scripts/pin_artifacts.py <platform> --out native/cores`
6. **Update policy**: `scripts/fill_manifest_data.py` (add to EXECUTION/CHEATS/DELIVERY maps)
7. **Regenerate catalog**: `python3 scripts/build_catalog.py`
8. **PR with**: manifest.json changes, catalog.json, pin diffs, test evidence

See [CORE_SYSTEM.md](CORE_SYSTEM.md) for full architecture.

## Troubleshooting

### "libretro.h not found"
```bash
scripts/build_core.sh --fetch-headers
```

### SameBoy build fails (parallel pb12 race)
```bash
# Build serially (default for single core)
scripts/build_core.sh sameboy
```

### Flutter analyze fails on generated files
```bash
flutter clean
flutter pub get
flutter analyze
```

### Android NDK version mismatch
```bash
# Ensure NDK r27c
export ANDROID_NDK_HOME=/usr/local/lib/android/sdk/ndk/27.2.12479018
```

### iOS "Pods-Runner" config errors
```bash
cd ios
pod deintegrate
pod install
# Ensure Flutter-Generated.xcconfig exists (run flutter pub get first)
```

### Core matrix test fails
- Ensure `native/cores/` has staged `.dylib`/`.so`/`.dll` files
- Run `python3 scripts/build_catalog.py` first
- Check `test/core_matrix_test.dart` for platform-specific skips

## Architecture Overview

```
Flutter UI (lib/)          → Dart
    ↓ FFI (lib/runtime/)   → C ABI (runtime/include/ezcore_runtime.h)
ezCore Runtime (runtime/)  → C11, no external runtime dependencies
    ↓ dlopen
libretro Cores (native/cores/) → C/C++, libretro API
```

Key files:
- `runtime/include/ezcore_runtime.h` — stable ABI v1
- `runtime/src/runtime.c` — session lifecycle, AV, saves, cheats
- `lib/runtime/ezcore_runtime.dart` — Dart FFI bindings
- `cores/<id>/manifest.json` — versioned plugin index (pins, execution, delivery)
- `cores/catalog.json` — merged manifest index (Flutter asset)

## License Compliance

- App shell: GPL-3.0-only
- Each core: upstream license in `manifest.json` (`license`, `license_url`)
- Fonts: SIL OFL 1.1 (assets/fonts/README.md)
- Brand assets: proprietary (do not redistribute modified)

Never commit:
- ROMs, BIOS, firmware, keys
- Cheat databases
- Compiled core binaries (`.dylib`, `.so`, `.dll`) — gitignored, built via scripts
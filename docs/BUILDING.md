# Building from Source

## Prerequisites

### macOS (Apple Silicon)
```bash
# Xcode 15+ (Xcode 27 for macOS 15.0+ deployment)
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
  git curl unzip
# Flutter: https://docs.flutter.dev/get-started/install/linux
```

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

## One-Command Bootstrap (macOS)

```bash
git clone https://github.com/JinUltimate1995/ezcore.git
cd ezcore
scripts/prereqs.sh                    # installs toolchain via Homebrew
scripts/build_core.sh --fetch-headers # vendors libretro.h
scripts/build_runtime.sh macos        # builds runtime + CTest
scripts/build_core.sh --tier1         # builds 6 verified cores (GB/GBC/GBA/NES/SNES/Genesis)
python3 scripts/build_catalog.py      # merges manifests → cores/catalog.json (required asset)
flutter analyze && flutter test       # gates
flutter run -d macos                  # debug run
```

## Platform Build Commands

| Platform | Runtime | Cores | Flutter |
|----------|---------|-------|---------|
| macOS | `scripts/build_runtime.sh macos` | `scripts/build_core.sh --tier1` | `flutter build macos --release` |
| Linux | `scripts/build_runtime.sh linux` | `EZCORE_PLATFORM=linux scripts/build_core.sh --tier-desktop` | `flutter build linux --release` |
| Windows | `scripts/build_runtime.sh windows` (MSYS2) | `EZCORE_PLATFORM=windows scripts/build_core.sh --tier-desktop` | `flutter build windows --release` (MSYS2) |
| Android | `scripts/build_runtime.sh android` | `EZCORE_PLATFORM=android scripts/build_core.sh --tier-android` | `flutter build apk --release` |
| iOS | `scripts/build_runtime.sh ios` | `EZCORE_PLATFORM=ios scripts/build_core.sh --tier-ios` | `flutter build ios --no-codesign` |

## Core Tiers

| Tier | Systems | Platforms |
|------|---------|-----------|
| `--tier1` | GB/GBC/GBA/NES/SNES/Genesis | All (fast, verified) |
| `--tier-desktop` | All desktop cores (18) | macOS, Linux, Windows |
| `--tier-android` | Mobile-verified (10) | Android |
| `--tier-ios` | Interpreter-only (9) | iOS |

## Release Build

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

# Android (needs keystore env vars):
EZCORE_KEYSTORE_FILE=keystore.jks EZCORE_KEYSTORE_PASSWORD=... \
EZCORE_KEY_ALIAS=... EZCORE_KEY_PASSWORD=... \
scripts/release.sh android --out dist/

# iOS (needs signing identity + embedded frameworks):
EZCORE_IOS_SIGNING_IDENTITY="..." scripts/release.sh ios --out dist/
```

Outputs:
- macOS: `dist/ezcore-<version>-macos-arm64.zip`
- Windows: `dist/ezcore-<version>-windows-x64.zip`
- Linux: `dist/ezcore-<version>-linux-x64.tar.gz`
- Android: `dist/ezcore-<version>-android-arm64.apk`

## Verification Gates (CI Equivalent)

```bash
# Data integrity
python3 scripts/fill_manifest_data.py --check
python3 scripts/build_catalog.py
bash scripts/banned_content_scan.sh

# Native pins (must match committed manifest.json)
python3 scripts/pin_artifacts.py macos-arm64 --out native/cores --check

# Dart
flutter analyze lib/ test/
flutter test

# Native CTest (runtime)
cd runtime/build-macos && ctest --output-on-failure

# Core matrix (Dart-driven, fork-isolated)
flutter test test/core_matrix_test.dart
```

## Adding a New Core

1. **Verify legal**: Open-source libretro core, compatible license (MPL-2.0, MIT, BSD, GPL-2.0+, LGPL), no DMCA 1201 exposure, no Nintendo/Sony/Sega IP.
2. **Add manifest**: `cores/<id>/manifest.json` (see existing for schema)
3. **Add build recipe**: `scripts/core_platform.sh` — define `build_<id>()` function
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
ezCore Runtime (runtime/)  → C99, no deps
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
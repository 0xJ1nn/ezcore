#!/usr/bin/env bash
# Platform layer for scripts/build_core.sh (sourced, not executed).
#
#   EZCORE_PLATFORM: macos | linux | windows | android | ios (default macos)
#   EZCORE_ARCH:     arch per platform (defaults: macos arm64, linux x64,
#                    windows x64, android arm64-v8a, ios arm64)
#   EZCORE_OUT_DIR:  staging root override (default native/cores-<plat>-<arch>
#                    for cross builds, native/cores for macos host default)
#
# Provides: PLATFORM, ARCH, PLAT_KEY (manifest artifacts key, e.g.
# android-arm64), LIB_SUFFIX, MAKE_PLATFORM (libretro `platform=` value or
# empty for native make), toolchain env setup, and interpreter enforcement
# for iOS (manifest rule: ios must never resolve to dynarec).
# shellcheck disable=SC2034

PLATFORM="${EZCORE_PLATFORM:-macos}"

default_arch() {
  case "$PLATFORM" in
    macos) echo arm64 ;;
    linux) echo x64 ;;
    windows) echo x64 ;;
    android) echo arm64-v8a ;;
    ios) echo arm64 ;;
  esac
}

ARCH="${EZCORE_ARCH:-$(default_arch)}"

case "$PLATFORM" in
  macos)   LIB_SUFFIX=dylib; MAKE_PLATFORM="";         PLAT_KEY="macos-$ARCH" ;;
  linux)   LIB_SUFFIX=so;    MAKE_PLATFORM="platform=unix"; PLAT_KEY="linux-$ARCH" ;;
  windows) LIB_SUFFIX=dll;   MAKE_PLATFORM="platform=windows"; PLAT_KEY="windows-$ARCH" ;;
  # Android make builds use plain `platform=unix` + the NDK clang from
  # android_toolchain: per-core `platform=android` branches are 32-bit
  # ARMv7-era (gambatte/stella/snes9x fall through to windows; mupen64plus
  # and ppsspp pin arm-linux-androideabi-gcc). CMake cores (mgba) use the
  # NDK toolchain file instead and ignore MAKE_PLATFORM.
  android) LIB_SUFFIX=so;    MAKE_PLATFORM="platform=unix"; PLAT_KEY="android-arm64" ;;
  # iOS defaults to ios-arm64: plain `platform=ios` means armv7 in every
  # libretro makefile in our matrix (swanstation excepted, and it is
  # refused on iOS before make runs).
  ios)     LIB_SUFFIX=dylib; MAKE_PLATFORM="platform=ios-arm64"; PLAT_KEY="ios-arm64" ;;
  *) echo "unknown EZCORE_PLATFORM: $PLATFORM" >&2; exit 2 ;;
esac

if [ -n "${EZCORE_OUT_DIR:-}" ]; then
  OUT_DIR="$EZCORE_OUT_DIR"
elif [ "$PLATFORM" = macos ] && [ "$ARCH" = arm64 ]; then
  OUT_DIR="$ROOT/native/cores"
else
  OUT_DIR="$ROOT/native/cores-$PLATFORM-$ARCH"
fi

# iOS interpreter enforcement: JIT-capable cores refuse here unless the
# recipe passes an explicit interpreter-forcing flag (audit trail in MATRIX).
require_interpreter_ios() { # id flag-description...
  local id="$1"; shift
  if [ "$PLATFORM" = ios ] && [ "$#" -eq 0 ]; then
    echo "REFUSED: $id needs an explicit interpreter flag for iOS (manifest execution.ios=interpreter)" >&2
    exit 5
  fi
}

# Boot-ROM builders (SameBoy) invoke $(PYTHON); make it explicit everywhere.
export PYTHON="${PYTHON:-python3}"

# iOS min-version repair: core makefiles set -miphoneos-version-min for
# compiles but rarely for the link, leaving minos == SDK (uninstallable on
# older devices, rejected next to the app target). Rewrites LC_BUILD_VERSION
# in place; unsigned at this stage so no signature is disturbed.
# Floor is 15.0 (Xcode 27 minimum; keep in sync with ios/Podfile).
IOS_MINOS="15.0"
ios_fix_min_version() { # file
  [ "$PLATFORM" = ios ] || return 0
  local sdk
  sdk="$(xcrun --sdk iphoneos --show-sdk-version)"
  xcrun vtool -arch "$ARCH" -set-build-version ios "$IOS_MINOS" "$sdk" \
    -output "$1.fixed" "$1" && mv "$1.fixed" "$1"
  # A cross-built dylib can carry more than one LC_BUILD_VERSION (a macOS
  # entry from the upstream toolchain plus the iOS one we set). Only the IOS
  # entry governs App Store validation; read that one, not the first minos.
  local shown minos
  shown="$(vtool -show-build "$1")"
  if ! printf '%s\n' "$shown" | grep -A4 -E "platform[[:space:]]+IOS" \
      | grep -qE "minos[[:space:]]+$IOS_MINOS"; then
    echo "REFUSED: minos repair failed for $1" >&2
    return 1
  fi
  minos="$(printf '%s\n' "$shown" | grep -A4 -E "platform[[:space:]]+IOS" | grep minos | head -n 1)"
  echo "-- minos check: $minos"
}

android_toolchain() {
  : "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME (sdkmanager ndk bundle)}"
  local tc="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin"
  [ -d "$tc" ] || tc="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
  export PATH="$tc:$PATH"
  # Compiler goes through a wrapper that drops -lrt (no librt in the NDK;
  # bionic libc covers it). Several upstream makefiles add -lrt
  # unconditionally; argv is otherwise preserved byte-exact.
  export REAL_CC="$tc/aarch64-linux-android21-clang"
  export REAL_CXX="$tc/aarch64-linux-android21-clang++"
  export CC="$ROOT/scripts/android-wrappers/clang"
  export CXX="$ROOT/scripts/android-wrappers/clang++"
  export AR="llvm-ar" RANLIB="llvm-ranlib"
  # Host strip cannot read ELF: point STRIP at llvm-strip (dosbox-pure and
  # friends honor $(STRIP) with fallback to host strip).
  export STRIP="$tc/llvm-strip"
}

ios_toolchain() {
  # libretro `platform=ios` fragments add -arch/-isysroot themselves from
  # IOSSDK; CC must stay a plain compiler or sub-makes misparse it.
  export IOSSDK
  IOSSDK="$(xcrun --sdk iphoneos --show-sdk-path)"
  export CC="clang"
  export CXX="clang++"
}

#!/usr/bin/env bash
# Builds the ezCore C runtime + synthetic test core for one platform.
# Usage:
#   scripts/build_runtime.sh macos        # arm64 host (also: macos-x64 via ARCH)
#   scripts/build_runtime.sh linux        # x86_64 (native or CI ubuntu runner)
#   scripts/build_runtime.sh windows      # x86_64 (CI windows runner, MSVC)
#   scripts/build_runtime.sh android      # arm64-v8a (+ ANDROID_ABI override)
#   scripts/build_runtime.sh ios          # arm64 device (EFFECTIVE_PLATFORM_NAME)
#
# Outputs land in runtime/build-<platform>/ (never the Flutter build/ dir).
# Requires: scripts/build_core.sh --fetch-headers (vendored libretro.h).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${1:-macos}"
BUILD_DIR="$ROOT/runtime/build-$PLATFORM"
GENERATOR="${CMAKE_GENERATOR:-Ninja}"

if [ ! -f "$ROOT/runtime/external/libretro-common/include/libretro.h" ]; then
  echo "libretro.h not vendored. Run scripts/build_core.sh --fetch-headers first." >&2
  exit 2
fi

cmake_args=(-S "$ROOT/runtime" -B "$BUILD_DIR" -G "$GENERATOR" -DCMAKE_BUILD_TYPE=Release)

case "$PLATFORM" in
  macos)
    ARCH="${ARCH:-arm64}"
    cmake_args+=(-DCMAKE_OSX_ARCHITECTURES="$ARCH")
    ;;
  linux)
    ;; # native gcc on the linux runner
  windows)
    ;; # native MSVC on the windows runner (Ninja + cl)
  android)
    : "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME (sdkmanager ndk bundle)}"
    ABI="${ANDROID_ABI:-arm64-v8a}"
    cmake_args+=(
      -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
      -DANDROID_ABI="$ABI" -DANDROID_PLATFORM=android-21
    )
    ;;
  ios)
    # Device arm64 without code signing (CI builds the dylib; Xcode signs
    # the bundled copy at app-archive time). Floor 15.0 = Xcode 27 minimum.
    cmake_args+=(
      -DCMAKE_SYSTEM_NAME=iOS
      -DCMAKE_OSX_ARCHITECTURES=arm64
      -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0
      -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
    )
    ;;
  *)
    echo "unknown platform: $PLATFORM (macos|linux|windows|android|ios)" >&2
    exit 2
    ;;
esac

cmake "${cmake_args[@]}"
cmake --build "$BUILD_DIR" -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"

case "$PLATFORM" in
  macos | linux)
    (cd "$BUILD_DIR" && ctest --output-on-failure)
    ;;
  *)
    echo "OK: runtime built for $PLATFORM (tests run on host CI legs)"
    ;;
esac
echo "OK: $BUILD_DIR"

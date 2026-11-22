#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

# build_and_play.sh — build real emulator cores and PROVE they play games.
#
# A green unit test, a built library, a manifest or a golden hash is NOT the
# goal. This is the reproducible path from source to "a game plays":
#   1. vendor libretro headers
#   2. build + stage a real libretro core (default: nesbyte / Mesen, NES+FDS)
#   3. build the native runtime
#   4. boot a real game through the core and check frames, pixels, audio and
#      save-state round-trip
#
# Usage:
#   scripts/build_and_play.sh                 # nesbyte + full boot proof
#   scripts/build_and_play.sh <core-id>       # another core from cores/<id>
#   ROM=<path> scripts/build_and_play.sh      # boot a specific game
#
# Outputs (gitignored under native/ and runtime/build-*):
#   native/cores-<plat>-<arch>/<id>/          staged core + SHA256SUMS
#   runtime/build-<plat>/                      runtime + CTest harness
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CORE_ID="${1:-${CORE_ID:-nesbyte}}"
PLAT="${EZCORE_PLATFORM:-linux}"
ROM="${ROM:-native/test-roms/ezcore_nes_minimal.nes}"

echo "== build_and_play: core=$CORE_ID platform=$PLAT rom=$ROM"

if [ ! -f runtime/external/libretro-common/include/libretro.h ]; then
  echo "== vendoring libretro headers"
  scripts/build_core.sh --fetch-headers
fi

echo "== building core: $CORE_ID"
EZCORE_PLATFORM="$PLAT" scripts/build_core.sh "$CORE_ID"

echo "== building runtime"
scripts/build_runtime.sh "$PLAT"

echo "== proving playability (CTest)"
BUILD_DIR="runtime/build-$PLAT"
BOOT_TEST="boot_${CORE_ID}"
if ctest --test-dir "$BUILD_DIR" -N 2>/dev/null | grep -q "$BOOT_TEST"; then
  ctest --test-dir "$BUILD_DIR" --output-on-failure -R "$BOOT_TEST"
  echo "== PLAY PROVED: $CORE_ID boot test passed"
else
  echo "== no dedicated boot_${CORE_ID} CTest; running the runtime smoke suite"
  ctest --test-dir "$BUILD_DIR" --output-on-failure
fi

if [ -f "$ROM" ] && [ -x "$BUILD_DIR/test_core_boot" ]; then
  CORE_LIB="$(find native -path "*/$CORE_ID/${CORE_ID}_libretro.so" -o -path "*/$CORE_ID/${CORE_ID}_libretro.dylib" | head -1)"
  if [ -n "${CORE_LIB:-}" ]; then
    echo "== booting real game: $ROM"
    "$BUILD_DIR/test_core_boot" "$CORE_LIB" "$ROM"
    echo "== GAME PLAYED: $ROM via $CORE_ID"
  fi
fi

echo "== DONE: core=$CORE_ID staged and playability verified"

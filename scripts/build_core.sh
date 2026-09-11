#!/usr/bin/env bash
# Builds libretro core plugins from upstream source into build/cores/<id>/.
# Usage:
#   scripts/build_core.sh --fetch-headers      # vendor libretro.h (once)
#   scripts/build_core.sh sameboy              # build one core
#   scripts/build_core.sh --tier1              # build all run-verified cores
# Legal holds (citra_hold, switch_hold, ps2_hold) refuse to build. This is
# deliberate — see cores/<id>/manifest.json blocked_reason.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# NOTE: never use Flutter's build/ dir — `flutter clean` would wipe cores.
SRC_DIR="$ROOT/native/src"
OUT_DIR="$ROOT/native/cores"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"

clone() { # repo dest (shallow, pinned branch/tag when known)
  local repo="$1" dest="$2" ref="${3:-}"
  if [ -d "$dest/.git" ]; then
    echo "-- $dest exists, skipping clone"
    return 0
  fi
  git clone --depth 1 ${ref:+--branch "$ref"} "$repo" "$dest"
}

fetch_headers() {
  clone https://github.com/libretro/libretro-common.git \
    "$ROOT/bridge/external/libretro-common"
  test -f "$ROOT/bridge/external/libretro-common/include/libretro.h"
  echo "OK: libretro.h vendored"
}

stage() { # id file
  local id="$1" file="$2"
  mkdir -p "$OUT_DIR/$id"
  cp "$file" "$OUT_DIR/$id/${id}_libretro.dylib"
  (cd "$OUT_DIR/$id" && shasum -a 256 "${id}_libretro.dylib" | tee SHA256SUMS)
}

# ---------------- TIER 1: run-verified recipes (macOS arm64) ----------------

build_sameboy() {
  clone https://github.com/LIJI32/SameBoy.git "$SRC_DIR/SameBoy"
  make -C "$SRC_DIR/SameBoy" -j"$JOBS" libretro
  stage sameboy "$SRC_DIR/SameBoy/build/bin/sameboy_libretro.dylib"
}

build_gambatte() {
  clone https://github.com/libretro/gambatte-libretro.git "$SRC_DIR/gambatte-libretro"
  make -C "$SRC_DIR/gambatte-libretro" -f Makefile.libretro -j"$JOBS"
  stage gambatte "$SRC_DIR/gambatte-libretro/gambatte_libretro.dylib"
}

build_mgba() {
  clone https://github.com/libretro/mgba.git "$SRC_DIR/mgba-libretro"
  cmake -S "$SRC_DIR/mgba-libretro" -B "$SRC_DIR/mgba-libretro/build" \
    -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_LIBRETRO=ON -DBUILD_QT=OFF -DBUILD_SDL=OFF -DBUILD_SUITE=OFF \
    -DBUILD_TEST=OFF -DBUILD_PYTHON=OFF -DBUILD_EXAMPLE=OFF \
    -DBUILD_PERF=OFF -DBUILD_CINEMA=OFF -DBUILD_HEADLESS=OFF
  cmake --build "$SRC_DIR/mgba-libretro/build" --target mgba_libretro -j"$JOBS"
  stage mgba "$SRC_DIR/mgba-libretro/build/mgba_libretro.dylib"
}

build_snes9x() {
  clone https://github.com/snes9xgit/snes9x.git "$SRC_DIR/snes9x"
  make -C "$SRC_DIR/snes9x/libretro" -j"$JOBS"
  stage snes9x "$SRC_DIR/snes9x/libretro/snes9x_libretro.dylib"
}

build_genesis_plus_gx() {
  clone https://github.com/libretro/Genesis-Plus-GX.git "$SRC_DIR/Genesis-Plus-GX"
  make -C "$SRC_DIR/Genesis-Plus-GX" -f Makefile.libretro -j"$JOBS"
  stage genesis_plus_gx "$SRC_DIR/Genesis-Plus-GX/genesis_plus_gx_libretro.dylib"
}

build_dosbox_pure() {
  clone https://github.com/libretro/dosbox-pure.git "$SRC_DIR/dosbox-pure"
  make -C "$SRC_DIR/dosbox-pure" -j"$JOBS"
  stage dosbox_pure "$SRC_DIR/dosbox-pure/dosbox_pure_libretro.dylib"
}

# ------------- TIER 2: scripted, awaiting first verified run -------------
# Each exits 3 until its recipe has produced a dylib once on this machine.
unverified() { echo "UNVERIFIED recipe: $1 — see script source"; exit 3; }

build_mesen()            { unverified "mesen (Mesen2 libretro target TBD)"; }
build_stella()           { unverified "stella (stella2014 libretro makefile TBD)"; }
build_scummvm()          { unverified "scummvm (in-tree libretro backend configure TBD)"; }
build_beetle_pce()       { unverified "beetle-pce-fast Makefile.libretro TBD"; }
build_swanstation()      { unverified "swanstation cmake libretro target TBD"; }
build_mupen64plus()      { unverified "mupen64plus-nx make target TBD"; }
build_melonds()          { unverified "melonDS libretro source location TBD"; }
build_ppsspp()           { unverified "ppsspp libretro build + submodules TBD"; }
build_flycast()          { unverified "flycast libretro make flags TBD"; }
build_dolphin()          { unverified "dolphin libretro cmake flags TBD"; }
build_beetle_saturn()    { unverified "beetle-saturn Makefile.libretro TBD"; }
build_fbneo()            { unverified "fbneo libretro makefile TBD + lawyer gate"; }

# ---------------- Legal holds: always refuse ----------------
hold() { echo "REFUSED: $1"; exit 4; }
build_citra_hold()  { hold "3DS core on legal hold (see cores/citra_hold/manifest.json)"; }
build_switch_hold() { hold "Switch core on legal hold (see cores/switch_hold/manifest.json)"; }
build_ps2_hold()    { hold "No shippable PS2 core (see cores/ps2_hold/manifest.json)"; }

TIER1="sameboy gambatte mgba snes9x genesis_plus_gx dosbox_pure"

cmd="${1:-}"
case "$cmd" in
  --fetch-headers) fetch_headers ;;
  --tier1) for c in $TIER1; do "build_${c}"; done ;;
  ""|--help|-h) sed -n '2,9p' "$0" ;;
  *) "build_${cmd//-/_}" ;;
esac

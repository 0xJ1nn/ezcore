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

build_swanstation() {
  clone https://github.com/libretro/swanstation.git "$SRC_DIR/swanstation"
  make -C "$SRC_DIR/swanstation" -f Makefile.libretro -j"$JOBS"
  stage swanstation "$SRC_DIR/swanstation/swanstation_libretro.dylib"
}

build_ppsspp() {
  clone https://github.com/hrydgard/ppsspp.git "$SRC_DIR/ppsspp"
  (cd "$SRC_DIR/ppsspp" && git submodule update --init --depth 1 --recursive)
  make -C "$SRC_DIR/ppsspp/libretro" -j"$JOBS"
  stage ppsspp "$SRC_DIR/ppsspp/libretro/ppsspp_libretro.dylib"
}

build_mesen() {
  clone https://github.com/libretro/Mesen.git "$SRC_DIR/Mesen"
  make -C "$SRC_DIR/Mesen/Libretro" -j"$JOBS"
  stage mesen "$SRC_DIR/Mesen/Libretro/mesen_libretro.dylib"
}

build_melonds() {
  clone https://github.com/libretro/melonDS.git "$SRC_DIR/melonDS-libretro"
  make -C "$SRC_DIR/melonDS-libretro" -j"$JOBS"
  stage melonds "$SRC_DIR/melonDS-libretro/melonds_libretro.dylib"
}

build_stella() {
  clone https://github.com/libretro/stella2023.git "$SRC_DIR/stella2023"
  make -C "$SRC_DIR/stella2023/src/os/libretro" -j"$JOBS"
  stage stella "$SRC_DIR/stella2023/src/os/libretro/stella2023_libretro.dylib"
}

build_beetle_pce() {
  clone https://github.com/libretro/beetle-pce-fast-libretro.git "$SRC_DIR/beetle-pce"
  # SYSTEM_ZLIB=1: vendored zlib-1.2.11 does not compile against the Xcode 27
  # SDK (_stdio.h collision); macOS system zlib is API-compatible.
  # Same posture as beetle-saturn's osx block.
  make -C "$SRC_DIR/beetle-pce" -j"$JOBS" SYSTEM_ZLIB=1
  stage beetle_pce "$SRC_DIR/beetle-pce/mednafen_pce_fast_libretro.dylib"
}

build_beetle_saturn() {
  clone https://github.com/libretro/beetle-saturn-libretro.git "$SRC_DIR/beetle-saturn"
  make -C "$SRC_DIR/beetle-saturn" -j"$JOBS"
  stage beetle_saturn "$SRC_DIR/beetle-saturn/mednafen_saturn_libretro.dylib"
}

build_mupen64plus() {
  clone https://github.com/libretro/mupen64plus-libretro-nx.git "$SRC_DIR/mupen64plus-nx"
  # SYSTEM_LIBPNG/ZLIB: vendored libpng hits the TARGET_OS_MAC/fp.h SDK rot
  # and vendored zlib-1.2.11 hits the _stdio.h rot (same as beetle-pce).
  make -C "$SRC_DIR/mupen64plus-nx" -j"$JOBS" SYSTEM_LIBPNG=1 SYSTEM_ZLIB=1
  stage mupen64plus "$SRC_DIR/mupen64plus-nx/mupen64plus_next_libretro.dylib"
}

build_flycast() {
  clone https://github.com/flyinghead/flycast.git "$SRC_DIR/flycast"
  (cd "$SRC_DIR/flycast" && git submodule update --init --depth 1 --recursive)
  cmake -S "$SRC_DIR/flycast" -B "$SRC_DIR/flycast/build-libretro" \
    -G Ninja -DCMAKE_BUILD_TYPE=Release -DLIBRETRO=ON
  cmake --build "$SRC_DIR/flycast/build-libretro" -j"$JOBS"
  stage flycast "$SRC_DIR/flycast/build-libretro/flycast_libretro.dylib"
}

build_fbneo() {
  clone https://github.com/libretro/FBNeo.git "$SRC_DIR/FBNeo"
  (cd "$SRC_DIR/FBNeo" && git submodule update --init --depth 1 --recursive)
  make -C "$SRC_DIR/FBNeo/src/burner/libretro" -j"$JOBS"
  stage fbneo "$SRC_DIR/FBNeo/src/burner/libretro/fbneo_libretro.dylib"
}

build_scummvm() {
  clone https://github.com/scummvm/scummvm.git "$SRC_DIR/scummvm"
  make -C "$SRC_DIR/scummvm/backends/platform/libretro" -j"$JOBS"
  stage scummvm "$SRC_DIR/scummvm/backends/platform/libretro/scummvm_libretro.dylib"
}

build_dolphin() {
  clone https://github.com/libretro/dolphin.git "$SRC_DIR/dolphin-libretro"
  (cd "$SRC_DIR/dolphin-libretro" && git submodule update --init --depth 1 --recursive)
  cmake -S "$SRC_DIR/dolphin-libretro" -B "$SRC_DIR/dolphin-libretro/build-libretro" \
    -G Ninja -DCMAKE_BUILD_TYPE=Release -DLIBRETRO=ON
  cmake --build "$SRC_DIR/dolphin-libretro/build-libretro" -j"$JOBS"
  stage dolphin "$SRC_DIR/dolphin-libretro/build-libretro/dolphin_libretro.dylib"
}

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

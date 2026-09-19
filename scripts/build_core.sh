#!/usr/bin/env bash
# Builds libretro core plugins from upstream source into build/cores/<id>/.
# Usage:
#   scripts/build_core.sh --fetch-headers      # vendor libretro.h (once)
#   scripts/build_core.sh sameboy              # build one core (host macos-arm64)
#   scripts/build_core.sh --tier1              # run-verified macOS set
#   EZCORE_PLATFORM=android scripts/build_core.sh --tier-android
#   EZCORE_PLATFORM=ios scripts/build_core.sh --tier-ios
#   EZCORE_PLATFORM=linux scripts/build_core.sh --tier-desktop   # CI runner
#   EZCORE_PLATFORM=windows scripts/build_core.sh --tier-desktop # CI runner
# Env: EZCORE_PLATFORM (macos|linux|windows|android|ios),
#      EZCORE_ARCH (default per platform), EZCORE_OUT_DIR (staging root),
#      ANDROID_NDK_HOME (android builds).
# Legal holds (citra_hold, switch_hold, ps2_hold) refuse to build. This is
# deliberate — see cores/<id>/manifest.json blocked_reason.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# NOTE: never use Flutter's build/ dir — `flutter clean` would wipe cores.
SRC_DIR="$ROOT/native/src"
JOBS="${JOBS_OVERRIDE:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"

# Platform layer: PLATFORM/ARCH/PLAT_KEY/LIB_SUFFIX/MAKE_PLATFORM/OUT_DIR,
# toolchain setup, iOS interpreter enforcement (see core_platform.sh).
# shellcheck source=core_platform.sh
. "$ROOT/scripts/core_platform.sh"

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
    "$ROOT/runtime/external/libretro-common"
  test -f "$ROOT/runtime/external/libretro-common/include/libretro.h"
  echo "OK: libretro.h vendored"
}

stage() { # id file [destname]
  local id="$1" file="$2"
  local dest="${3:-${id}_libretro.$LIB_SUFFIX}"
  mkdir -p "$OUT_DIR/$id"
  cp "$file" "$OUT_DIR/$id/$dest"
  # Strip debug symbols (size: fbneo 81M->~20M). Dynamic symbols needed by
  # dlopen are preserved (-x/-g remove debug info only). Pinned bytes are
  # the stripped bytes — dev, pins and bundles all agree.
  case "$PLATFORM" in
    macos|ios) strip -x "$OUT_DIR/$id/$dest" ;;
    linux) "${STRIP:-strip}" -g "$OUT_DIR/$id/$dest" ;;
    android) "${STRIP:?set by android_toolchain}" -g "$OUT_DIR/$id/$dest" ;;
    windows) ;; # TODO: strip PE debug data when mingw strip is confirmed
  esac
  ios_fix_min_version "$OUT_DIR/$id/$dest"
  # macOS: ad-hoc sign at stage time — the pins describe the signed bytes
  # (what actually ships), and the app verifies the bundle against those
  # pins before staging. Signing after pinning rewrites the bytes and
  # breaks the app's verification; never re-sign a pinned artifact.
  case "$PLATFORM" in
    macos) codesign --force -s - "$OUT_DIR/$id/$dest" ;;
  esac
  (cd "$OUT_DIR/$id" && { shasum -a 256 "$dest" 2>/dev/null || sha256sum "$dest"; } | tee SHA256SUMS)
}

# Portable make wrapper: libretro `platform=` value + parallelism.
# Toolchains (android NDK / iOS SDK env) are installed by dispatch.
# One-shot override per call (auto-cleared, never leaks across recipes):
#   MAKE_PLATFORM_OVERRIDE="platform=unix" core_make "$dir"
# MAKEBIN selects the make binary (SameBoy needs GNU make 4+ for realpath).
# Tree lock: concurrent same-tree builds poison each other (verified mac+iOS
# scummvm object race). Serializes per source dir; different cores still
# build in parallel.
core_make() { # dir [make-args...]
  local dir="$1"; shift
  local mp="${MAKE_PLATFORM_OVERRIDE:-$MAKE_PLATFORM}"
  MAKE_PLATFORM_OVERRIDE=""
  local rc
  if command -v flock >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    flock "$dir/.ezcore-make.lock" "${MAKEBIN:-make}" -C "$dir" $mp -j"$JOBS" "$@"
    rc=$?
  else
    # shellcheck disable=SC2086
    "${MAKEBIN:-make}" -C "$dir" $mp -j"$JOBS" "$@"
    rc=$?
  fi
  if [ $rc -eq 0 ]; then
    echo "$PLATFORM-$ARCH" > "$dir/.ezcore-build-ok"
  else
    rm -f "$dir/.ezcore-build-ok"
  fi
  return $rc
}

# ---------------- TIER 1: run-verified recipes (macOS arm64) ----------------

# Pristine-checkout reset on platform switches: objects for one OS poison
# another's link (verified both directions). Correctness marker: core_make
# writes .ezcore-build-ok on success; core_reset cleans unless the marker
# matches this platform. A run killed mid-build leaves no (or a stale)
# marker, so the next run cleans instead of resuming poisoned objects.
# Same-platform rebuilds stay incremental. Submodule checkouts survive
# (nested repos untouched).
# EZCORE_NO_RESET=1 skips (iteration only — never for pins/releases).
core_reset() { # srcdir
  [ "${EZCORE_NO_RESET:-0}" = 1 ] && return 0
  local ok="$1/.ezcore-build-ok" want="$PLATFORM-$ARCH"
  if [ -f "$ok" ] && [ "$(cat "$ok")" = "$want" ]; then return 0; fi
  git -C "$1" reset -q --hard
  git -C "$1" clean -fdx -q
  rm -f "$ok" "$1/.ezcore-build-platform"
  # Nested checkouts (e.g. scummvm's deps/ clones): the superproject clean
  # never descends into them, so stale foreign objects survive forever
  # (verified: Sep-11 macOS objects poisoning iOS links). Reset them too.
  while IFS= read -r gitdir; do
    repo="$(dirname "$gitdir")"
    [ "$repo" = "$1" ] && continue
    git -C "$repo" reset -q --hard
    git -C "$repo" clean -fdx -q
  done < <(find "$1" -name .git -print 2>/dev/null | head -n 64)
}

build_pocketbit() {
  clone https://github.com/LIJI32/SameBoy.git "$SRC_DIR/SameBoy"
  core_reset "$SRC_DIR/SameBoy"
  # GNU make 4+ required: BootROM rules use $(realpath) (make 3.81 lacks it).
  # Serial build: the BootROM pb12 link step races under -j (triplicate
  # link jobs, missing order-only prerequisite upstream).
  command -v gmake >/dev/null || {
    echo "gmake required for SameBoy (brew install make)" >&2
    exit 2
  }
  # GNU make 4+ (realpath) + serial: BootROM pb12 link step races.
  MAKEBIN="gmake" JOBS=1 \
    core_make "$SRC_DIR/SameBoy" libretro
  if [ "$PLATFORM" = ios ]; then
    stage pocketbit "$SRC_DIR/SameBoy/build/bin/sameboy_libretro_ios.dylib"
  else
    stage pocketbit "$SRC_DIR/SameBoy/build/bin/sameboy_libretro.$LIB_SUFFIX"
  fi
}

build_gambatte() {
  clone https://github.com/libretro/gambatte-libretro.git "$SRC_DIR/gambatte-libretro"
  core_reset "$SRC_DIR/gambatte-libretro"
  core_make "$SRC_DIR/gambatte-libretro" -f Makefile.libretro
  # iOS link output carries the _ios infix (makefile TARGET rule).
  out="gambatte_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="gambatte_libretro_ios.dylib"
  stage gambatte "$SRC_DIR/gambatte-libretro/$out"
}

build_advancebit() {
  clone https://github.com/libretro/mgba.git "$SRC_DIR/mgba-libretro"
  core_reset "$SRC_DIR/mgba-libretro"
  require_interpreter_ios advancebit
  if [ "$PLATFORM" = android ]; then
    android_toolchain
    # NDK r27 (Clang 18) promotes implicit declarations to errors; mGBA's
    # vendored minizip predates that. Scoped downgrade, C only.
    cmake -S "$SRC_DIR/mgba-libretro" -B "$SRC_DIR/mgba-libretro/build-android" \
      -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-21 \
      -DCMAKE_C_FLAGS="-Wno-error=implicit-function-declaration -Wno-error=int-conversion" \
      -DBUILD_LIBRETRO=ON -DBUILD_QT=OFF -DBUILD_SDL=OFF -DBUILD_SUITE=OFF \
      -DBUILD_TEST=OFF -DBUILD_PYTHON=OFF -DBUILD_EXAMPLE=OFF \
      -DBUILD_PERF=OFF -DBUILD_CINEMA=OFF -DBUILD_HEADLESS=OFF
    cmake --build "$SRC_DIR/mgba-libretro/build-android" --target mgba_libretro -j"$JOBS"
    stage advancebit "$SRC_DIR/mgba-libretro/build-android/mgba_libretro.so"
    return
  fi
  cmake -S "$SRC_DIR/mgba-libretro" -B "$SRC_DIR/mgba-libretro/build-$PLATFORM-$ARCH" \
    -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_LIBRETRO=ON -DBUILD_QT=OFF -DBUILD_SDL=OFF -DBUILD_SUITE=OFF \
    -DBUILD_TEST=OFF -DBUILD_PYTHON=OFF -DBUILD_EXAMPLE=OFF \
    -DBUILD_PERF=OFF -DBUILD_CINEMA=OFF -DBUILD_HEADLESS=OFF
  cmake --build "$SRC_DIR/mgba-libretro/build-$PLATFORM-$ARCH" --target mgba_libretro -j"$JOBS"
  stage advancebit "$SRC_DIR/mgba-libretro/build-$PLATFORM-$ARCH/mgba_libretro.$LIB_SUFFIX"
}

build_superfx() {
  clone https://github.com/snes9xgit/snes9x.git "$SRC_DIR/snes9x"
  core_reset "$SRC_DIR/snes9x"
  core_make "$SRC_DIR/snes9x/libretro"
  out="snes9x_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="snes9x_libretro_ios.dylib"
  stage superfx "$SRC_DIR/snes9x/libretro/$out"
}

build_blastproc() {
  clone https://github.com/libretro/Genesis-Plus-GX.git "$SRC_DIR/Genesis-Plus-GX"
  core_reset "$SRC_DIR/Genesis-Plus-GX"
  core_make "$SRC_DIR/Genesis-Plus-GX" -f Makefile.libretro
  out="genesis_plus_gx_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="genesis_plus_gx_libretro_ios.dylib"
  stage blastproc "$SRC_DIR/Genesis-Plus-GX/$out"
}

build_realmode() {
  clone https://github.com/libretro/dosbox-pure.git "$SRC_DIR/dosbox-pure"
  core_reset "$SRC_DIR/dosbox-pure"
  # Android NDK has no libpthread (bionic libc covers it). ISMAC= defeats
  # the host sniff (/Applications wildcard) so the generic unix branch
  # (OUTNAME .so, env CXX honored) is used instead of the macOS one.
  # STRIP comes from android_toolchain (llvm-strip; host strip can't ELF).
  extra=""
  [ "$PLATFORM" = android ] && extra="LDLIBS= ISMAC="
  # shellcheck disable=SC2086
  core_make "$SRC_DIR/dosbox-pure" $extra
  out="dosbox_pure_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="dosbox_pure_libretro_ios.dylib"
  stage realmode "$SRC_DIR/dosbox-pure/$out"
}

# ------------- TIER 2: scripted, awaiting first verified run -------------
# Each exits 3 until its recipe has produced a dylib once on this machine.
unverified() { echo "UNVERIFIED recipe: $1 — see script source"; exit 3; }

build_geometry1() {
  clone https://github.com/libretro/swanstation.git "$SRC_DIR/swanstation"
  core_reset "$SRC_DIR/swanstation"
  require_interpreter_ios geometry1
  core_make "$SRC_DIR/swanstation" -f Makefile.libretro
  stage geometry1 "$SRC_DIR/swanstation/swanstation_libretro.$LIB_SUFFIX"
}

build_portcomp() {
  clone https://github.com/hrydgard/ppsspp.git "$SRC_DIR/ppsspp"
  core_reset "$SRC_DIR/ppsspp"
  (cd "$SRC_DIR/ppsspp" && git submodule update --init --depth 1 --recursive)
  # macOS-arm64 adaptation (Android-only adrenotools, dlfcn probe):
  # scripts/apply_ppsspp_macos_fix.py is idempotent and refuses loudly
  # when upstream drifts.
  python3 "$ROOT/scripts/apply_ppsspp_macos_fix.py" "$SRC_DIR/ppsspp"
  require_interpreter_ios portcomp
  # TARGET_ARCH=arm64 (macOS only): the Makefile misdetects arm64
  # (contains "64") as x86_64 and injects -msse/-msse2. Override wins.
  extra=""
  [ "$PLATFORM" = macos ] && extra="TARGET_ARCH=arm64"
  # shellcheck disable=SC2086
  core_make "$SRC_DIR/ppsspp/libretro" $extra
  stage portcomp "$SRC_DIR/ppsspp/libretro/ppsspp_libretro.$LIB_SUFFIX"
}

build_nesbyte() {
  clone https://github.com/libretro/Mesen.git "$SRC_DIR/Mesen"
  core_reset "$SRC_DIR/Mesen"
  core_make "$SRC_DIR/Mesen/Libretro"
  out="mesen_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="mesen_libretro_ios.dylib"
  stage nesbyte "$SRC_DIR/Mesen/Libretro/$out"
}

build_dualscreen() {
  clone https://github.com/libretro/melonDS.git "$SRC_DIR/melonDS-libretro"
  core_reset "$SRC_DIR/melonDS-libretro"
  require_interpreter_ios dualscreen
  core_make "$SRC_DIR/melonDS-libretro"
  stage dualscreen "$SRC_DIR/melonDS-libretro/melonds_libretro.$LIB_SUFFIX"
}

build_joystick() {
  clone https://github.com/libretro/stella2023.git "$SRC_DIR/stella2023"
  core_reset "$SRC_DIR/stella2023"
  # Android NDK has no libpthread (pthread lives in bionic libc).
  extra=""
  [ "$PLATFORM" = android ] && extra="PTHREAD_FLAGS="
  # shellcheck disable=SC2086
  core_make "$SRC_DIR/stella2023/src/os/libretro" $extra
  out="stella2023_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="stella2023_libretro_ios.dylib"
  stage joystick "$SRC_DIR/stella2023/src/os/libretro/$out"
}

build_cardcon() {
  clone https://github.com/libretro/beetle-pce-fast-libretro.git "$SRC_DIR/beetle-pce"
  core_reset "$SRC_DIR/beetle-pce"
  # SYSTEM_ZLIB=1: vendored zlib-1.2.11 does not compile against the Xcode 27
  # SDK (_stdio.h collision); macOS system zlib is API-compatible.
  # Same posture as beetle-saturn's osx block.
  # Android NDK has no librt (realtime funcs live in bionic libc): satisfy
  # -lrt with a linker-script stub via LIBRARY_PATH. A CLI LDFLAGS wipe is
  # NOT safe here — this makefile accumulates $(fpic) $(SHARED) into
  # LDFLAGS, and wiping it produced an executable link (missing _start).
  extra="SYSTEM_ZLIB=1"
  if [ "$PLATFORM" = android ]; then
    export LIBRARY_PATH="$ROOT/scripts/android-stubs${LIBRARY_PATH:+:$LIBRARY_PATH}"
  fi
  # shellcheck disable=SC2086
  core_make "$SRC_DIR/beetle-pce" $extra
  out="mednafen_pce_fast_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="mednafen_pce_fast_libretro_ios.dylib"
  stage cardcon "$SRC_DIR/beetle-pce/$out"
}

build_twinsh() {
  clone https://github.com/libretro/beetle-saturn-libretro.git "$SRC_DIR/beetle-saturn"
  core_reset "$SRC_DIR/beetle-saturn"
  core_make "$SRC_DIR/beetle-saturn"
  stage twinsh "$SRC_DIR/beetle-saturn/mednafen_saturn_libretro.$LIB_SUFFIX"
}

build_rcp64() {
  clone https://github.com/libretro/mupen64plus-libretro-nx.git "$SRC_DIR/mupen64plus-nx"
  core_reset "$SRC_DIR/mupen64plus-nx"
  # SYSTEM_LIBPNG/ZLIB: vendored libpng hits the TARGET_OS_MAC/fp.h SDK rot
  # and vendored zlib-1.2.11 hits the _stdio.h rot (same as beetle-pce).
  require_interpreter_ios rcp64
  core_make "$SRC_DIR/mupen64plus-nx" SYSTEM_LIBPNG=1 SYSTEM_ZLIB=1
  stage rcp64 "$SRC_DIR/mupen64plus-nx/mupen64plus_next_libretro.$LIB_SUFFIX"
}

build_dreamarc() {
  clone https://github.com/flyinghead/flycast.git "$SRC_DIR/flycast"
  core_reset "$SRC_DIR/flycast"
  (cd "$SRC_DIR/flycast" && git submodule update --init --depth 1 --recursive)
  require_interpreter_ios dreamarc
  # Thin arm64 on macOS: upstream defaults to universal (x86_64 slice wasted).
  extra=""
  [ "$PLATFORM" = macos ] && extra="-DCMAKE_OSX_ARCHITECTURES=arm64"
  # shellcheck disable=SC2086
  cmake -S "$SRC_DIR/flycast" -B "$SRC_DIR/flycast/build-$PLATFORM-$ARCH" \
    -G Ninja -DCMAKE_BUILD_TYPE=Release -DLIBRETRO=ON $extra
  cmake --build "$SRC_DIR/flycast/build-$PLATFORM-$ARCH" -j"$JOBS"
  stage dreamarc "$SRC_DIR/flycast/build-$PLATFORM-$ARCH/flycast_libretro.$LIB_SUFFIX"
}

build_coinbox() {
  clone https://github.com/libretro/FBNeo.git "$SRC_DIR/FBNeo"
  core_reset "$SRC_DIR/FBNeo"
  (cd "$SRC_DIR/FBNeo" && git submodule update --init --depth 1 --recursive)
  # Android NDK has no libpthread (bionic libc covers it).
  extra=""
  [ "$PLATFORM" = android ] && extra="LDFLAGS="
  # shellcheck disable=SC2086
  core_make "$SRC_DIR/FBNeo/src/burner/libretro" $extra
  out="fbneo_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="fbneo_libretro_ios.dylib"
  stage coinbox "$SRC_DIR/FBNeo/src/burner/libretro/$out"
}

build_pointclick() {
  clone https://github.com/scummvm/scummvm.git "$SRC_DIR/scummvm"
  core_reset "$SRC_DIR/scummvm"
  # USE_SYSTEM_mad=1: vendored libmad ships an extensionless `version` stamp
  # file that hijacks libc++'s <version> header (Xcode 27 libc++ includes it
  # from <limits>). USE_SYSTEM_png=1: vendored libpng hits the
  # TARGET_OS_MAC/fp.h rot (same as mupen64plus-nx). Requires:
  # brew install mad libpng. LIBRARY_PATH/CPATH let the system-lib
  # probes find Homebrew libs on Apple Silicon.
  # Vendored freetype zlib copy skips `typedef unsigned char Byte` on any
  # Apple target (ancient MacTypes assumption), but nothing defines Byte
  # anymore -> hard error under Xcode 27 libc++ on macOS AND iOS. The
  # typedef is identical everywhere (unsigned char), so making it
  # unconditional is safe. Idempotent; restored by core_reset on switches.
  fzconf="$SRC_DIR/scummvm/backends/platform/libretro/deps/libretro-deps/freetype/src/gzip/zconf.h"
  if grep -q '!defined(MACOS) && !defined(TARGET_OS_MAC)' "$fzconf" 2>/dev/null; then
    sed -i.bak 's/#if !defined(MACOS) \&\& !defined(TARGET_OS_MAC)/#if 1 \/* ezCORE: Byte is identical (unsigned char) on all targets *\//' "$fzconf" && rm -f "$fzconf.bak"
  fi
  if [ "$PLATFORM" = macos ]; then
    # DEBUG_ALLOW_DIRTY_SUBMODULES=1: same reason as the mobile branch —
    # their configure_submodules.sh git-reset --hard's any dirty dep at
    # make-parse time, which silently reverted the zconf.h patch above
    # (that's why macOS never got past freetype's gzip).
    LIBRARY_PATH="$(brew --prefix)/lib" CPATH="$(brew --prefix)/include" \
    core_make "$SRC_DIR/scummvm/backends/platform/libretro" \
      USE_SYSTEM_mad=1 USE_SYSTEM_png=1 DEBUG_ALLOW_DIRTY_SUBMODULES=1
  else
    # Xcode 27 SDK rot, two parts (both predate it upstream):
    # 1. The pinned libretro-deps mirror ships deps/.../libmad/VERSION,
    #    which shadows C++20 <version> on case-insensitive filesystems
    #    through the vendored -I path. Unreferenced by the build; remove.
    #    DEBUG_ALLOW_DIRTY_SUBMODULES=1 stops their configure script from
    #    git-reset --hard restoring it mid-build.
    # 2. Vendored libpng tests defined(TARGET_OS_MAC) (true on every Apple
    #    OS) and includes <fp.h> (Mac OS 9 era, gone). Mirror upstream's
    #    scoping to non-iPhone targets. Idempotent; restored by core_reset.
    rm -f "$SRC_DIR/scummvm/backends/platform/libretro/deps/libretro-deps/libmad/version" \
      "$SRC_DIR/scummvm/backends/platform/libretro/deps/libretro-deps/libmad/VERSION"
    pngpriv="$SRC_DIR/scummvm/backends/platform/libretro/deps/libretro-deps/libpng/pngpriv.h"
    if grep -q "defined(TARGET_OS_MAC)" "$pngpriv" 2>/dev/null && ! grep -q "TARGET_OS_IPHONE" "$pngpriv" 2>/dev/null; then
      sed -i.bak 's/defined(TARGET_OS_MAC)/(defined(TARGET_OS_MAC) \&\& !defined(TARGET_OS_IPHONE))/g' "$pngpriv" && rm -f "$pngpriv.bak"
    fi
      core_make "$SRC_DIR/scummvm/backends/platform/libretro" \
      DEBUG_ALLOW_DIRTY_SUBMODULES=1
  fi
  stage pointclick "$SRC_DIR/scummvm/backends/platform/libretro/scummvm_libretro.$LIB_SUFFIX"
}

build_powercube() {
  clone https://github.com/libretro/dolphin.git "$SRC_DIR/dolphin-libretro"
  core_reset "$SRC_DIR/dolphin-libretro"
  (cd "$SRC_DIR/dolphin-libretro" && git submodule update --init --depth 1 --recursive)
  require_interpreter_ios powercube
  # Deployment target 27.0 (macOS only): bundled curl calls pipe2()
  # (27+ SDK API) and the build sets -Werror=unguarded-availability.
  # Artifact requires macOS 27+; revisit with an @available-guarded curl
  # patch for wider distribution.
  extra=""
  [ "$PLATFORM" = macos ] && extra="-DCMAKE_OSX_DEPLOYMENT_TARGET=27.0"
  # shellcheck disable=SC2086
  cmake -S "$SRC_DIR/dolphin-libretro" -B "$SRC_DIR/dolphin-libretro/build-$PLATFORM-$ARCH" \
    -G Ninja -DCMAKE_BUILD_TYPE=Release -DLIBRETRO=ON $extra
  cmake --build "$SRC_DIR/dolphin-libretro/build-$PLATFORM-$ARCH" -j"$JOBS"
  stage powercube "$SRC_DIR/dolphin-libretro/build-$PLATFORM-$ARCH/dolphin_libretro.$LIB_SUFFIX"
}

# ---------------- Legal holds: always refuse ----------------
hold() { echo "REFUSED: $1"; exit 4; }
build_citra_hold()  { hold "3DS core on legal hold (see cores/citra_hold/manifest.json)"; }
build_switch_hold() { hold "Switch core on legal hold (see cores/switch_hold/manifest.json)"; }
build_ps2_hold()    { hold "No shippable PS2 core (see cores/ps2_hold/manifest.json)"; }

TIER1="pocketbit advancebit superfx blastproc realmode"

# Platform tiers (docs/MATRIX.md records per-core results).
# Android: dynarec allowed; software + JIT-capable make/cmake cores.
TIER_ANDROID="pocketbit advancebit nesbyte superfx blastproc joystick cardcon realmode pointclick coinbox"
# iOS: pure-interpreter make cores only. mgba/melonds/JIT-default cores stay
# out until an explicit interpreter flag is verified (manifest rule).
TIER_IOS="pocketbit nesbyte superfx blastproc joystick cardcon realmode pointclick coinbox"
# Desktop (linux/windows native): everything shippable.
TIER_DESKTOP="pocketbit advancebit nesbyte superfx blastproc joystick cardcon twinsh coinbox pointclick realmode geometry1 rcp64 dualscreen portcomp dreamarc powercube"

cmd="${1:-}"
case "$PLATFORM" in
  android) android_toolchain ;;
  ios) ios_toolchain ;;
esac
case "$cmd" in
  --fetch-headers) fetch_headers ;;
  --tier1) for c in $TIER1; do "build_${c}"; done ;;
  --tier-android) for c in $TIER_ANDROID; do "build_${c}"; done ;;
  --tier-ios) for c in $TIER_IOS; do "build_${c}"; done ;;
  --tier-desktop) for c in $TIER_DESKTOP; do "build_${c}"; done ;;
  ""|--help|-h) sed -n '2,9p' "$0" ;;
  *) "build_${cmd//-/_}" ;;
esac

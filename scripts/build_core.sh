#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

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
# Hold cores (citra_hold, switch_hold) refuse to build. This is
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

stage_system_data() { # id srcdir name — core-owned data for <system>/<name> (core system data)
  local id="$1" src="$2" name="$3"
  local dest="$OUT_DIR/$id/system/$name"
  [ -d "$src" ] || { echo "stage_system_data: $src missing" >&2; return 1; }
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  cp -R "$src" "$dest"
  # Data only: the app refuses executable bits and links in system data.
  find "$dest" -type l -delete
  find "$dest" -type f -exec chmod a-x {} +
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
  # gmake is the explicit GNU-make name (macOS brew); Linux make is already
  # GNU, so accept it when its version is 4+.
  MAKEBIN=""
  if command -v gmake >/dev/null; then
    MAKEBIN="gmake"
  elif command -v make >/dev/null && make --version 2>/dev/null | grep -q "GNU Make [4-9]"; then
    MAKEBIN="make"
  else
    echo "GNU make 4+ required for SameBoy (gmake, or make >= 4)" >&2
    exit 2
  fi
  # GNU make 4+ (realpath) + serial: BootROM pb12 link step races.
  MAKEBIN="$MAKEBIN" JOBS=1 \
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
  if [ "$PLATFORM" = ios ]; then
    # Upstream Makefile.common is included before the platform block sets
    # PLATFORM_EXT=darwin, so the generic branch adds the X11 Vulkan define
    # even for iOS. Remove it; iOS has no X11 and uses GLES/OpenGLES.
    # Upstream tests the generic `arm64` platform branch before the `ios`
    # branch, so `ios-arm64` is misdetected as a host arm64 build (GNU ld
    # flags, .so target). Exclude it from the generic branch.
    mk="$SRC_DIR/ppsspp/libretro/Makefile"
    python3 - "$mk" <<'PY'
import re
import sys
p = sys.argv[1]
s = open(p).read()
s, n = re.subn(
    r"else ifneq \(,\$\(findstring arm64,\$\(platform\)\)\)",
    "else ifneq (,$(findstring arm64,$(filter-out %ios-arm64,$(platform))))",
    s, count=1)
if n != 1:
    raise SystemExit("PPSSPP arm64 platform guard not found; refusing stale patch")
# Upstream's iOS min-version is 5.0/8.0; our floor is 15.0 and thread_local
# needs the modern target.
s = s.replace("-miphoneos-version-min=5.0", "-miphoneos-version-min=15.0")
s = s.replace("-miphoneos-version-min=8.0", "-miphoneos-version-min=15.0")
# The generic branch adds a GNU ld flag that Apple's linker rejects.
s = s.replace("LDFLAGS += -Wl,--gc-sections", "")
open(p, "w").write(s)
PY
    # iOS has no system(3); this call only opens an editor for ini files.
    fu="$SRC_DIR/ppsspp/Common/File/FileUtil.cpp"
    python3 - "$fu" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = "int retval = system(iniFile.c_str());"
if needle in s:
    open(p, "w").write(s.replace(needle, 'int retval = -1; (void)iniFile;  // ezCORE: no system(3) on iOS', 1))
PY
    lua="$SRC_DIR/ppsspp/ext/lua/loslib.c"
    python3 - "$lua" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = "#define l_system(cmd)\tsystem(cmd)"
if needle in s:
    open(p, "w").write(s.replace(needle, "#define l_system(cmd) ((cmd) == NULL ? 0 : -1)", 1))
PY
    common="$SRC_DIR/ppsspp/libretro/Makefile.common"
    python3 - "$common" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = "COREFLAGS += -DVK_USE_PLATFORM_XLIB_KHR\n"
if needle in s:
    open(p, "w").write(s.replace(needle, "", 1))
# The osx-arm64 workaround disables libpng runtime NEON; iOS arm64 has the
# same missing asm wiring, so apply it there too.
s = s.replace("ifneq (,$(findstring osx,$(platform)))\nCPUFLAGS += -DPNG_ARM_NEON_OPT=0",
              "ifneq (,$(filter osx ios-arm64,$(platform)))\nCPUFLAGS += -DPNG_ARM_NEON_OPT=0")
open(p, "w").write(s)
PY
    # A stale generated config can still define HAVE_STRONG_GETAUXVAL from a
    # previous host build; iOS has no <sys/auxv.h>. Guard that branch.
    hw="$SRC_DIR/ppsspp/ext/cpu_features/src/hwcaps.c"
    python3 - "$hw" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("#if defined(HAVE_STRONG_GETAUXVAL)\n#include <sys/auxv.h>",
              "#if defined(HAVE_STRONG_GETAUXVAL) && !defined(__APPLE__)\n#include <sys/auxv.h>", 1)
s = s.replace('#else\n#error "This platform does not provide hardware capabilities."',
              '#elif defined(__APPLE__)\nstatic unsigned long GetElfHwcapFromGetauxval(uint32_t hwcap_type) {\n  (void)hwcap_type;\n  return 0;\n}\n#else\n#error "This platform does not provide hardware capabilities."', 1)
open(p, "w").write(s)
PY
  fi
  # PPSSPP's libretro port starts with CPUCore::INTERPRETER on platforms
  # without JIT capability and exposes a runtime CPU-core option. For the iOS
  # bundle pin that option's default to Interpreter so no shipped default
  # selects the dynarec (App Review 2.5.2/4.7).
  require_interpreter_ios portcomp "runtime CPUCore::INTERPRETER default"
  if [ "$PLATFORM" = ios ]; then
    opts="$SRC_DIR/ppsspp/libretro/libretro_core_options.h"
    python3 - "$opts" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = '         "JIT"\n   },\n   {\n      "ppsspp_fast_memory",'
if needle in s:
    open(p, "w").write(s.replace(needle, '         "Interpreter"\n   },\n   {\n      "ppsspp_fast_memory",', 1))
PY
  fi
  # TARGET_ARCH=arm64 (macOS only): the Makefile misdetects arm64
  # (contains "64") as x86_64 and injects -msse/-msse2. Override wins.
  extra=""
  case "$PLATFORM" in
    macos|ios) extra="TARGET_ARCH=arm64" ;;
  esac
  # shellcheck disable=SC2086
  core_make "$SRC_DIR/ppsspp/libretro" $extra
  out="ppsspp_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="ppsspp_libretro_ios.dylib"
  stage portcomp "$SRC_DIR/ppsspp/libretro/$out"
  stage_system_data portcomp "$SRC_DIR/ppsspp/assets" PPSSPP
}

build_nesbyte() {
  clone https://github.com/libretro/Mesen.git "$SRC_DIR/Mesen"
  core_reset "$SRC_DIR/Mesen"
  core_make "$SRC_DIR/Mesen/Libretro"
  out="mesen_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="mesen_libretro_ios.dylib"
  stage nesbyte "$SRC_DIR/Mesen/Libretro/$out"
}

# The libretro melonDS source is mirrored under several retired names; this
# repository builds from the live upstream and checks out the exact revision
# the shipped core was built from.
DUALSCREEN_SHA=66b5d2634cd0a79030562811e6e05f5532f800ba
build_dualscreen() {
  clone https://github.com/libretro/melonDS.git "$SRC_DIR/melonDS"
  core_reset "$SRC_DIR/melonDS"
  git -C "$SRC_DIR/melonDS" cat-file -e "$DUALSCREEN_SHA^{commit}" 2>/dev/null \
    || git -C "$SRC_DIR/melonDS" fetch --depth 1 origin "$DUALSCREEN_SHA"
  git -C "$SRC_DIR/melonDS" checkout -q --detach "$DUALSCREEN_SHA"
  require_interpreter_ios dualscreen
  core_make "$SRC_DIR/melonDS"
  stage dualscreen "$SRC_DIR/melonDS/melonds_libretro.$LIB_SUFFIX"
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
  out="mednafen_saturn_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="mednafen_saturn_libretro_ios.dylib"
  stage twinsh "$SRC_DIR/beetle-saturn/$out"
}

build_rcp64() {
  clone https://github.com/libretro/mupen64plus-libretro-nx.git "$SRC_DIR/mupen64plus-nx"
  # The software-renderer flags below change which objects exist, and make
  # does not rebuild on a flag change -- so a tree last built with other
  # flags is reset instead of relinked into a core missing Angrylion.
  local flags_mark="$SRC_DIR/mupen64plus-nx/.ezcore-rcp64-flags" flags_want="sw-v1"
  if [ ! -f "$flags_mark" ] || [ "$(cat "$flags_mark")" != "$flags_want" ]; then
    rm -f "$SRC_DIR/mupen64plus-nx/.ezcore-build-ok"
  fi
  core_reset "$SRC_DIR/mupen64plus-nx"
  # SYSTEM_LIBPNG/ZLIB: vendored libpng hits the TARGET_OS_MAC/fp.h SDK rot
  # and vendored zlib-1.2.11 hits the _stdio.h rot (same as beetle-pce).
  require_interpreter_ios rcp64
  # Software rendering: the core offers the Angrylion RDP as an option, but
  # upstream's Makefile only compiles it (and the LLE RSP it requires) for
  # osx/ios/rpi5 and a few others -- not for unix or windows. Asking a build
  # without it for angrylion dereferences a NULL plugin pointer
  # (plugin_start_gfx) and crashes. With these flags N64 renders on the CPU,
  # with no GL context, which is the only path ezCORE has until P8.
  local sw=()
  case "$PLATFORM" in
    linux|windows) sw=(HAVE_THR_AL=1 HAVE_PARALLEL_RSP=1 LLE=1) ;;
  esac
  core_make "$SRC_DIR/mupen64plus-nx" SYSTEM_LIBPNG=1 SYSTEM_ZLIB=1 ${sw[@]+"${sw[@]}"}
  echo "$flags_want" > "$flags_mark"
  stage rcp64 "$SRC_DIR/mupen64plus-nx/mupen64plus_next_libretro.$LIB_SUFFIX"
}

build_dreamarc() {
  clone https://github.com/flyinghead/flycast.git "$SRC_DIR/flycast"
  core_reset "$SRC_DIR/flycast"
  (cd "$SRC_DIR/flycast" && git submodule update --init --depth 1 --recursive)
  # Flycast's libretro build has no compile-time JIT switch in its CMake
  # options; the interpreter/JIT choice is a documented runtime setting. The
  # explicit argument records that this iOS bundle must use the interpreter.
  require_interpreter_ios dreamarc "runtime interpreter setting; no JIT flag exposed upstream"
  # Thin arm64 on macOS: upstream defaults to universal (x86_64 slice wasted).
  extra=""
  [ "$PLATFORM" = macos ] && extra="-DCMAKE_OSX_ARCHITECTURES=arm64"
  if [ "$PLATFORM" = ios ]; then
    # Without CMAKE_SYSTEM_NAME CMake uses the host macOS SDK and produces a
    # MACOS dylib that the App Store rejects.
    export CFLAGS="-DIOS -DHAVE_OPENGLES3"
    export CXXFLAGS="-DIOS -DHAVE_OPENGLES3"
    extra="-DIOS=ON -DUSE_GLES=ON -DUSE_VULKAN=OFF -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=$IOSSDK -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_OSX_ARCHITECTURES=arm64"
    rm -rf "$SRC_DIR/flycast/build-$PLATFORM-$ARCH"
  fi
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
  # Linux libretro build: Makefile.common:344 generates shared_modules.mk by
  # sed-blanking the `-include engines/engines.mk` line, but that line is
  # wrapped in ifeq/endif — the blanking orphans the `endif`, so make fails
  # with "extraneous 'endif'". Drop the wrapper, keep the include: the sed
  # then produces a valid file. Idempotent; restored by core_reset.
  scumm_common="$SRC_DIR/scummvm/Makefile.common"
  if grep -q 'ifeq (,$(filter updatepot,$(MAKECMDGOALS)))' "$scumm_common" 2>/dev/null; then
    python3 - "$scumm_common" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text()
s = s.replace('ifeq (,$(filter updatepot,$(MAKECMDGOALS)))\n-include engines/engines.mk\nendif',
              '-include engines/engines.mk')
p.write_text(s)
PY
  fi
  # configure_engines.sh generates config.h.engines/config.mk.engines with the
  # enabled engine components, but the libretro port does NOT merge the header
  # into its static include/config.h — instead it curates its own -DUSE_* list
  # in backends/platform/libretro/Makefile.common. That list drifted behind
  # config.h.engines: components like sjis and coktel_decoder are enabled on
  # the make side (their .o files build) but never defined for C++, so engine
  # code that uses their classes unconditionally fails with "incomplete type"
  # (e.g. Graphics::FontSJIS in scumm/charset.cpp, Video::CoktelDecoder in
  # gob/videoplayer.cpp). Enable every component from config.h.engines that
  # the curated list omits, the same way the existing ones are enabled.
  # Idempotent; restored by core_reset.
  lrc_common="$SRC_DIR/scummvm/backends/platform/libretro/Makefile.common"
  if grep -q '^USE_FAAD          = 1' "$lrc_common" 2>/dev/null && ! grep -q '^USE_SJIS' "$lrc_common" 2>/dev/null; then
    python3 - "$lrc_common" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text()
anchor = 'USE_FAAD          = 1\n'
assert s.count(anchor) == 1, "unexpected USE_FAAD anchor count"
add = anchor + '''
# ezCORE: components enabled by configure_engines.sh (config.h.engines) but
# missing from the libretro curated -DUSE_* list. Engine code uses their
# classes unconditionally; without these defines the headers gate them out.
USE_SJIS             = 1
USE_COKTEL_DECODER   = 1
USE_HMI_AUDIO        = 1
USE_MACTOOLBOX       = 1
USE_MFC              = 1
USE_MSMPEG4          = 1
USE_QDM2             = 1
USE_SVQ1             = 1
USE_UNIVERSALTRACKER = 1
USE_UNP64            = 1
DEFINES += -DUSE_SJIS -DUSE_COKTEL_DECODER -DUSE_HMI_AUDIO -DUSE_MACTOOLBOX \\
           -DUSE_MFC -DUSE_MSMPEG4 -DUSE_QDM2 -DUSE_SVQ1 \\
           -DUSE_UNIVERSALTRACKER -DUSE_UNP64
'''
p.write_text(s.replace(anchor, add))
PY
  fi
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
  out="scummvm_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="scummvm_libretro_ios.dylib"
  stage pointclick "$SRC_DIR/scummvm/backends/platform/libretro/$out"
}

build_powercube() {
  clone https://github.com/libretro/dolphin.git "$SRC_DIR/dolphin-libretro"
  core_reset "$SRC_DIR/dolphin-libretro"
  (cd "$SRC_DIR/dolphin-libretro" && git submodule update --init --depth 1 --recursive)
  # Dolphin has no JIT backend on iOS at all (manifest execution.ios is
  # unset); the platform's dynarec is simply not compiled in this build.
  require_interpreter_ios powercube "no JIT backend on iOS"
  # Deployment target 27.0 (macOS only): bundled curl calls pipe2()
  # (27+ SDK API) and the build sets -Werror=unguarded-availability.
  # Artifact requires macOS 27+; revisit with an @available-guarded curl
  # patch for wider distribution.
  extra=""
  [ "$PLATFORM" = macos ] && extra="-DCMAKE_OSX_DEPLOYMENT_TARGET=27.0"
  # iOS: bundled curl detects pipe2 and then trips -Werror on the SDK
  # availability annotation. Downgrade that one warning so the core builds;
  # pipe2 exists on our iOS 15 deployment target.
  if [ "$PLATFORM" = ios ]; then
    # iOS forbids Mach exception ports; Dolphin's sigaction path avoids them.
    export CFLAGS="-Wno-error=unguarded-availability-new -DUSE_SIGACTION_ON_APPLE -DTARGET_OS_IPHONE=1 -march=armv8-a+crc+aes+sha2"
    # With the sigaction path the Mach thread-state macros are unused; skip
    # their definition block so a generic (JIT-less) build does not trip the
    # "Unsupported architecture" error or reference JitArm64 symbols.
    mt="$SRC_DIR/dolphin-libretro/Source/Core/Core/MemTools.cpp"
    python3 - "$mt" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = "#if defined(__APPLE__)\n#include <TargetConditionals.h>"
if needle in s:
    open(p, "w").write(s.replace(needle, "#if defined(__APPLE__) && !defined(USE_SIGACTION_ON_APPLE)\n#include <TargetConditionals.h>", 1))
PY
    export CXXFLAGS="$CFLAGS"
    extra="-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 -DENABLE_GENERIC=ON -DCMAKE_OSX_SYSROOT=$IOSSDK -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_OSX_ARCHITECTURES=arm64"
    # The CURL CMake probe enables pipe2, but the SDK availability annotation
    # is enforced as an error after our warning override. Use plain pipe() on
    # iOS instead, which is available at our deployment target.
    sp="$SRC_DIR/dolphin-libretro/Externals/curl/curl/lib/socketpair.c"
    python3 - "$sp" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
needle = "#ifdef HAVE_PIPE2\n"
if needle in s and "#undef HAVE_PIPE2 /* ezCORE iOS */" not in s:
    open(p, "w").write(s.replace(needle, "#ifdef __APPLE__\n#undef HAVE_PIPE2 /* ezCORE iOS */\n#endif\n" + needle, 1))
PY
    rm -rf "$SRC_DIR/dolphin-libretro/build-$PLATFORM-$ARCH"
  fi
  # shellcheck disable=SC2086
  cmake -S "$SRC_DIR/dolphin-libretro" -B "$SRC_DIR/dolphin-libretro/build-$PLATFORM-$ARCH" \
    -G Ninja -DCMAKE_BUILD_TYPE=Release -DLIBRETRO=ON $extra
  cmake --build "$SRC_DIR/dolphin-libretro/build-$PLATFORM-$ARCH" -j"$JOBS"
  out="dolphin_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="dolphin_libretro_ios.dylib"
  [ -f "$SRC_DIR/dolphin-libretro/build-$PLATFORM-$ARCH/$out" ] || out="dolphin_libretro.$LIB_SUFFIX"
  stage powercube "$SRC_DIR/dolphin-libretro/build-$PLATFORM-$ARCH/$out"
  stage_system_data powercube "$SRC_DIR/dolphin-libretro/Data/Sys" dolphin-emu/Sys
}

# LRPS2 — the maintained libretro port of PCSX2. Not in the tier lists: only
# linux-x64 is verified (manifest delivery: download); macOS/Windows have no
# kernel GL context backend yet and Android/iOS need separate packaging.
build_lrps2() {
  clone https://github.com/libretro/ps2.git "$SRC_DIR/lrps2"
  core_reset "$SRC_DIR/lrps2"
  (cd "$SRC_DIR/lrps2" && git submodule update --init --depth 1 --recursive)
  # IS_X86=1: the Makefile infers x86 from `uname -p`, which prints
  # "unknown" on distros that omit processor info (Arch). Without the
  # override the SSE4.1 baseline flags are never applied and GCC rejects
  # PCSX2's intrinsics ("target specific option mismatch" on _mm_min_epu32).
  # The arm64 backend is selected from `uname -m` and is unaffected.
  x86flag="IS_X86=1"
  [ "$PLATFORM" = ios ] && x86flag="IS_X86=0"
  # shellcheck disable=SC2086
  core_make "$SRC_DIR/lrps2" $x86flag
  out="pcsx2_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="pcsx2_libretro_ios.dylib"
  stage lrps2 "$SRC_DIR/lrps2/$out"
}

# DualVU — Play! (jpd002/Play-) ui_libretro, the BIOS-free PS2 path. BSD-2-Clause.
# Pinned commit: the libretro target exists upstream but is not exercised by
# Play!'s own CI; d44bfa1 is the commit this recipe was built and smoke-tested at.
# Play! needs its nested Dependencies submodules (zstd/xxHash/zlib), so the
# recursive submodule init is mandatory. CMake target `play_libretro`.
DUALVU_SHA=d44bfa1814b729d4a3ed3c6c3a945432d5ee5bbe
build_dualvu() {
  clone https://github.com/jpd002/Play-.git "$SRC_DIR/play"
  core_reset "$SRC_DIR/play"
  git -C "$SRC_DIR/play" cat-file -e "$DUALVU_SHA^{commit}" 2>/dev/null \
    || git -C "$SRC_DIR/play" fetch --depth 1 origin "$DUALVU_SHA"
  git -C "$SRC_DIR/play" checkout -q --detach "$DUALVU_SHA"
  (cd "$SRC_DIR/play" && git submodule update --init --depth 1 --recursive)
  # Local fixes (all BSD-2-compatible, see patches/play/): libretro teardown
  # (drain the GS mailbox instead of Release()ing GL objects under the emu
  # thread; let Destroy() tear handlers down in-thread) + an IPU PACK null
  # slot guard, and a direct hex parser in Framework's lexical_cast_ex.h
  # (GCC 16 miscompiles the iostream extraction for "FFFFFFFF", which
  # corrupted restored save-state registers).
  apply_dualvu_patch() { # repo patch
    local repo="$1" patch="$2"
    if git -C "$repo" apply --reverse --check "$patch" >/dev/null 2>&1; then
      echo "-- patch already applied: $(basename "$patch")"
    else
      git -C "$repo" apply "$patch"
    fi
  }
  apply_dualvu_patch "$SRC_DIR/play" "$ROOT/patches/play/0001-libretro-teardown-and-ipu-guard.patch"
  apply_dualvu_patch "$SRC_DIR/play/deps/Framework" "$ROOT/patches/play/0002-framework-hex-parse.patch"
  # -j2 by default: each PlayCore translation unit is large and the target
  # machine is RAM-bound (the brief pins this). Raise only with RAM free.
  ioscmake=""
  if [ "$PLATFORM" = ios ]; then
    ioscmake="-DTARGET_IOS=ON -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=$IOSSDK -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_OSX_ARCHITECTURES=arm64"
    rm -rf "$SRC_DIR/play/build-libretro"
  fi
  # shellcheck disable=SC2086
  cmake -S "$SRC_DIR/play" -B "$SRC_DIR/play/build-libretro" \
    -DCMAKE_BUILD_TYPE=Release $ioscmake \
    -DBUILD_LIBRETRO_CORE=ON -DBUILD_PLAY=OFF -DBUILD_TESTS=OFF -DBUILD_PSFPLAYER=OFF
  cmake --build "$SRC_DIR/play/build-libretro" --target play_libretro \
    -j"${DUALVU_JOBS:-2}"
  out="play_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="play_libretro_ios.dylib"
  stage dualvu "$SRC_DIR/play/build-libretro/Source/ui_libretro/$out"
}

# ---------------- New verified-license cores ----------------
# Each is pinned to the exact upstream commit the artifact was built from.
# Both are pure interpreters with no required firmware:
#   potator  — Unlicense (public domain), Watara Supervision
#   gw       — zlib/libpng, LCD handhelds (upstream: libretro/gw-libretro)
# Product names and system ids in the manifests are ezCORE-invented; the
# upstream project names are recorded as provenance only.

POTATOR_SHA=227c5f6f3ce74d32e9002ce24c1420288559a860
build_potator() {
  clone https://github.com/libretro/potator.git "$SRC_DIR/potator"
  core_reset "$SRC_DIR/potator"
  git -C "$SRC_DIR/potator" cat-file -e "$POTATOR_SHA^{commit}" 2>/dev/null \
    || git -C "$SRC_DIR/potator" fetch --depth 1 origin "$POTATOR_SHA"
  git -C "$SRC_DIR/potator" checkout -q --detach "$POTATOR_SHA"
  core_make "$SRC_DIR/potator/platform/libretro"
  stage potator "$SRC_DIR/potator/platform/libretro/potator_libretro.$LIB_SUFFIX"
}

GW_SHA=91d599b951e7bfe7e040347f58667cba20074adc
build_gw() {
  clone https://github.com/libretro/gw-libretro.git "$SRC_DIR/gw-libretro"
  core_reset "$SRC_DIR/gw-libretro"
  git -C "$SRC_DIR/gw-libretro" cat-file -e "$GW_SHA^{commit}" 2>/dev/null \
    || git -C "$SRC_DIR/gw-libretro" fetch --depth 1 origin "$GW_SHA"
  git -C "$SRC_DIR/gw-libretro" checkout -q --detach "$GW_SHA"
  core_make "$SRC_DIR/gw-libretro"
  # Makefile.libretro sets TARGET_NAME := gw; unix builds emit gw_libretro.so.
  out="gw_libretro.$LIB_SUFFIX"
  [ "$PLATFORM" = ios ] && out="gw_libretro_ios.dylib"
  stage gw "$SRC_DIR/gw-libretro/$out"
}

# ---------------- Hold cores: always refuse ----------------
hold() { echo "REFUSED: $1"; exit 4; }
build_citra_hold()  { hold "3DS core is on hold (see cores/citra_hold/manifest.json)"; }
build_switch_hold() { hold "Switch core is on hold (see cores/switch_hold/manifest.json)"; }

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

#!/usr/bin/env bash
# Assembles a shippable ezCORE release for one platform.
# Usage: scripts/release.sh <macos|windows|linux|android|ios> [--out dist/]
# Env:   EZCORE_VERSION (default: pubspec version),
#        EZCORE_CODESIGN_IDENTITY (macOS; default ad-hoc),
#        EZCORE_KEYSTORE_* (Android; see android signing config).
#
# Pipeline per platform:
#   1. data gates (manifests valid + catalog fresh)
#   2. native gates (runtime builds; staged cores match committed pins)
#   3. flutter build --release
# 4. bundle runtime + tier cores next to the app (desktop), jniLibs
#      (Android), unsigned device build (iOS; store pipeline needs a
#      signing identity — see RELEASE_PLAN Phase C)
# 5. sign + archive + banned-content scan
#
# iOS note: cores ship as versioned .framework bundles embedded via the
# Xcode project (scripts/ios_frameworks.sh, run once per core set — NOT
# per release), and the runtime links statically (scripts/build_runtime.sh
# ios --static, linked in Runner.xcodeproj). Until a signing identity is
# configured, iOS stops after an unsigned --no-codesign build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="${1:-}"
OUT="${3:-$ROOT/dist}"
VERSION="${EZCORE_VERSION:-$(grep '^version:' "$ROOT/pubspec.yaml" | cut -d' ' -f2 | cut -d+ -f1)}"

[ -z "$PLATFORM" ] && { echo "usage: release.sh <macos|windows|linux|android|ios> [--out dist/]" >&2; exit 2; }
if [ "${2:-}" = "--out" ] && [ -n "${3:-}" ]; then OUT="$3"; fi
mkdir -p "$OUT"
# Normalize to an absolute path: bundle steps cd into build dirs before
# writing $OUT, so a relative --out would land in the wrong place.
OUT="$(cd "$OUT" && pwd)"

gate() { echo "-- $*"; "$@"; }
fail() { echo "release: ERROR: $*" >&2; exit 1; }

# Prints the ids whose manifest promises this OS a bundled artifact.
# release.sh ships exactly the delivery map — a core that is staged but
# marked absent for this OS (e.g. fbneo, held pending review) stays out
# of the bundle even though its artifact is present locally.
bundled_ids() { # $1 = os key
  python3 - "$1" "$ROOT" <<'PY'
import glob, json, os, sys
osname, root = sys.argv[1], sys.argv[2]
for f in sorted(glob.glob(os.path.join(root, "cores", "*", "manifest.json"))):
    m = json.load(open(f))
    if m.get("delivery", {}).get(osname) == "bundled":
        print(m["id"])
PY
}

stage_bundled() { # $1 = cores_out dir, $2 = os key, $3 = dest dir
  local out="$1" os="$2" dest="$3" id
  for id in $(bundled_ids "$os"); do
    [ -d "$out/$id" ] || fail "delivery promises $os bundle for $id but it is not staged"
    gate cp -R "$out/$id" "$dest/"
  done
  echo "  bundled for $os: $(bundled_ids "$os" | tr '\n' ' ')"
}

echo "== ezCORE $VERSION for $PLATFORM =="

# 1. data gates
gate python3 "$ROOT/scripts/fill_manifest_data.py" --check
gate python3 "$ROOT/scripts/build_catalog.py"
gate bash "$ROOT/scripts/banned_content_scan.sh"

# 2. native gates
case "$PLATFORM" in
  macos)   PA=macos-arm64;   RUNTIME_OUT="$ROOT/runtime/build-macos"; CORES_OUT="$ROOT/native/cores" ;;
  windows) PA=windows-x64;   RUNTIME_OUT="$ROOT/runtime/build-windows"; CORES_OUT="$ROOT/native/cores-windows-x64" ;;
  linux)   PA=linux-x64;     RUNTIME_OUT="$ROOT/runtime/build-linux"; CORES_OUT="$ROOT/native/cores-linux-x64" ;;
  android) PA=android-arm64; RUNTIME_OUT="$ROOT/runtime/build-android"; CORES_OUT="$ROOT/native/cores-android-arm64-v8a" ;;
  ios)     PA=ios-arm64;     RUNTIME_OUT="$ROOT/runtime/build-ios"; CORES_OUT="$ROOT/native/cores-ios-arm64" ;;
  *) fail "unknown platform $PLATFORM" ;;
esac
gate scripts/build_runtime.sh "$PLATFORM"
gate python3 "$ROOT/scripts/pin_artifacts.py" "$PA" --out "$CORES_OUT" --check
[ -d "$CORES_OUT" ] || fail "no staged cores at $CORES_OUT (run build_core.sh tiers first)"

# 3. flutter build
case "$PLATFORM" in
  macos) gate flutter build macos --release ;;
  windows) gate flutter build windows --release ;;
  linux) gate flutter build linux --release ;;
  android)
    # jniLibs BEFORE the Gradle build: flat <abi>/ dirs (dlopen by
    # absolute nativeLibraryDir path; names need no lib prefix).
    gate mkdir -p "$ROOT/android/app/src/main/jniLibs/arm64-v8a"
    gate cp "$RUNTIME_OUT/libezcore_runtime.so" \
      "$ROOT/android/app/src/main/jniLibs/arm64-v8a/"
    for d in "$CORES_OUT"/*/; do
      id="$(basename "$d")"
      case " $(bundled_ids android | tr '\n' ' ') " in
        *" $id "*) gate cp "$d"*_libretro.so \
          "$ROOT/android/app/src/main/jniLibs/arm64-v8a/" 2>/dev/null || true ;;
        *) echo "  skip $id (not promised for android)" ;;
      esac
    done
    [ -z "${EZCORE_KEYSTORE_FILE:-}" ] && echo "WARN: no keystore env; debug-signed APK (not for stores)"
    gate flutter build apk --release
    ;;
  ios)
    # No codesign path yet (needs EZCORE_IOS_SIGNING_IDENTITY + embedded
    # core frameworks — tracked in RELEASE_PLAN Phase C). Until then an
    # unsigned device build proves the app + Swift + assets compile.
    echo "WARN: no iOS signing identity; unsigned device build only"
    gate flutter build ios --no-codesign
    echo "OK: unsigned iOS build (device deploy needs signing; see RELEASE_PLAN)"
    exit 0
    ;;
esac

# 4. bundle natives next to the app
case "$PLATFORM" in
  macos)
    APP="$ROOT/build/macos/Build/Products/Release/ezCore.app"
    [ -d "$APP" ] || fail "missing $APP"
    gate cp "$RUNTIME_OUT/libezcore_runtime.dylib" "$APP/Contents/Frameworks/"
    gate mkdir -p "$APP/Contents/Resources/ezcore/cores"
    stage_bundled "$CORES_OUT" macos "$APP/Contents/Resources/ezcore/cores"
    if [ -n "${EZCORE_CODESIGN_IDENTITY:-}" ]; then
      gate codesign --deep --force --options runtime -s "$EZCORE_CODESIGN_IDENTITY" "$APP"
    else
      # Ad-hoc sign, inside-out. Only the runtime dylib (a Frameworks/
      # subcomponent, which must be signed) and the app itself (WITH
      # Release.entitlements — signing without them silently drops the
      # sandbox the app is designed for).
      #
      # The core dylibs in Contents/Resources/ are deliberately NOT signed:
      # signing rewrites their bytes, which would break the sha256 pins the
      # app verifies against before staging (ad-hoc signatures are not
      # reproducible). Resources/ nested code isn't required to be signed,
      # and there is no hardened runtime in the ad-hoc path, so dlopen of
      # the unsigned cores works. (For a future notarized build: hardened
      # runtime + library validation needs either the disable-library-
      # validation entitlement or cores signed with the same team ID and
      # re-pinned to the signed bytes.)
      gate codesign --force -s - "$APP/Contents/Frameworks/libezcore_runtime.dylib"
      gate codesign --force --entitlements "$ROOT/macos/Runner/Release.entitlements" -s - "$APP"
    fi
    (cd "$(dirname "$APP")" && ditto -c -k --sequesterRsrc --keepParent "$(basename "$APP")" "$OUT/ezcore-$VERSION-macos-arm64.zip")
    ;;
  windows)
    DIST="$ROOT/build/windows/x64/runner/Release"
    [ -d "$DIST" ] || fail "missing $DIST"
    gate cp "$RUNTIME_OUT/libezcore_runtime.dll" "$DIST/"
    gate mkdir -p "$DIST/cores" && stage_bundled "$CORES_OUT" windows "$DIST/cores"
    (cd "$ROOT/build/windows/x64/runner" && zip -qr "$OUT/ezcore-$VERSION-windows-x64.zip" Release)
    ;;
  linux)
    DIST="$ROOT/build/linux/x64/release/bundle"
    [ -d "$DIST" ] || fail "missing $DIST"
    gate cp "$RUNTIME_OUT/libezcore_runtime.so" "$DIST/"
    gate mkdir -p "$DIST/cores" && stage_bundled "$CORES_OUT" linux "$DIST/cores"
    (cd "$ROOT/build/linux/x64/release" && tar -czf "$OUT/ezcore-$VERSION-linux-x64.tar.gz" bundle)
    ;;
  android)
    APK="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
    [ -f "$APK" ] || fail "missing $APK (jniLibs staging: see docs/MATRIX.md)"
    gate cp "$APK" "$OUT/ezcore-$VERSION-android-arm64.apk"
    ;;
esac

# 5. final scan of what ships (bundle content, not just the repo)
gate bash "$ROOT/scripts/banned_content_scan.sh"
echo "OK: $OUT"

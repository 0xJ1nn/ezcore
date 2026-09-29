#!/usr/bin/env bash
# Package staged iOS cores as .framework bundles for Xcode embedding.
#
# WHY THIS EXISTS
# ---------------
# scripts/release.sh:18 documents that "cores ship as versioned .framework
# bundles embedded via the Xcode project (scripts/ios_frameworks.sh, run once
# per core set -- NOT per release)". That script did not exist, so the iOS
# delivery design referenced a tool that was never written and iOS could not
# be cut as a release at all. This is that tool.
#
# WHAT IT DOES
# ------------
# iOS will not let an app dlopen() a bare dylib that sits in its bundle, so
# each staged libretro core has to be wrapped in a macOS-style .framework
# directory: a directory named <id>.framework containing the dylib and an
# Info.plist declaring it a dynamic library with the right install name.
# Xcode then links and embeds them via the existing "Embed Frameworks" build
# phase in ios/Runner.xcodeproj/project.pbxproj.
#
# Run ONCE per core set, not per release. The output is a committed,
# versioned artifact tree; re-running it for a release is what would make the
# pins and the embedded bytes disagree.
#
#   scripts/ios_frameworks.sh [--out DIR] [--check]
#
#   --out DIR   where to write the bundles (default native/cores-ios-arm64)
#   --check     verify an existing tree without writing anything; exits 1 on
#               any bundle that is missing, malformed, or whose install name
#               disagrees with its location. Used by CI and by the release
#               gate so a broken bundle set can never reach an archive.
#
# WHY minos IS ALREADY HANDLED ELSEWHERE
# --------------------------------------
# scripts/core_platform.sh:74 (ios_fix_min_version) already rewrites each
# staged dylib's LC_BUILD_VERSION to IOS_MINOS=15.0 at stage time, and
# REFUSES the build if the repair did not take. This script therefore does not
# re-patch minos: doing it again here would rewrite bytes that the committed
# pin was computed from, which is exactly the bug the macOS ad-hoc signing
# comment in build_core.sh:59-62 warns about. This script only WRAPS.
#
# Requires: macOS with xcrun. Safe to run elsewhere -- it refuses with a clear
# message rather than emitting bundles that Xcode would reject.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# The staging root core_platform.sh:52 writes to for ios/arm64.
STAGED="${EZCORE_STAGED_IOS:-$ROOT/native/cores-ios-arm64}"
OUT=""
CHECK=0

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:?--out needs a directory}"; shift 2 ;;
    --check) CHECK=1; shift ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "usage: ios_frameworks.sh [--out DIR] [--check]" >&2; exit 2 ;;
  esac
done
[ -n "$OUT" ] || OUT="$STAGED"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "ios_frameworks.sh: xcrun not found." >&2
  echo "  iOS .framework bundles are built with the macOS toolchain because the" >&2
  echo "  Info.plist and the linker need it. Run this on a macOS host, in the" >&2
  echo "  same session that produced the staged dylibs." >&2
  exit 2
fi

SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
IOS_MINOS="15.0"   # keep in sync with IOS_MINOS in scripts/core_platform.sh
BIN_ID="ezcore.core"

note() { printf '%s\n' "$*"; }

# Validate one staged core directory. Sets a reason on failure.
validate_core_dir() { # dir -> 0 ok
  local dir="$1" so
  so="$(find "$dir" -maxdepth 1 -name '*.dylib' -print -quit 2>/dev/null || true)"
  if [ -z "$so" ]; then
    REASON="no .dylib in $dir"
    return 1
  fi
  # lipo must recognise it: a fat or thin arm64 slice, not a script or a stub.
  if ! lipo -info "$so" >/dev/null 2>&1; then
    REASON="$so is not a Mach-O dylib (lipo rejected it)"
    return 1
  fi
  return 0
}

write_bundle() { # id dir
  local id="$1" dir="$2" so dest
  so="$(find "$dir" -maxdepth 1 -name '*.dylib' -print -quit)"
  dest="$OUT/$id.framework"

  rm -rf "$dest"
  mkdir -p "$dest"
  cp "$so" "$dest/$id"

  cat > "$dest/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$id</string>
	<key>CFBundleIdentifier</key>
	<string>com.ezcore.$BIN_ID.$id</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$id</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>iPhoneOS</string>
	</array>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>MinimumOSVersion</key>
	<string>$IOS_MINOS</string>
</dict>
</plist>
PLIST

  # The install name is what the dyld loader resolves @rpath against. It has
  # to match where the bundle will actually sit, or the app dlopen()s nothing
  # and fails at runtime with a symbol error rather than at build time.
  install_name="@rpath/$id.framework/$id"
  if ! install_name_tool -id "$install_name" "$dest/$id" 2>/dev/null; then
    note "  WARNING: install_name_tool failed for $id; leaving the staged name"
  fi
}

# --check: verify an existing bundle set. Never writes.
check_bundles() {
  local id fw status=0
  shopt -s nullglob
  local ids=("$OUT"/*)
  shopt -u nullglob
  if [ ${#ids[@]} -eq 0 ]; then
    echo "ios_frameworks.sh --check: no bundles under $OUT" >&2
    return 1
  fi
  for id in "${ids[@]}"; do
    id="$(basename "$id" .framework)"
    fw="$OUT/$id.framework"
    if [ ! -d "$fw" ]; then
      echo "  MISSING: $id has no $id.framework" >&2
      status=1; continue
    fi
    for required in "Info.plist" "$id"; do
      if [ ! -e "$fw/$required" ]; then
        echo "  MALFORMED: $fw missing $required" >&2
        status=1
      fi
    done
    if [ -e "$fw/$id" ]; then
      if ! lipo -info "$fw/$id" >/dev/null 2>&1; then
        echo "  MALFORMED: $fw/$id is not Mach-O" >&2
        status=1
      fi
      # `otool -D` prints a leading header line and then the install name, but
      # the exact header varies by toolchain version. Rather than depend on a
      # fixed offset, take the first line that actually LOOKS like an install
      # name. The original `tail -n +2` silently passed on any tree where the
      # header was absent, which is the failure mode a release gate cannot
      # have: a wrong install name reaches the archive and only fails at
      # dlopen time on a user's device.
      actual=""
      while read -r line; do
        case "$line" in
          *@rpath*|*/lib*|*.dylib) actual="$line"; break ;;
        esac
      done < <(otool -D "$fw/$id" 2>/dev/null | tr -s ' \t' ' ')
      if [ -z "$actual" ]; then
        echo "  UNREADABLE: $fw/$id has no install name (otool gave nothing usable)" >&2
        status=1
      elif [ "$actual" != "@rpath/$id.framework/$id" ]; then
        echo "  INSTALL NAME: $id is '$actual', expected '@rpath/$id.framework/$id'" >&2
        status=1
      fi
    fi
    if ! plutil -lint "$fw/Info.plist" >/dev/null 2>&1; then
      echo "  MALFORMED: $fw/Info.plist does not parse" >&2
      status=1
    fi
  done
  return $status
}

if [ "$CHECK" = 1 ]; then
  note "checking bundles in $OUT"
  check_bundles
  rc=$?
  if [ $rc -eq 0 ]; then
    note "OK: every bundle is well-formed and its install name matches its path"
  fi
  exit $rc
fi

if [ ! -d "$STAGED" ]; then
  echo "ios_frameworks.sh: no staged cores at $STAGED" >&2
  echo "  Build them first:  scripts/build_core.sh ios" >&2
  exit 1
fi

note "staged: $STAGED"
note "bundles: $OUT"
written=0
skipped=0

for dir in "$STAGED"/*/; do
  [ -d "$dir" ] || continue
  id="$(basename "$dir")"
  # The _hold cores are the project's legal holds: they are never built, never
  # delivered and must not acquire a bundle. Skipping them here is deliberate
  # -- packaging one would put a blocked core into an iOS archive.
  case "$id" in
    *_hold) note "skip $id (legal hold)"; skipped=$((skipped+1)); continue ;;
  esac

  if ! validate_core_dir "$dir"; then
    echo "  REFUSED: $id -- $REASON" >&2
    continue
  fi
  write_bundle "$id" "$dir"
  note "  wrote $id.framework"
  written=$((written+1))
done

if [ "$written" -eq 0 ]; then
  echo "ios_frameworks.sh: wrote no bundles." >&2
  echo "  Every staged core was skipped or refused; see the messages above." >&2
  exit 1
fi

note ""
note "wrote $written bundle(s), skipped $skipped"
note ""
note "Next: add each $id.framework to the Xcode project's Embed Frameworks"
note "phase (ios/Runner.xcodeproj), or run this per core set and commit the"
note "tree. Xcode signs the embedded copies at archive time; this script"
note "deliberately does not sign, because the committed pins describe the"
note "unsigned staged bytes."

#!/usr/bin/env bash
# Xcode "Bundle ezCORE cores" build phase (iOS).
#
# Apple rejects standalone Mach-O dylibs inside an app bundle (90171) and only
# accepts framework bundles under the app's Frameworks/ directory (90680).
# Each staged libretro core is therefore wrapped in a minimal .framework there.
# The dylib bytes are copied unchanged; the app hashes the shipped framework at
# startup and uses that as the pin for bundled cores.
set -euo pipefail

SRC="${SRCROOT}/../native/cores-ios-arm64"
APP="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
FWROOT="$APP/Frameworks"
[ -d "$SRC" ] || exit 0
mkdir -p "$FWROOT"
rm -rf "$APP/ezcore-cores"

for d in "$SRC"/*/; do
  id="$(basename "$d")"
  so="$(find "$d" -maxdepth 1 -name "${id}_libretro.dylib" -print -quit 2>/dev/null || true)"
  [ -n "$so" ] || continue

  fw="$FWROOT/${id}_libretro.framework"
  mkdir -p "$fw"
  cp "$so" "$fw/${id}_libretro.dylib"
  [ -f "$d/SHA256SUMS" ] && cp "$d/SHA256SUMS" "$fw/"
  [ -d "$d/system" ] && cp -R "$d/system" "$fw/"

  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict>' \
    '<key>CFBundlePackageType</key><string>FMWK</string>' \
    "<key>CFBundleExecutable</key><string>${id}_libretro.dylib</string>" \
    "<key>CFBundleIdentifier</key><string>app.ezcore.core.${id}</string>" \
    "<key>CFBundleName</key><string>${id}</string>" \
    '<key>CFBundleVersion</key><string>1</string>' \
    '<key>CFBundleShortVersionString</key><string>1.0</string>' \
    '<key>MinimumOSVersion</key><string>15.0</string>' \
    '</dict></plist>' > "$fw/Info.plist"
  echo "wrapped $id"
done

echo "wrapped $(find "$FWROOT" -name '*_libretro.dylib' | wc -l | tr -d ' ') cores"

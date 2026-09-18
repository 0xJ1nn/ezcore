#!/usr/bin/env bash
# Regenerates all launcher icons from assets/branding/app-icon-1024.png.
# macOS-only (uses sips). Rerunnable: pads the near-square master to a
# 1024 square on brand black, then downsizes every platform slot.
# Usage: scripts/generate_icons.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="$ROOT/assets/branding/app-icon-1024.png"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

test -f "$MASTER" || { echo "missing $MASTER" >&2; exit 2; }
command -v sips >/dev/null || { echo "sips required (macOS)" >&2; exit 2; }

SQUARE="$WORK/square-1024.png"
sips -s format png -p 1024 1024 --padColor 0A0A0A "$MASTER" --out "$SQUARE" >/dev/null

gen() { # size path
  sips -s format png -z "$1" "$1" "$SQUARE" --out "$2" >/dev/null
}

# --- iOS (filenames must match Assets.xcassets/.../Contents.json) ---
IOS="$ROOT/ios/Runner/Assets.xcassets/AppIcon.appiconset"
gen 20 "$IOS/Icon-App-20x20@1x.png"
gen 40 "$IOS/Icon-App-20x20@2x.png"
gen 60 "$IOS/Icon-App-20x20@3x.png"
gen 29 "$IOS/Icon-App-29x29@1x.png"
gen 58 "$IOS/Icon-App-29x29@2x.png"
gen 87 "$IOS/Icon-App-29x29@3x.png"
gen 40 "$IOS/Icon-App-40x40@1x.png"
gen 80 "$IOS/Icon-App-40x40@2x.png"
gen 120 "$IOS/Icon-App-40x40@3x.png"
gen 120 "$IOS/Icon-App-60x60@2x.png"
gen 180 "$IOS/Icon-App-60x60@3x.png"
gen 76 "$IOS/Icon-App-76x76@1x.png"
gen 152 "$IOS/Icon-App-76x76@2x.png"
gen 167 "$IOS/Icon-App-83.5x83.5@2x.png"
cp "$SQUARE" "$IOS/Icon-App-1024x1024@1x.png"

# --- macOS ---
MAC="$ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset"
gen 16 "$MAC/app_icon_16.png"
gen 32 "$MAC/app_icon_32.png"
gen 128 "$MAC/app_icon_128.png"
gen 256 "$MAC/app_icon_256.png"
gen 512 "$MAC/app_icon_512.png"
cp "$SQUARE" "$MAC/app_icon_1024.png"

# --- Android (legacy mipmaps; adaptive icons are follow-up polish) ---
AND="$ROOT/android/app/src/main/res"
gen 48 "$AND/mipmap-mdpi/ic_launcher.png"
gen 72 "$AND/mipmap-hdpi/ic_launcher.png"
gen 96 "$AND/mipmap-xhdpi/ic_launcher.png"
gen 144 "$AND/mipmap-xxhdpi/ic_launcher.png"
gen 192 "$AND/mipmap-xxxhdpi/ic_launcher.png"

echo "OK: icons regenerated from $MASTER"

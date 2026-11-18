#!/usr/bin/env bash
# Regenerates the in-app logos and every platform launcher icon from the
# exported Claude Design brand files. Rerunnable from a clean checkout.
#
# Chromium renders the design's own SVGs; sips only resizes and converts
# those renders, and Pillow only packs the finished PNGs into an .ico
# container. Nothing is drawn here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESIGN="${DESIGN:-/Users/0xj1n/Projects/ezcore-ws-taglines/design/claude-design/src/assets/branding}"
HS="${HS:-$(ls "$HOME"/Library/Caches/ms-playwright/chromium_headless_shell-1223/*/chrome-headless-shell 2>/dev/null | head -1)}"
PORT="${PORT:-8941}"

for tool in python3 sips; do
  command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 2; }
done
for src in lockup-light.svg mark-white.svg wordmark-light.svg icon-ios.svg mark-outline.svg; do
  test -f "$DESIGN/$src" || { echo "missing $DESIGN/$src" >&2; exit 2; }
done
test -n "$HS" && test -x "$HS" || { echo "missing Chromium headless shell" >&2; exit 2; }

WORK="$(mktemp -d)"
SERVER_PID=
cleanup() {
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

cp "$DESIGN/lockup-light.svg" "$DESIGN/mark-white.svg" \
  "$DESIGN/wordmark-light.svg" "$DESIGN/icon-ios.svg" \
  "$DESIGN/mark-outline.svg" "$WORK/"

(cd "$WORK" && exec python3 -m http.server "$PORT" >/dev/null 2>&1) &
SERVER_PID=$!
ready=0
for _ in $(seq 1 50); do
  if python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:$PORT/', timeout=1).close()" 2>/dev/null; then
    ready=1
    break
  fi
  sleep 0.1
done
[ "$ready" = 1 ] || { echo "local server did not start" >&2; exit 2; }

page() { printf '%s' "$2" > "$WORK/$1"; }

shoot() { # page, width, height, output
  "$HS" --no-first-run --use-mock-keychain \
    --user-data-dir="$WORK/profile-$RANDOM" \
    --hide-scrollbars --default-background-color=00000000 \
    --window-size="$2,$3" --screenshot="$4" \
    "http://localhost:$PORT/$1" >/dev/null 2>&1
  test -s "$4" || { echo "render failed: $4" >&2; exit 2; }
}

resize() { sips -s format png -z "$1" "$1" "$2" --out "$3" >/dev/null; }

# ViewBox width/height of one of the exported SVGs.
dims() {
  sed -n 's/.*viewBox="0 0 \([0-9.]*\) \([0-9.]*\)".*/\1 \2/p' "$DESIGN/$1" | head -1
}

# ---------------------------------------------------------------------------
# Part B: in-app logos, with Flutter's 2.0x / 3.0x directory variants.
# ---------------------------------------------------------------------------
logo() { # svg, directory suffix, height
  local svg="$1" dir="$2" h="$3" d w name
  d=$(dims "$svg")
  w=$(python3 -c "print(round($h * ${d% *} / ${d#* }))")
  name="${svg%.svg}-$h"
  page "$name.html" "<html><body style=\"margin:0;background:transparent\"><img src=\"$svg\" style=\"display:block;width:${w}px;height:${h}px\"></body></html>"
  shoot "$name.html" "$w" "$h" "$ROOT/assets/branding/inapp/$dir/$4"
}

mkdir -p "$ROOT/assets/branding/inapp/2.0x" "$ROOT/assets/branding/inapp/3.0x"
for spec in "34|" "68|2.0x" "102|3.0x"; do
  h=${spec%%|*}; dir=${spec#*|}
  logo lockup-light.svg "$dir" "$h" lockup.png
done
for spec in "32|" "64|2.0x" "96|3.0x"; do
  h=${spec%%|*}; dir=${spec#*|}
  logo mark-white.svg "$dir" "$h" mark.png
done
for spec in "24|" "48|2.0x" "72|3.0x"; do
  h=${spec%%|*}; dir=${spec#*|}
  logo wordmark-light.svg "$dir" "$h" wordmark.png
done

# ---------------------------------------------------------------------------
# Part C: the iPhone icon is the one launcher icon on every platform.
# ---------------------------------------------------------------------------

# macOS: 824px tile centred on a 1024px Apple grid, 185px corner radius.
MAC="$ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$MAC"
page macos.html '<html><body style="margin:0;background:transparent"><div style="width:1024px;height:1024px;display:flex;align-items:center;justify-content:center"><div style="width:824px;height:824px;border-radius:185px;overflow:hidden"><img src="icon-ios.svg" style="display:block;width:824px;height:824px"></div></div></body></html>'
shoot macos.html 1024 1024 "$WORK/macos-1024.png"
cp "$WORK/macos-1024.png" "$MAC/app_icon_1024.png"
for s in 512 256 128 64 32 16; do
  resize "$s" "$WORK/macos-1024.png" "$MAC/app_icon_$s.png"
done

# Android legacy: full-bleed tile with 22% rounded, transparent corners.
AND="$ROOT/android/app/src/main/res"
mkdir -p "$AND/mipmap-anydpi-v26"
page android.html '<html><body style="margin:0;background:transparent"><div style="width:1024px;height:1024px;border-radius:22%;overflow:hidden"><img src="icon-ios.svg" style="display:block;width:1024px;height:1024px"></div></body></html>'
shoot android.html 1024 1024 "$WORK/android-1024.png"
for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  n=${spec%:*}; s=${spec#*:}
  resize "$s" "$WORK/android-1024.png" "$AND/mipmap-$n/ic_launcher.png"
done

# Android adaptive: the outline mark centred at 52% of each 108dp canvas.
for spec in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  n=${spec%:*}; s=${spec#*:}
  fw=$(python3 -c "print(round($s * 0.52))")
  fh=$(python3 -c "print(round($fw * 200 / 478))")
  page "fg-$s.html" "<html><body style=\"margin:0;background:transparent\"><div style=\"width:${s}px;height:${s}px;display:flex;align-items:center;justify-content:center\"><img src=\"mark-outline.svg\" style=\"display:block;width:${fw}px;height:${fh}px\"></div></body></html>"
  shoot "fg-$s.html" "$s" "$s" "$AND/mipmap-$n/ic_launcher_foreground.png"
done

# Windows: pack the finished PNG sizes into the .ico container.
WIN="$ROOT/windows/runner/resources"
mkdir -p "$WIN"
for s in 16 24 32 48 64 128 256; do
  resize "$s" "$WORK/android-1024.png" "$WORK/win-$s.png"
done
python3 - "$WORK" "$WIN/app_icon.ico" <<'PY'
import os
import sys
from PIL import Image

work, out = sys.argv[1], sys.argv[2]
sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
with Image.open(os.path.join(work, "win-256.png")) as image:
    image.save(out, format="ICO", sizes=sizes)
PY

# Linux: the rounded tile at 512px.
mkdir -p "$ROOT/linux/runner/resources"
resize 512 "$WORK/android-1024.png" "$ROOT/linux/runner/resources/app_icon.png"

# Web (when present): flat icons plus full-bleed maskable variants.
if [ -d "$ROOT/web" ]; then
  mkdir -p "$ROOT/web/icons"
  resize 32 "$WORK/android-1024.png" "$ROOT/web/favicon.png"
  resize 192 "$WORK/android-1024.png" "$ROOT/web/icons/Icon-192.png"
  resize 512 "$WORK/android-1024.png" "$ROOT/web/icons/Icon-512.png"
  page web-mask.html '<html><body style="margin:0;background:transparent"><img src="icon-ios.svg" style="display:block;width:1024px;height:1024px"></body></html>'
  shoot web-mask.html 1024 1024 "$WORK/web-mask.png"
  resize 192 "$WORK/web-mask.png" "$ROOT/web/icons/Icon-maskable-192.png"
  resize 512 "$WORK/web-mask.png" "$ROOT/web/icons/Icon-maskable-512.png"
fi

echo "OK: in-app logos and launcher icons regenerated from $DESIGN"

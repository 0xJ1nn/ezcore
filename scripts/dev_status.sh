#!/usr/bin/env bash
# Dev-machine verification matrix: for every staged core dylib, check
# (1) sha256 matches the manifest pin, (2) load+init+identify via the
# ezCore runtime harness. Exit nonzero on any failure. macOS dev only.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS=/tmp/test_load

if [ ! -x "$HARNESS" ]; then
  cc "$ROOT/runtime/test/test_load.c" -o "$HARNESS" \
    -I"$ROOT/runtime/include" -L"$ROOT/runtime/build" -lezcore_runtime \
    -Wl,-rpath,"$ROOT/runtime/build" || exit 2
fi

fail=0
printf '%-16s %-10s %-12s %s\n' CORE SHA_LOAD IDENTIFY
for d in "$ROOT"/native/cores/*/; do
  [ -d "$d" ] || continue
  id="$(basename "$d")"
  lib="$(ls "$d"*_libretro.dylib 2>/dev/null | head -n 1)"
  [ -n "$lib" ] || { printf '%-16s %-10s %s\n' "$id" '-' 'not built'; continue; }
  sha="$(shasum -a 256 "$lib" | cut -d' ' -f1)"
  pinned="$(python3 -c "
import json,sys
m = json.load(open('$ROOT/cores/$id/manifest.json'))
print(m.get('artifacts', {}).get('macos-arm64', 'UNPINNED'))" 2>/dev/null || echo ERROR)"
  if [ "$sha" = "$pinned" ]; then shastat=PINNED; else shastat="MISMATCH($pinned)"; fail=1; fi
  ident="$("$HARNESS" "$lib" 2>/dev/null | grep STATUS || echo CRASH)"
  [ "$ident" = CRASH ] && fail=1
  printf '%-16s %-10s %s\n' "$id" "$shastat" "$ident"
done
exit "$fail"

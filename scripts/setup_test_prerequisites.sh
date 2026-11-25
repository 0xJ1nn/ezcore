#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

# Provisions the two native inputs the Dart suite needs but a fresh clone does
# not carry: the pinned libretro header and the host runtime library. Both are
# build outputs, never repository content.
#
# Usage:
#   scripts/setup_test_prerequisites.sh             # fetch, build, verify
#   scripts/setup_test_prerequisites.sh --fetch-header  # header only
#   scripts/setup_test_prerequisites.sh --check      # verify only, no network
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIN="$ROOT/scripts/test_prerequisites.json"
HEADER="$ROOT/runtime/external/libretro-common/include/libretro.h"

die() { printf '%s\n' "$1" >&2; exit 1; }

pin_field() {
  python3 - "$PIN" "$1" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f)["libretro_header"][sys.argv[2]])
PY
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

host_platform() {
  case "$(uname -s)" in
    Linux) echo linux ;;
    Darwin) echo macos ;;
    MINGW* | MSYS* | CYGWIN*) echo windows ;;
    *) die "unsupported host: $(uname -s)" ;;
  esac
}

COMMIT="$(pin_field commit)"
HEADER_REL="$(pin_field path)"
EXPECTED="$(pin_field sha256)"

fetch_header() {
  if [ -f "$HEADER" ] && [ "$(sha256_file "$HEADER")" = "$EXPECTED" ]; then
    echo "OK: libretro.h already matches the pin"
    return 0
  fi
  command -v curl >/dev/null 2>&1 || die "curl is required to fetch the pinned header"
  local url="https://raw.githubusercontent.com/libretro/libretro-common/$COMMIT/$HEADER_REL"
  local tmp
  tmp="$(mktemp)"
  echo "Fetching pinned libretro.h at $COMMIT"
  if ! curl -fsSL "$url" -o "$tmp"; then
    rm -f "$tmp"
    die "could not fetch the pinned libretro header"
  fi
  local got
  got="$(sha256_file "$tmp")"
  if [ "$got" != "$EXPECTED" ]; then
    rm -f "$tmp"
    die "libretro.h SHA-256 mismatch: expected $EXPECTED, got $got"
  fi
  mkdir -p "$(dirname "$HEADER")"
  mv "$tmp" "$HEADER"
  echo "OK: libretro.h vendored ($got)"
}

build_runtime() {
  local platform ext staged
  platform="$(host_platform)"
  case "$platform" in
    linux) ext=so ;;
    macos) ext=dylib ;;
    windows) ext=dll ;;
  esac
  echo "Building the $platform host runtime"
  bash "$ROOT/scripts/build_runtime.sh" "$platform"

  # The test path policy treats any runtime/build-<platform> directory as a
  # built bridge and runs the staged-core tests against it. Stage only the
  # library at the host path those tests read, and drop the build tree.
  staged="runtime/build-host/libezcore_runtime.$ext"
  mkdir -p "$ROOT/runtime/build-host"
  cp "$ROOT/runtime/build-$platform/libezcore_runtime.$ext" "$ROOT/$staged"
  rm -rf "$ROOT/runtime/build-$platform"
  echo "OK: host runtime staged at $staged"
}

check() {
  [ -f "$HEADER" ] || die "missing pinned libretro.h; run scripts/setup_test_prerequisites.sh"
  local got
  got="$(sha256_file "$HEADER")"
  [ "$got" = "$EXPECTED" ] ||
    die "libretro.h SHA-256 mismatch: expected $EXPECTED, got $got"

  local platform ext lib
  platform="$(host_platform)"
  case "$platform" in
    linux) ext=so ;;
    macos) ext=dylib ;;
    windows) ext=dll ;;
  esac
  lib="runtime/build-host/libezcore_runtime.$ext"
  [ -f "$ROOT/$lib" ] || die "missing built runtime at $lib; run scripts/setup_test_prerequisites.sh"
  echo "OK: test prerequisites are provisioned (libretro.h, $lib)"
}

case "${1:-}" in
  --fetch-header) fetch_header ;;
  --check) check ;;
  "") fetch_header && build_runtime && check ;;
  *) die "unknown argument: $1" ;;
esac

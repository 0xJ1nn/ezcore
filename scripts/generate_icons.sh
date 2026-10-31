#!/usr/bin/env bash
# Regenerates every launcher icon (iOS, Android incl. adaptive, macOS,
# Windows, Linux). Kept for muscle memory: the one source is
# scripts/build_brand.py, which renders them all from the iPhone icon.
set -euo pipefail
exec python3 "$(cd "$(dirname "$0")" && pwd)/build_brand.py" "$@"

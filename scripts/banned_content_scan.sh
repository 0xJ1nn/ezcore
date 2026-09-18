#!/usr/bin/env bash
# Fails if any ROM/BIOS/keys/game blob lands in the repo (source of truth
# for the "ships zero copyrighted bytes" posture). CI runs this per PR.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Extensions that must never be committed (allowlist: test fixtures dir only).
PATTERN='\.(gb|gbc|gba|nds|3ds|nsp|xci|sfc|smc|iso|cso|chd|pbp|keys)$'
# BIOS/firmware blobs are caught by exact-name rules below, not by extension
# (so compiler artifacts like CMakeDetermineCompilerABI_C.bin don't trip us).
# Match FILENAMES only (basename), not paths. Source files like bios_check.dart are fine.
BIOS_FILENAMES='^(bios|firmware|syscard|IPL|prod\.keys|title\.keys|dc_boot|dc_flash|scph)(\.|$)'
ALLOWLIST='^test/fixtures/'
# Build outputs are reproducible and untracked — never scan them.
SKIP_DIRS='^(build/|runtime/build/|runtime/external/)'

hits="$(git -C "$ROOT" ls-files | grep -Ev "$SKIP_DIRS" | grep -Ei "$PATTERN" | grep -Ev "$ALLOWLIST" || true)"
# Check basenames only for BIOS patterns - use awk to extract basename
bios_hits="$(git -C "$ROOT" ls-files | grep -Ev "$SKIP_DIRS" | awk -F/ '{print $NF}' | grep -Ei "$BIOS_FILENAMES" | grep -Ev "$ALLOWLIST" || true)"
hits="$hits$bios_hits"
if [ -n "$hits" ]; then
  echo "BANNED CONTENT IN REPO:"
  echo "$hits"
  exit 1
fi

# Magic-byte sweep for committed files masquerading under other names is a
# release-pipeline step (scripts/release.sh). v0 checks names only.
echo "OK: no banned content"

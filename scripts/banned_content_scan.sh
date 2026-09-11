#!/usr/bin/env bash
# Fails if any ROM/BIOS/keys/game blob lands in the repo (source of truth
# for the "ships zero copyrighted bytes" posture). CI runs this per PR.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Extensions that must never be committed (allowlist: test fixtures dir only).
PATTERN='\.(gb|gbc|gba|nds|3ds|nsp|xci|sfc|smc|iso|cso|chd|pbp|bin|keys)$'
ALLOWLIST='^test/fixtures/'

hits="$(git -C "$ROOT" ls-files | grep -Ei "$PATTERN" | grep -Ev "$ALLOWLIST" || true)"
if [ -n "$hits" ]; then
  echo "BANNED CONTENT IN REPO:"
  echo "$hits"
  exit 1
fi

# Magic-byte sweep for committed files masquerading under other names is a
# release-pipeline step (scripts/release.sh). v0 checks names only.
echo "OK: no banned content"

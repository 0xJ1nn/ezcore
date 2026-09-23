#!/usr/bin/env bash
# Point git at the repo's tracked hooks (.githooks/).
# pre-commit: banned-content scan + license audit (when present).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
chmod +x .githooks/pre-commit 2>/dev/null || true
echo "hooks installed: core.hooksPath -> .githooks"

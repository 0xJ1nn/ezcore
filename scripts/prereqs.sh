#!/usr/bin/env bash
# Installs everything scripts/build_core.sh needs on macOS/arm64.
# Linux/Windows notes at the bottom. Idempotent — rerun freely.
set -euo pipefail

if ! command -v brew >/dev/null; then
  echo "Install Homebrew first: https://brew.sh"
  exit 1
fi

# Build system.
brew install cmake ninja pkg-config
# SameBoy boot ROMs are compiled from source with RGBDS (clean-room,
# no Nintendo binaries involved).
brew install rgbds
# System libs preferred over SDK-rotted vendored copies (see recipes).
brew install libpng mad

# Bridge + harness smoke (no extra deps).
cmake --version | head -n 1
echo "OK: prereqs installed"

# --- Other OSes (maintainers: verify and promote to commands) ---
# Debian/Ubuntu: apt install cmake ninja-build pkg-config rgbds \
#   libpng-dev libmad0-dev
# Windows: winget install Kitware.CMake Ninja-build.Ninja \
#   (RGBDS via https://github.com/gbdev/rgbds/releases)
# Android NDK / Xcode: stock installs; iOS cores bundle at build time.

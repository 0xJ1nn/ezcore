#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception
"""Read the single toolchain pin, and check that the build legs use it.

    python3 scripts/toolchain_pin.py get ndk     # print one version for a build
    python3 scripts/toolchain_pin.py check       # fail on a second NDK pin
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PIN = ROOT / "toolchain.json"
REQUIRED = (
    "flutter",
    "dart",
    "ndk",
    "cmake",
    "xcode_minimum",
    "mingw",
    "llvm_mingw",
    "msvc",
)
NDK_LITERAL = re.compile(r"2[78]\.[0-9]+\.[0-9]{5,}")
ENTRY_POINTS = (
    "scripts/core_platform.sh",
    "android/app/build.gradle.kts",
    ".github/workflows/ci.yml",
    ".github/workflows/matrix.yml",
    ".github/workflows/release.yml",
    "ios/ci_scripts/ci_post_clone.sh",
)
SKIP_DIRS = {
    ".git",
    ".dart_tool",
    ".plugin_symlinks",
    ".cxx",
    "build",
    "ephemeral",
    "native",
}


def load() -> dict:
    data = json.loads(PIN.read_text(encoding="utf-8"))
    missing = [
        key
        for key in REQUIRED
        if not isinstance(data.get(key), str) or not data[key].strip()
    ]
    if missing:
        raise SystemExit(f"{PIN.name} is missing versions: {', '.join(missing)}")
    return data


def check(data: dict) -> int:
    problems = []
    for relative in ENTRY_POINTS:
        path = ROOT / relative
        if not path.is_file() or PIN.name not in path.read_text(encoding="utf-8"):
            problems.append(f"{relative} does not read {PIN.name}")

    for path in ROOT.rglob("*"):
        if not path.is_file() or path == PIN:
            continue
        parts = path.relative_to(ROOT).parts
        if set(parts) & SKIP_DIRS or any(p.startswith("build-") for p in parts):
            continue
        if path.stat().st_size > 2_000_000:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if NDK_LITERAL.search(text):
            problems.append(f"hard-coded NDK version in {Path(*parts)}")

    for problem in problems:
        print("FAIL", problem, file=sys.stderr)
    if problems:
        return 1
    print(
        f"toolchain pin OK: Flutter {data['flutter']}, Dart {data['dart']}, "
        f"NDK {data['ndk']}, CMake {data['cmake']}"
    )
    return 0


def main(argv: list[str]) -> int:
    data = load()
    if len(argv) == 2 and argv[0] == "get" and argv[1] in data:
        print(data[argv[1]])
        return 0
    if argv == ["check"]:
        return check(data)
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

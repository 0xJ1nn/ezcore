#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

"""Require a changelog entry for a change to shipped code.

  python3 scripts/check_changelog.py [--root .] [--base origin/main] [--head HEAD]

Compares the two revisions and fails when a change to a shipped source tree has
no new entry under ``## [Unreleased]`` in CHANGELOG.md. Documentation, tests,
tooling and the changelog itself need no entry. Exit 0 when the range is clean,
1 when it is not, 2 when the revisions cannot be read.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

WATCHED = (
    "lib", "runtime", "cores", "android", "ios", "macos", "linux", "windows",
)
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


def git(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(root), *args], capture_output=True, text=True,
        errors="replace",
    )


def unreleased_range(lines: list[str]) -> tuple[int, int] | None:
    start = next((i for i, l in enumerate(lines)
                  if l.strip() == "## [Unreleased]"), None)
    if start is None:
        return None
    end = next((i for i in range(start + 1, len(lines))
                if lines[i].startswith("## [")), len(lines))
    return start + 1, end


def added_lines_with_numbers(diff: str) -> list[tuple[int, str]]:
    added: list[tuple[int, str]] = []
    lineno = 0
    for line in diff.splitlines():
        head = HUNK.match(line)
        if head:
            lineno = int(head.group(1))
        elif line.startswith("+++") or line.startswith("\\"):
            continue
        elif line.startswith("+"):
            added.append((lineno, line[1:]))
            lineno += 1
        elif line.startswith("-"):
            continue
        else:
            lineno += 1
    return added


def main(argv: list[str]) -> int:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(here.parent))
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--head", default="HEAD")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    rev = f"{args.base}...{args.head}"

    changed = git(root, "diff", "--name-only", rev)
    if changed.returncode != 0:
        print(f"check_changelog: cannot read {rev}: {changed.stderr.strip()}",
              file=sys.stderr)
        return 2
    files = [f for f in changed.stdout.splitlines() if f]
    sources = [f for f in files if f.split("/", 1)[0] in WATCHED]
    if not sources:
        print(f"check_changelog: no shipped source changed in {rev}")
        return 0

    if "CHANGELOG.md" not in files:
        print("check_changelog: FAIL: shipped source changed without a "
              "CHANGELOG.md entry:")
        for path in sources:
            print(f"  {path}")
        return 1

    current = git(root, "show", f"{args.head}:CHANGELOG.md")
    if current.returncode != 0:
        print("check_changelog: cannot read CHANGELOG.md at "
              f"{args.head}: {current.stderr.strip()}", file=sys.stderr)
        return 2
    section = unreleased_range(current.stdout.splitlines())
    if section is None:
        print("check_changelog: FAIL: CHANGELOG.md has no ## [Unreleased] section")
        return 1
    start, end = section
    patch = git(root, "diff", "-U0", rev, "--", "CHANGELOG.md")
    if patch.returncode != 0:
        print(f"check_changelog: cannot diff CHANGELOG.md: {patch.stderr.strip()}",
              file=sys.stderr)
        return 2
    entries = [text for lineno, text in added_lines_with_numbers(patch.stdout)
               if start < lineno <= end and text.strip()
               and not text.lstrip().startswith("#")]
    if not entries:
        print("check_changelog: FAIL: CHANGELOG.md changed but no entry was "
              "added under ## [Unreleased]")
        return 1

    print(f"check_changelog: OK: {len(sources)} shipped source file(s) changed "
          f"with {len(entries)} new unreleased entry/entries")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

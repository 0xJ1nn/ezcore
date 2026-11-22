#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

# Repository hygiene gate for a fresh clone: no build, no network, no Flutter.
#
# Run by the merge gate on each pull request head, and cheap enough to run by
# hand before committing:
#
#     sh scripts/check_clean.sh
#
# Checks (tracked files only, from `git ls-files`):
#
#   1. No merge-conflict marker at the start of a line. `=======` alone is not
#      checked: a Markdown setext heading uses the same run of equals signs and
#      the left/right markers always travel with it, so the three unambiguous
#      markers are enough.
#   2. No tracked file that a .gitignore already excludes. A file added with
#      `git add -f` stays in the tree and keeps working locally while every
#      fresh clone is missing it; this finds the difference. Per-user excludes
#      (.git/info/exclude) are deliberately ignored, because they describe one
#      machine and not the repository.
#   3. `python3 scripts/build_catalog.py --check` agrees with the committed
#      cores/catalog.json and cores/release.json. The catalog is a checked-in
#      generated file (the app loads it as an asset), so drift here is a
#      hand-edited merge that would ship a stale core list.
#
# Deliberately NOT checked here:
#
#   * ROM, BIOS, firmware and key files. scripts/banned_content_scan.sh owns
#     that rule, including the allowlist for test fixtures. Repeating its
#     patterns would create a second copy of one policy, and the copy that is
#     not run on every pull request is the one that drifts.
#   * Trailing whitespace. Nothing in this repository enforces it: .gitattributes
#     normalises line endings only, there is no .editorconfig, and the Dart
#     lints say nothing about it. Four tracked files carry trailing whitespace
#     today, so adding the rule here would fail a tree the project accepts and
#     would silently declare a new style policy.
#
# A check whose subject file is absent is skipped rather than failed, so the
# script stays usable in the other repositories the merge gate runs it against.
#
# Exit 0 clean, 1 findings, 2 the checkout itself could not be read.
set -u

ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd) || exit 2
problems=0

die() {
  printf 'check_clean: %s\n' "$1" >&2
  exit 2
}

report() { # <heading> <body>
  [ -n "$2" ] || return 0
  n=$(printf '%s\n' "$2" | wc -l | tr -d ' ')
  problems=$((problems + n))
  printf 'check_clean: %s (%s):\n' "$1" "$n"
  printf '%s\n' "$2" | sed 's/^/  /'
}

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 ||
  die "not a git checkout: $ROOT"

# 1. Merge-conflict markers. git grep reads the working tree and skips binary
#    files, so a stale marker cannot hide inside a build artifact either.
markers='^(<<<<<<<|>>>>>>>|\|\|\|\|\|\|\|)( |$)'
conflicts=$(git -C "$ROOT" grep -I -n -E "$markers" -- 2>&1)
rc=$?
case $rc in
  0) report "merge-conflict markers" "$conflicts" ;;
  1) : ;;
  *) die "git grep failed: $conflicts" ;;
esac

# 2. Tracked files that .gitignore excludes.
ignored=$(git -C "$ROOT" ls-files -ci --exclude-per-directory=.gitignore 2>&1)
rc=$?
[ $rc -eq 0 ] || die "git ls-files failed: $ignored"
report "tracked files excluded by .gitignore" "$ignored"

# 3. Generated catalog matches the manifests it is built from.
if [ -f "$ROOT/scripts/build_catalog.py" ]; then
  if ! command -v python3 >/dev/null 2>&1; then
    problems=$((problems + 1))
    printf 'check_clean: python3 not found (required by scripts/build_catalog.py)\n'
  elif catalog=$(cd "$ROOT" && python3 scripts/build_catalog.py --check 2>&1); then
    :
  else
    problems=$((problems + 1))
    printf 'check_clean: catalog out of date:\n'
    printf '%s\n' "$catalog" | sed 's/^/  /'
  fi
fi

if [ "$problems" -ne 0 ]; then
  printf 'FAIL: %s finding(s)\n' "$problems"
  exit 1
fi
printf 'OK: repository hygiene checks pass\n'

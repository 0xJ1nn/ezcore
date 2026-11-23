#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

# Behavioural suite for scripts/check_clean.sh, run on a throwaway git
# repository so it needs no build, no network and no Flutter SDK.
#
# Each case plants exactly one condition in a fixture checkout and asserts
# both the exit status and the line the script reports. The negative cases
# matter as much as the positive one: "passes on a clean tree" is worthless if
# the same run would have passed on a dirty one.
#
# Deliberately absent from the fixtures is any ROM/BIOS/key file check. That
# rule belongs to scripts/banned_content_scan.sh, and case 2 pins that down by
# proving a tracked .gb file does NOT fail this gate.
set -uo pipefail

SCRIPT="${1:?path to check_clean.sh}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; fail=$((fail+1)); }

fixture() { # <name> -> prints the fixture path
  local d="$WORK/$1"
  rm -rf "$d"
  mkdir -p "$d/scripts"
  cp "$SCRIPT" "$d/scripts/check_clean.sh"
  printf 'build/\n*.log\n' > "$d/.gitignore"
  printf 'read me\n' > "$d/README.md"
  git -C "$d" init -q
  git -C "$d" add -A
  printf '%s\n' "$d"
}

run() { # <fixture> -> captures output in $out, status in $rc
  out="$(sh "$1/scripts/check_clean.sh" 2>&1)"
  rc=$?
}

echo "== a clean checkout passes =="
d="$(fixture clean)"
run "$d"
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^OK'; then
  ok "clean tree exits 0 with an OK summary"
else
  bad "clean tree" "rc=$rc output=$(printf '%s' "$out" | tr '\n' ' ')"
fi

echo
echo "== banned content is left to banned_content_scan.sh =="
d="$(fixture banned)"
printf 'not really a rom\n' > "$d/game.gb"
git -C "$d" add -A
run "$d"
if [ "$rc" -eq 0 ]; then
  ok "a tracked .gb does not fail this gate (that is the other scan's rule)"
else
  bad "gb file" "check_clean duplicated the banned-content rule: $out"
fi

echo
echo "== a merge-conflict marker fails =="
d="$(fixture conflict)"
printf 'left\n<<<<<<< HEAD\nright\n>>>>>>> origin/main\n' > "$d/notes.txt"
git -C "$d" add -A
run "$d"
if [ "$rc" -eq 1 ]; then
  ok "conflict marker exits 1"
else
  bad "conflict marker" "rc=$rc"
fi
printf '%s' "$out" | grep -q 'notes.txt:2:<<<<<<< HEAD' \
  && ok "the marker is reported with file and line" \
  || bad "conflict location" "$out"
printf '%s' "$out" | grep -q 'FAIL: 2 finding' \
  && ok "the summary counts both markers" \
  || bad "conflict summary" "$out"

echo
echo "== a tracked file that .gitignore excludes fails =="
d="$(fixture ignored)"
printf 'scratch\n' > "$d/session.log"
git -C "$d" add -f session.log
run "$d"
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'session.log'; then
  ok "force-added ignored file is caught"
else
  bad "ignored file" "rc=$rc output=$(printf '%s' "$out" | tr '\n' ' ')"
fi

echo
echo "== a stale catalog fails and prints the generator's reason =="
d="$(fixture catalog)"
cat > "$d/scripts/build_catalog.py" <<'PY'
import sys
if "--check" not in sys.argv:
    sys.exit("unexpected write mode")
print("build_catalog: ERROR: cores/catalog.json is out of date")
sys.exit(1)
PY
git -C "$d" add -A
run "$d"
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'catalog out of date'; then
  ok "catalog drift fails with the generator's message"
else
  bad "catalog drift" "rc=$rc output=$(printf '%s' "$out" | tr '\n' ' ')"
fi

echo
echo "== a repository without build_catalog.py still checks the rest =="
d="$(fixture no-catalog)"
rm -f "$d/scripts/build_catalog.py"
printf 'left\n<<<<<<< HEAD\n' > "$d/notes.txt"
git -C "$d" add -A
run "$d"
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'conflict' \
    && ! printf '%s' "$out" | grep -q 'catalog'; then
  ok "missing generator is skipped, remaining checks still run"
else
  bad "missing generator" "rc=$rc output=$(printf '%s' "$out" | tr '\n' ' ')"
fi

echo
echo "== a directory that is not a git checkout is refused =="
d="$WORK/not-a-repo"
mkdir -p "$d/scripts"
cp "$SCRIPT" "$d/scripts/check_clean.sh"
run "$d"
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'not a git checkout'; then
  ok "non-git directory exits 2 rather than claiming clean"
else
  bad "non-git directory" "rc=$rc output=$(printf '%s' "$out" | tr '\n' ' ')"
fi

echo
echo "== a shipped-source change needs an unreleased changelog entry =="
d="$WORK/changelog"
rm -rf "$d"
mkdir -p "$d/scripts" "$d/lib"
cp "$SCRIPT" "$d/scripts/check_clean.sh"
cp "$SCRIPT_DIR/check_changelog.py" "$d/scripts/check_changelog.py"
printf 'build/\n*.log\n' > "$d/.gitignore"
cat > "$d/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

### Added

- Existing work.

## [0.1.0]

- First release.
MD
printf '// base\n' > "$d/lib/app.dart"
git -C "$d" init -q
git -C "$d" add -A
git -C "$d" commit -q -m base
git -C "$d" update-ref refs/remotes/origin/main HEAD
printf '// changed\n' > "$d/lib/app.dart"
git -C "$d" add -A
git -C "$d" commit -q -m 'change lib'
run "$d"
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'changelog gate failed'; then
  ok 'a shipped-source change with no entry fails the gate'
else
  bad 'changelog gate' "rc=$rc output=$(printf '%s' "$out" | tr '\n' ' ')"
fi
printf '%s' "$out" | grep -q 'lib/app.dart' \
  && ok 'the gate names the source file that needs an entry' \
  || bad 'changelog location' "$out"

python3 - "$d/CHANGELOG.md" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
open(path, "w", encoding="utf-8").write(
    text.replace("### Added\n", "### Added\n\n- A user-visible change. [linux]\n", 1))
PY
git -C "$d" add -A
git -C "$d" commit -q -m 'document the change'
run "$d"
if [ "$rc" -eq 0 ]; then
  ok 'the same change passes once an unreleased entry is added'
else
  bad 'changelog entry' "rc=$rc output=$(printf '%s' "$out" | tr '\n' ' ')"
fi

git -C "$d" reset --hard -q HEAD~1
printf '// changed again\n' > "$d/lib/app.dart"
printf '%s\n' '- a stray line below the released section' >> "$d/CHANGELOG.md"
git -C "$d" add -A
git -C "$d" commit -q -m 'change lib with an entry outside Unreleased'
run "$d"
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'Unreleased'; then
  ok 'an edit outside Unreleased does not count as an entry'
else
  bad 'changelog scope' "rc=$rc output=$(printf '%s' "$out" | tr '\n' ' ')"
fi

echo
printf 'passed=%s failed=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

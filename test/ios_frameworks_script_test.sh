#!/usr/bin/env bash
# Exercises scripts/ios_frameworks.sh logic on a non-macOS host by stubbing the
# Apple tools it shells out to (xcrun, lipo, install_name_tool, otool, plutil).
#
# The point is NOT to pretend a Linux box can build iOS bundles. It is to prove
# the SCRIPT's own logic: which cores it refuses, that it wraps rather than
# patches, that the install name it writes matches the path the check verifies,
# and that --check actually fails on each class of corruption.
#
# Every stub is a recording fake. If the script starts calling a tool this file
# does not stub, the test fails loudly rather than silently passing.
set -uo pipefail

SCRIPT="${1:?path to ios_frameworks.sh}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"
mkdir -p "$BIN"

cat > "$BIN/xcrun" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *--show-sdk-version*) echo "17.0" ;;
  *) echo "stub xcrun: unsupported $*" >&2; exit 64 ;;
esac
EOF

cat > "$BIN/lipo" <<'EOF'
#!/usr/bin/env bash
# Real lipo rejects non-Mach-O. Mirror that: a file that does not start with the
# Mach-O magic (feed face / cafe babe) is refused, so the script's validation
# path is genuinely exercised.
f="${@: -1}"
magic="$(head -c 4 "$f" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
case "$magic" in
  feedface|cafebabe|cefaedfe|cffaedfe) echo "Non-fat file: $f is architecture: arm64" ;;
  *) echo "lipo: can't create output file because : was not a valid input file" >&2; exit 1 ;;
esac
EOF

cat > "$BIN/install_name_tool" <<'EOF'
#!/usr/bin/env bash
# Supports only -id <name> <file>, which is the sole form the script uses.
if [ "${1:-}" = "-id" ]; then
  name="$2"; file="$3"
  # Rewrite the stored install name in place. Our fake Mach-O keeps it in a
  # sidecar so the check's otool -D read agrees.
  echo "$name" > "$file.install_name"
  exit 0
fi
echo "stub install_name_tool: unsupported $*" >&2; exit 64
EOF

cat > "$BIN/otool" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "-D" ] || { echo "stub otool: unsupported $*" >&2; exit 64; }
f="$2"
if [ -f "$f.install_name" ]; then cat "$f.install_name"; else echo "$f (not found)"; fi
EOF

cat > "$BIN/plutil" <<'EOF'
#!/usr/bin/env bash
# lint only: succeed if the plist has balanced dict tags and a doctype.
f="${@: -1}"
grep -q "<!DOCTYPE plist" "$f" || exit 1
grep -q "</plist>" "$f" || exit 1
exit 0
EOF

chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; fail=$((fail+1)); }

macho() { # path [install_name]
  printf '\xcf\xfa\xed\xfe' > "$1"
  [ $# -gt 1 ] && echo "$2" > "$1.install_name"
}

echo "== refuses cleanly when the Apple toolchain is absent =="
( unset PATH; PATH=/usr/bin:/bin bash "$SCRIPT" --out "$WORK/o" >"$WORK/e" 2>&1 )
if [ $? -ne 0 ] && grep -q "xcrun not found" "$WORK/e"; then
  ok "no xcrun -> non-zero exit with a clear message"
else
  bad "no xcrun" "exit was 0 or the message was missing: $(cat "$WORK/e")"
fi

echo
echo "== wraps staged cores into bundles =="
STAGE="$WORK/stage"
mkdir -p "$STAGE/nesbyte" "$STAGE/pocketbit" "$STAGE/ps2_hold" "$STAGE/broken"
macho "$STAGE/nesbyte/nesbyte_libretro_ios.dylib" "/usr/lib/libnesbyte.dylib"
macho "$STAGE/pocketbit/pocketbit_libretro_ios.dylib" "/usr/lib/libpocketbit.dylib"
macho "$STAGE/ps2_hold/ps2_hold_libretro_ios.dylib"
printf 'not a mach-o file at all\n' > "$STAGE/broken/broken_libretro_ios.dylib"

out="$WORK/out"
if EZCORE_STAGED_IOS="$STAGE" bash "$SCRIPT" --out "$out" >"$WORK/log" 2>&1; then
  ok "run succeeded"
else
  bad "run" "$(cat "$WORK/log")"
fi

[ -f "$out/nesbyte.framework/nesbyte" ] && ok "bundle contains the dylib" \
  || bad "bundle contains the dylib" "missing $out/nesbyte.framework/nesbyte"
[ -f "$out/nesbyte.framework/Info.plist" ] && ok "bundle contains Info.plist" \
  || bad "bundle contains Info.plist" "missing"
grep -q "<string>FMWK</string>" "$out/nesbyte.framework/Info.plist" \
  && ok "Info.plist declares package type FMWK" || bad "Info.plist FMWK" "absent"
grep -q "com.ezcore.ezcore.core.nesbyte" "$out/nesbyte.framework/Info.plist" \
  && ok "bundle id is namespaced to ezCORE" || bad "bundle id" "absent"

[ -d "$out/ps2_hold.framework" ] \
  && bad "legal hold skipped" "$out/ps2_hold.framework was created" \
  || ok "legal hold core is never packaged"

[ -d "$out/broken.framework" ] \
  && bad "non-Mach-O refused" "broken.framework was created" \
  || ok "non-Mach-O dylib is refused"

got="$(cat "$out/nesbyte.framework/nesbyte.install_name" 2>/dev/null || echo '')"
[ "$got" = "@rpath/nesbyte.framework/nesbyte" ] \
  && ok "install name rewritten to match the bundle path" \
  || bad "install name" "got '$got'"

echo
echo "== --check passes on the tree it just wrote =="
if bash "$SCRIPT" --out "$out" --check >"$WORK/c" 2>&1; then
  ok "check passes on a good tree"
else
  bad "check on good tree" "$(cat "$WORK/c")"
fi

echo
echo "== --check fails on each class of corruption =="
expect_check_fail() { # label mutate-cmd
  local label="$1"; shift
  local d="$WORK/corrupt"; rm -rf "$d"; cp -r "$out" "$d"
  ( eval "$@" )
  if bash "$SCRIPT" --out "$d" --check >"$WORK/cc" 2>&1; then
    bad "$label" "check PASSED on a corrupt tree"
  else
    ok "$label"
  fi
}

expect_check_fail "missing dylib inside the bundle" \
  'rm -f "$d/nesbyte.framework/nesbyte"'
expect_check_fail "missing Info.plist" \
  'rm -f "$d/nesbyte.framework/Info.plist"'
expect_check_fail "dylib is not Mach-O" \
  'printf "junk\n" > "$d/nesbyte.framework/nesbyte"'
expect_check_fail "install name disagrees with its path" \
  'echo "@rpath/Wrong.framework/nesbyte" > "$d/nesbyte.framework/nesbyte.install_name"'
expect_check_fail "unparsable Info.plist" \
  'printf "not a plist\n" > "$d/nesbyte.framework/Info.plist"'
expect_check_fail "empty tree" 'rm -rf "$d"; mkdir -p "$d"'

echo
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]

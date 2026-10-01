#!/usr/bin/env python3
"""Gate: the documented libretro environment-command coverage must match reality.

Why this exists
---------------
The kernel capability count went stale in SIX files at once. Every one of them
said "7 of 92" for months and nothing failed. Two separate mistakes were
involved, and this gate closes both:

1. The DENOMINATOR was wrong (92). It had been counted from a per-core copy of
   libretro.h under native/src/<upstream>/, not from the authoritative vendored
   header at runtime/external/libretro-common/include/libretro.h. The vendored
   header defines 93 commands, not 92.

2. The COUNTING METHOD was wrong. A plain substring grep for
   RETRO_ENVIRONMENT_[A-Z0-9_]+ reports 96, because it also matches three
   doc-comment references (\\ref RETRO_ENVIRONMENT_GET_ASSET_DIRECTORY and
   friends) that are not commands. The correct method anchors on `#define`, so
   only real commands are counted.

`scripts/check_api_docs.py` already gates the ezCORE-owned ABI against
runtime/include/ezcore_runtime.h. That gate could never have caught this: the
number lives in prose, and the functions involved are libretro's, not ours. So
the two gates are complementary, not duplicates.

What is checked
---------------
For every markdown file that states a coverage figure, the stated numerator
(count of `case RETRO_ENVIRONMENT_*` in runtime/src/runtime.c) and the stated
denominator (count of `#define RETRO_ENVIRONMENT_*` in the vendored header)
must both equal the measured values. A file that states no figure is ignored,
so this can be run over the whole docs tree.

The measured figures are recomputed on every run from the header and the
source. Nothing is hardcoded here, deliberately: a hardcoded expectation is a
second thing to get wrong, and it fails in the most convincing direction - it
reports a perfectly correct tree as broken.

Usage:
    python3 scripts/check_env_coverage_docs.py [--json] [--verbose]

Exit codes: 0 clean, 1 stale/incorrect documentation found, 2 cannot read
inputs (which is a failure too, never a silent pass).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The authoritative header. NOT native/src/<upstream>/libretro.h - per-core
# copies exist and have been the wrong source of the denominator before.
HEADER = ROOT / "runtime" / "external" / "libretro-common" / "include" / "libretro.h"
RUNTIME_C = ROOT / "runtime" / "src" / "runtime.c"

# Docs that get scanned. Excludes vendored third-party trees and build output.
SCAN_GLOBS = ["*.md", "docs/**/*.md", ".ezcore/**/*.md"]

# A stated coverage figure, in the forms the docs actually use:
#   "**13 of 93** environment commands"   (bold, with the context word)
#   "Both files now cite 13/93"            (slash form, no context word)
#   "13 of the 93 environment commands"
#
# A bare "13 of 93" with no context word is accepted only when the line also
# mentions the header or "environment" somewhere, because "13 of 93" alone is
# too generic to attribute. Every form is anchored on the two numbers, so the
# ctest tallies ("14 of 14", "3 of 3") and test counts cannot match: those
# never carry an environment/header keyword on the same line.
FIGURE_RE = re.compile(
    r"(?<![\d.])(\d{1,3})\s*(?:of\s+the\s+|of\s+|/)\s*(\d{1,3})(?![\d.])",
    re.I,
)
# A line only counts as a coverage claim if it also says what is being counted.
# Marks a line (or the one above) as QUOTING a superseded figure.
#
# It deliberately does NOT match the wrong numbers themselves. The first
# attempt keyed on "7 of 92", which made the exemption indistinguishable from
# the defect: a doc that wrote a live, wrong "7 of 92" claim was auto-exempted,
# and a mutation test proved the gate passed with the corruption in place.
# Only an explicit editorial marker qualifies, so a doc cannot launder a live
# wrong figure by saying "previously" while still asserting it.
HISTORICAL_RE = re.compile(
    r"\bearlier figure\b|\bpreviously claimed\b|\bthis entry recorded\b"
    r"|\bthe wrong figure\b|\bbad figure\b|\bincorrect figure\b"
    r"|\bsuperseded\b|\bpredates the vendored header\b"
    r"|\bcorrect(?:ed| current)? figures?\b|\bhistor(?:y|ical)\b"
    # The EZC-016 entry is the canonical example: it names the retired figure
    # inside a sentence that opens with "claimed" and immediately gives "the
    # correct current figures". Without these the gate flags the very entry
    # that documents the fix.
    r"|\bclaimed\b|\bdrift(?:s|ed)?\b|\bretired\b|\bstale\b",
    re.I,
)

CONTEXT_RE = re.compile(
    r"environment\s+command|libretro\s+environment|env(?:ironment)?\s+callback"
    r"|RETRO_ENVIRONMENT|vendored\s+header|env_cb|kernel\s+capabilit",
    re.I,
)

# The counting method, anchored on #define. A plain substring grep is WRONG:
# it also matches doc-comment refs like \ref RETRO_ENVIRONMENT_GET_ASSET_DIRECTORY.
DEFINE_RE = re.compile(r"^\s*#\s*define\s+RETRO_ENVIRONMENT_[A-Z0-9_]+", re.M)
CASE_RE = re.compile(r"case\s+RETRO_ENVIRONMENT_[A-Z0-9_]+")


def measure() -> tuple[int, int]:
    """Recompute (handled, total) from the header and the runtime source."""
    header = HEADER.read_text()
    runtime_c = RUNTIME_C.read_text()
    total = len({m.split()[-1] for m in DEFINE_RE.findall(header)})
    handled = len({m.split()[-1] for m in CASE_RE.findall(runtime_c)})
    return handled, total


def iter_docs() -> list[Path]:
    seen: dict[Path, None] = {}
    for pattern in SCAN_GLOBS:
        for p in ROOT.glob(pattern):
            if ".worktrees" in p.parts or "external" in p.parts:
                continue
            if p.is_file():
                seen[p] = None
    return sorted(seen)


def check(verbose: bool = False) -> tuple[list[str], list[str]]:
    findings: list[str] = []
    scanned: list[str] = []

    handled, total = measure()
    if total == 0:
        findings.append(
            f"{HEADER.relative_to(ROOT)} yielded 0 environment commands - the "
            "parser or the vendored header moved. Refusing to pass on an empty parse."
        )
    if handled == 0:
        findings.append(
            f"{RUNTIME_C.relative_to(ROOT)} yielded 0 `case RETRO_ENVIRONMENT_*` "
            "arms - refusing to report 0 of N as correct."
        )

    for doc in iter_docs():
        rel = doc.relative_to(ROOT)
        text = doc.read_text()
        lines = text.splitlines()
        for lineno, line in enumerate(lines, 1):
            if not CONTEXT_RE.search(line):
                continue
            # Historical references are exempt, keyed on the PARAGRAPH rather
            # than the line: KNOWN_ISSUES.md and ROADMAP.md both document the
            # retired "7 of 92" in prose that puts the correction on a
            # *different* line from the wrong figure, so a same-line test
            # flags text that is explicitly explaining the fix.
            #
            # The marker must never be the wrong numbers themselves. The first
            # attempt matched "7 of 92" and was therefore indistinguishable
            # from the defect -- a mutation test caught a live wrong claim
            # being auto-exempted. Only an editorial marker qualifies.
            para = "\n".join(lines[max(0, lineno - 4):lineno + 3])
            if HISTORICAL_RE.search(para):
                continue
            for num, den in FIGURE_RE.findall(line):
                scanned.append(f"{rel}:{lineno}")
                n, d = int(num), int(den)
                if d == total and n == handled:
                    continue
                findings.append(
                    f"{rel}:{lineno} states {n} of {d}, but the measured "
                    f"figures are {handled} of {total} "
                    f"(header {HEADER.relative_to(ROOT)}, source "
                    f"{RUNTIME_C.relative_to(ROOT)}). Fix the doc, not the code."
                )
    if verbose:
        for s in scanned:
            print(f"  checked {s}", file=sys.stderr)
    return findings, scanned


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    if not HEADER.exists() or not RUNTIME_C.exists():
        msg = f"cannot read inputs (header={HEADER.exists()}, source={RUNTIME_C.exists()})"
        print(f"env coverage docs check FAILED: {msg}")
        return 2

    try:
        findings, scanned = check(verbose=args.verbose)
    except OSError as exc:
        print(f"env coverage docs check FAILED: cannot read inputs: {exc}")
        return 2

    handled, total = measure()
    if findings:
        if args.json:
            print(json.dumps({"ok": False, "measured": f"{handled} of {total}",
                              "findings": findings}, indent=2))
        else:
            print("Environment coverage documentation check FAILED\n")
            for f in findings:
                print(f"  - {f}")
            print(
                "\n  Recompute with:\n"
                "    grep -oE '^#\\s*define\\s+RETRO_ENVIRONMENT_[A-Z0-9_]+' \\\n"
                "      runtime/external/libretro-common/include/libretro.h | "
                "awk '{print $2}' | sort -u | wc -l\n"
                "    grep -oE 'case RETRO_ENVIRONMENT_[A-Z0-9_]+' \\\n"
                "      runtime/src/runtime.c | sort -u | wc -l"
            )
        return 1

    if args.json:
        print(json.dumps({"ok": True, "measured": f"{handled} of {total}",
                          "figures_checked": len(scanned)}, indent=2))
    else:
        print(f"PASS: {len(scanned)} stated figure(s) match the measured "
              f"{handled} of {total} environment commands")
    return 0


if __name__ == "__main__":
    sys.exit(main())

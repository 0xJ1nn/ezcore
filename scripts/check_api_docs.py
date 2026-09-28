#!/usr/bin/env python3
"""Gate: docs/API.md must describe the ABI runtime/include/ezcore_runtime.h exports.

Why this exists
---------------
docs/API.md drifted from the header: it showed three EZCORE_PIXEL_* macros
that exist nowhere in the repository, called ezcore_audio_drain "thread-safe"
while its implementation is an unsynchronised memcpy/memmove
(runtime/src/runtime.c:433-443), and omitted eight exported functions
(ezcore_reset, ezcore_set_button, ezcore_clear_buttons, ezcore_frame_size,
ezcore_frame_pixels_copy, ezcore_audio_drain_copy, ezcore_audio_pending,
ezcore_sample_rate). Nothing mechanical checked the pair, so the rot was found
by a human reading a table (docs/PLATFORM.md §8). Documentation rot is
mechanical; it is caught mechanically from here on.

Rules enforced (the header is the source of truth):

1. Every function declared in the header must have a `#### `ezcore_*``
   signature section in docs/API.md.
2. Every function documented in a `####` signature section must be declared
   in the header. Prose mentions elsewhere are exempt by design — the
   "Future ABI Extensions" section is explicitly not current API and uses
   list items, not signature sections, so the check keys on those sections.
3. Every `#define EZCORE_*` shown in docs/API.md must exist in the header.
4. EZCORE_ABI_VERSION must be documented in docs/API.md.

Standard library only, so it runs anywhere the runtime builds. Wired into the
runtime's ctest suite; also safe to run by hand:

    python3 scripts/check_api_docs.py [--json]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HEADER = ROOT / "runtime" / "include" / "ezcore_runtime.h"
DOC = ROOT / "docs" / "API.md"


def check() -> list[str]:
    findings: list[str] = []

    header = HEADER.read_text()
    doc = DOC.read_text()

    # 1. Functions declared in the header: any `ezcore_*` token followed by an
    #    open paren. The ezcore_session TYPE never matches (never followed by
    #    a paren in the header).
    header_funcs = set(re.findall(r"\b(ezcore_[a-z_]+)\s*\(", header))

    # 2. Functions documented as current API: `#### `ezcore_*`` signature
    #    sections. Prose mentions (planned/roadmap text) are not sections.
    doc_funcs = set(re.findall(r"^#{4}\s+`?(ezcore_[a-z_]+)`?\s*$", doc, re.M))

    # 3. Macros shown in docs vs macros that exist in the header.
    header_macros = set(re.findall(r"^#define\s+(EZCORE_[A-Z0-9_]+)", header, re.M))
    doc_macros = set(re.findall(r"#define\s+(EZCORE_[A-Z0-9_]+)", doc))

    undocumented = sorted(header_funcs - doc_funcs)
    if undocumented:
        findings.append(
            "exported in the header but undocumented in docs/API.md: "
            + ", ".join(undocumented)
        )
    phantom = sorted(doc_funcs - header_funcs)
    if phantom:
        findings.append(
            "documented in docs/API.md but absent from the header: "
            + ", ".join(phantom)
        )
    fabricated = sorted(doc_macros - header_macros)
    if fabricated:
        findings.append(
            "#define shown in docs/API.md but absent from the header: "
            + ", ".join(fabricated)
        )
    if "EZCORE_ABI_VERSION" not in doc:
        findings.append("EZCORE_ABI_VERSION is not documented in docs/API.md")
    if not header_funcs:
        findings.append(
            "no functions found in the header — the parser found nothing, "
            "which means the header moved or the parser broke; do not ship a "
            "gate that silently passes on an empty parse"
        )

    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    args = parser.parse_args()

    try:
        findings = check()
    except OSError as exc:
        print(f"api docs check FAILED: cannot read inputs: {exc}")
        return 1

    if findings:
        if args.json:
            print(json.dumps({"ok": False, "findings": findings}, indent=2))
        else:
            print("API documentation check FAILED\n")
            for f in findings:
                print(f"  - {f}")
            print(
                "\n  The header (runtime/include/ezcore_runtime.h) is the truth;"
                "\n  fix docs/API.md, not the header."
            )
        return 1

    header = HEADER.read_text()
    n = len(set(re.findall(r"\b(ezcore_[a-z_]+)\s*\(", header)))
    if args.json:
        print(json.dumps({"ok": True, "documented_functions": n}, indent=2))
    else:
        print(
            f"PASS: all {n} exported functions documented, no phantom "
            "sections, no fabricated macros, ABI version documented"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
#!/usr/bin/env python3
"""Machine check for the project's licensing rules.

Run before every release (wired into scripts/release.sh and the pre-commit
hook) so a license problem can never ship silently.

Rules enforced:
  1. Every core manifest declares `license` and `license_url`.
  2. A non-commercial core is NEVER `bundled` for any OS — free or paid.
     (Build recipes may exist; binary distribution may not.)
  3. A GPL-2.0-ONLY core is NEVER `bundled`: it cannot form a combined work
     with this GPL-3.0-only app. A bare GPL-2 LICENSE file does not decide
     this — read the source headers for an "or later" grant.
  4. Blocked holds (`blocked_reason`) ship nothing: delivery absent, no pins.
  5. Every bundled core is listed in THIRD_PARTY_NOTICES.md.
  6. Every bundled core has at least one pinned artifact.

Exit 0 = clean. Exit 1 = violations printed.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OS_KEYS = ["macos", "windows", "linux", "android", "ios"]


def license_class(lic):
    low = lic.lower()
    if "non-commercial" in low or "noncommercial" in low:
        return "NON-COMMERCIAL"
    # GPL version precision. A bare "GPL-2.0" is AMBIGUOUS and was exactly how
    # gambatte (GPL-2.0-only) sat in the bundled set unnoticed — so an
    # unresolved string is treated as unshippable rather than assumed fine.
    # GPL-2.0-only cannot form a combined work with our GPL-3.0-only app;
    # a dlopen'd plugin shipped in the bundle counts as one work.
    if "gpl-2.0-only" in low or "gpl-2-only" in low or "gplv2 only" in low:
        return "GPL-2-ONLY"
    if ("gpl-2.0-or-later" in low or "gpl-2-or-later" in low
            or "gpl-2.0+" in low or "gplv2+" in low or "gpl-2+" in low):
        return "GPL-2-OR-LATER"
    if "gpl-2" in low:
        return "GPL-2-AMBIG"      # must be resolved before it can be bundled
    if "gpl-3" in low:
        return "GPL-3"
    if "mpl" in low:
        return "MPL-2"
    if "mit" in low:
        return "MIT"
    if "expat" in low:
        return "MIT"
    return "CUSTOM?"


def main():
    notices = ""
    notices_path = ROOT / "THIRD_PARTY_NOTICES.md"
    if notices_path.is_file():
        notices = notices_path.read_text()

    violations = []
    rows = []
    for path in sorted((ROOT / "cores").glob("*/manifest.json")):
        d = json.loads(path.read_text())
        cid = d.get("id", path.parent.name)
        lic = d.get("license", "")
        cls = license_class(lic) if lic else "MISSING"
        delivery = d.get("delivery", {})
        bundled_os = [k for k in OS_KEYS if delivery.get(k) == "bundled"]
        artifacts = d.get("artifacts", {}) or {}
        blocked = bool(d.get("blocked_reason"))

        if blocked:
            # Legal holds ship nothing and carry no license obligations —
            # the only rule is that they stay empty.
            if bundled_os or artifacts:
                violations.append(
                    f"{cid}: blocked hold must ship nothing (delivery/pins present)"
                )
            rows.append(f"{cid:<16} {'HOLD':<14} not distributed")
            continue

        if not lic or not d.get("license_url"):
            violations.append(f"{cid}: missing license or license_url")

        if cls == "NON-COMMERCIAL" and bundled_os:
            violations.append(
                f"{cid}: non-commercial license but bundled for {bundled_os}"
            )
        if cls in ("GPL-2-ONLY", "GPL-2-AMBIG") and bundled_os:
            why = ("GPL-2.0-only is incompatible with this GPL-3.0-only app"
                   if cls == "GPL-2-ONLY"
                   else "license string is ambiguous (bare GPL-2.0) — verify the "
                        "source headers for an 'or later' grant, then state it "
                        "explicitly as GPL-2.0-or-later or GPL-2.0-only")
            violations.append(f"{cid}: {why} but is bundled for {bundled_os}")
        if cls == "CUSTOM?":
            rows.append(f"{cid}: license class CUSTOM — review manually")

        if bundled_os:
            if f"`{cid}`" not in notices:
                violations.append(
                    f"{cid}: bundled but missing from THIRD_PARTY_NOTICES.md"
                )
            if not artifacts:
                violations.append(
                    f"{cid}: bundled but has no pinned artifacts"
                )

        state = "bundled " + ",".join(bundled_os) if bundled_os else "not distributed"
        rows.append(f"{cid:<16} {cls:<14} {state}")

    print("legal_audit: core license/delivery map")
    for r in rows:
        print("  " + r)
    if violations:
        print("\nVIOLATIONS:")
        for v in violations:
            print("  ✗ " + v)
        sys.exit(1)
    print("\nOK: license rules hold")


if __name__ == "__main__":
    main()

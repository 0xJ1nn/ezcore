#!/usr/bin/env python3
"""Machine check for the project's licensing rules.

Run before every release (wired into scripts/release.sh and the pre-commit
hook) so a license problem can never ship silently.

Rules enforced:
  1. Every core manifest declares `license` and `license_url`.
  2. A non-commercial core is NEVER `bundled` or `download` for any OS —
     free or paid. (Build recipes may exist; binary distribution may not.)
  3. A GPL-2.0-ONLY core is NEVER `bundled` or `download`: it cannot form
     a combined work with this GPL-3.0-only app. A bare GPL-2 LICENSE file
     does not decide this — read the source headers for an "or later" grant.
  4. Blocked holds (`blocked_reason`) ship nothing: delivery absent, no pins.
  5. Every distributed core is listed in THIRD_PARTY_NOTICES.md.
  6. Every distributed core has at least one pinned artifact.
  7. Every bundled core-art WebP is listed in the artwork provenance record.

`download` distributes the exact same bytes from our release assets as
`bundled` does from the package — every rule above covers both (ADR-013).

Exit 0 = clean. Exit 1 = violations printed.
"""
import hashlib
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


def verify_core_art():
    """Validate the exact artwork set, provenance record, and pins."""
    art_dir = ROOT / "assets" / "core_art"
    record_path = ROOT / "docs" / "CORE_ART_PROVENANCE.json"
    violations = []
    if not art_dir.is_dir():
        return ["core artwork: missing assets/core_art directory"]
    entries = list(art_dir.iterdir())
    for entry in entries:
        if entry.is_dir() or entry.is_symlink() or entry.suffix.lower() != ".webp":
            violations.append(
                "core artwork: assets/core_art must contain only flat WebP files "
                f"({entry.name})"
            )
    actual = {
        path.name: path
        for path in entries
        if path.is_file() and not path.is_symlink() and path.suffix.lower() == ".webp"
    }
    if not record_path.is_file():
        return violations + ["core artwork: missing docs/CORE_ART_PROVENANCE.json"]
    try:
        record = json.loads(record_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        return violations + [f"core artwork: invalid provenance JSON: {exc}"]

    if record.get("schema") != 1:
        violations.append("core artwork provenance: unsupported schema")
    source = record.get("source", {})
    if source.get("service") != "ChatGPT Images" or source.get("client") != "Codex":
        violations.append("core artwork provenance: service/client statement missing")
    rights = record.get("rights", {})
    if rights.get("maintainer_review") != "approved":
        violations.append("core artwork provenance: maintainer review is not approved")
    if rights.get("terms_url") != "https://openai.com/policies/row-terms-of-use/":
        violations.append("core artwork provenance: OpenAI terms URL missing")

    recorded = record.get("files", {})
    if not isinstance(recorded, dict):
        return violations + ["core artwork provenance: files must be an object"]
    for name in sorted(set(actual) - set(recorded)):
        violations.append(f"core artwork: {name} missing from provenance record")
    for name in sorted(set(recorded) - set(actual)):
        violations.append(f"core artwork provenance: {name} has no asset file")
    for name in sorted(set(actual) & set(recorded)):
        path = actual[name]
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        expected = recorded[name].get("sha256") if isinstance(recorded[name], dict) else None
        if digest != expected:
            violations.append(f"core artwork: {name} SHA-256 does not match provenance pin")
        header = path.read_bytes()[:12]
        if header[:4] != b"RIFF" or header[8:12] != b"WEBP":
            violations.append(f"core artwork: {name} is not a RIFF/WebP file")
    return violations


def main():
    notices = ""
    notices_path = ROOT / "THIRD_PARTY_NOTICES.md"
    if notices_path.is_file():
        notices = notices_path.read_text()

    violations = []
    rows = []

    violations.extend(verify_core_art())
    for path in sorted((ROOT / "cores").glob("*/manifest.json")):
        d = json.loads(path.read_text())
        cid = d.get("id", path.parent.name)
        lic = d.get("license", "")
        cls = license_class(lic) if lic else "MISSING"
        delivery = d.get("delivery", {})
        # `download` ships the same bytes from our release assets as
        # `bundled` ships inside the package — one distributed set, one
        # rulebook (ADR-013).
        shipped_os = [
            k for k in OS_KEYS if delivery.get(k) in ("bundled", "download")
        ]
        artifacts = d.get("artifacts", {}) or {}
        blocked = bool(d.get("blocked_reason"))

        if blocked:
            # Hold cores ship nothing and carry no license obligations —
            # the only rule is that they stay empty.
            if shipped_os or artifacts:
                violations.append(
                    f"{cid}: blocked hold must ship nothing (delivery/pins present)"
                )
            rows.append(f"{cid:<16} {'HOLD':<14} not distributed")
            continue

        if not lic or not d.get("license_url"):
            violations.append(f"{cid}: missing license or license_url")

        if cls == "NON-COMMERCIAL" and shipped_os:
            violations.append(
                f"{cid}: non-commercial license but ships for {shipped_os}"
            )
        if cls in ("GPL-2-ONLY", "GPL-2-AMBIG") and shipped_os:
            why = ("GPL-2.0-only is incompatible with this GPL-3.0-only app"
                   if cls == "GPL-2-ONLY"
                   else "license string is ambiguous (bare GPL-2.0) — verify the "
                        "source headers for an 'or later' grant, then state it "
                        "explicitly as GPL-2.0-or-later or GPL-2.0-only")
            violations.append(f"{cid}: {why} but ships for {shipped_os}")
        if cls == "CUSTOM?":
            rows.append(f"{cid}: license class CUSTOM — review manually")

        if shipped_os:
            if f"`{cid}`" not in notices:
                violations.append(
                    f"{cid}: ships to users but missing from THIRD_PARTY_NOTICES.md"
                )
            if not artifacts:
                violations.append(
                    f"{cid}: ships to users but has no pinned artifacts"
                )

        state = "ships " + ",".join(shipped_os) if shipped_os else "not distributed"
        rows.append(f"{cid:<16} {cls:<14} {state}")

    print("license_audit: core license/delivery map")
    for r in rows:
        print("  " + r)
    if violations:
        print("\nVIOLATIONS:")
        for v in violations:
            print("  ✗ " + v)
        sys.exit(1)
    print("\nOK: license and artwork provenance rules hold")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Builds cores/catalog.json from cores/*/manifest.json.

Single source of truth is the per-core manifests; the catalog is a
deterministic merge (sorted ids, sorted keys) bundled as a Flutter asset
and loaded at startup by AppState. Run before flutter pub get/test/build:

    python3 scripts/build_catalog.py

CI runs this first so fresh checkouts (which lack the gitignored outputs
but DO track every manifest) always produce a valid catalog. Fails loudly
on duplicate ids, id/dir mismatches, or policy-invalid manifests.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORES = ROOT / "cores"
CATALOG = CORES / "catalog.json"

REQUIRED = ("id", "name", "version", "license", "systems", "delivery")


def fail(msg: str) -> "NoReturn":
    print(f"build_catalog: ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    manifests = sorted(CORES.glob("*/manifest.json"))
    if not manifests:
        fail("no manifests found under cores/")
    catalog: dict[str, dict] = {}
    for path in manifests:
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError as e:
            fail(f"{path}: invalid JSON: {e}")
        for key in REQUIRED:
            if key not in data:
                fail(f"{path}: missing required key {key!r}")
        if data["id"] != path.parent.name and not path.parent.name.endswith("_hold"):
            fail(f"{path}: id {data['id']!r} != directory {path.parent.name!r}")
        if data["id"] in catalog:
            fail(f"duplicate core id {data['id']!r}")
        if data.get("delivery", {}).get("ios") == "download":
            fail(f"{path}: ios delivery must never be download (2.5.2/4.7)")
        if data.get("blocked_reason") and data.get("artifacts"):
            fail(f"{path}: blocked core must not ship artifacts")
        catalog[data["id"]] = data
    ordered = {k: catalog[k] for k in sorted(catalog)}
    CATALOG.write_text(json.dumps(ordered, indent=2, sort_keys=True) + "\n")
    print(f"build_catalog: wrote {CATALOG} ({len(ordered)} cores)")


if __name__ == "__main__":
    from typing import NoReturn

    main()

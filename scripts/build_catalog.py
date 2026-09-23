#!/usr/bin/env python3
"""Builds cores/catalog.json (+ cores/release.json) from cores/*/manifests.

Single source of truth is the per-core manifests; the catalog is a
deterministic merge (sorted ids, sorted keys) bundled as a Flutter asset
and loaded at startup by AppState. Run before flutter pub get/test/build:

    python3 scripts/build_catalog.py

cores/release.json is the on-demand delivery map (ADR-013): the GitHub
release tag matching this pubspec version plus the asset filename for
every delivery=download core that has a pin for that platform-arch. The
app downloads exactly these names, sha256-verifies them against the pin
in the catalog, and stages them.

CI runs this first so fresh checkouts (which lack the gitignored outputs
but DO track every manifest) always produce a valid catalog. Fails loudly
on duplicate ids, id/dir mismatches, or policy-invalid manifests.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORES = ROOT / "cores"
CATALOG = CORES / "catalog.json"
RELEASE = CORES / "release.json"

# Repository slug whose releases host the on-demand core assets. Manual
# uploads only (`gh release upload`) — GitHub is repo-hosting, no CI (ADR-013).
REPO = "JinUltimate1995/ezcore"

REQUIRED = ("id", "name", "version", "license", "systems", "delivery")


def fail(msg: str) -> "NoReturn":
    print(f"build_catalog: ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def pubspec_version() -> str:
    text = (ROOT / "pubspec.yaml").read_text()
    m = re.search(r"^version:\s*(\S+)", text, re.M)
    if not m:
        fail("pubspec.yaml: no version: line")
    return m.group(1).split("+", 1)[0]


def asset_ext(plat: str) -> str:
    return {
        "windows": "dll",
        "macos": "dylib",
        "ios": "dylib",
    }.get(plat.split("-")[0], "so")


def build_release(catalog: dict) -> dict:
    """cores/release.json — tag + downloadable asset names (ADR-013)."""
    assets: dict[str, dict[str, str]] = {}
    for cid, m in sorted(catalog.items()):
        if m.get("blocked_reason"):
            continue
        delivery = m.get("delivery", {})
        for plat, pin in sorted((m.get("artifacts") or {}).items()):
            if not pin:
                continue
            if delivery.get(plat.split("-")[0]) != "download":
                continue
            assets.setdefault(plat, {})[cid] = (
                f"{cid}_libretro-{plat}.{asset_ext(plat)}"
            )
    return {
        "repo": REPO,
        "tag": f"v{pubspec_version()}",
        "assets": {k: dict(sorted(v.items())) for k, v in sorted(assets.items())},
    }


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
    release = build_release(ordered)
    RELEASE.write_text(json.dumps(release, indent=2, sort_keys=True) + "\n")
    n_assets = sum(len(v) for v in release["assets"].values())
    print(
        f"build_catalog: wrote {RELEASE} "
        f"(tag {release['tag']}, {n_assets} downloadable assets)"
    )


if __name__ == "__main__":
    from typing import NoReturn

    main()

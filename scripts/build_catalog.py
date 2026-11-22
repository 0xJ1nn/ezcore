#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

"""Builds cores/catalog.json (+ cores/release.json) from cores/*/manifests.

Single source of truth is the per-core manifests; the catalog is a
deterministic merge (sorted ids, sorted keys) bundled as a Flutter asset
and loaded at startup by AppState. Run before flutter pub get/test/build:

    python3 scripts/build_catalog.py

cores/release.json is the on-demand delivery map (hybrid core delivery): the GitHub
release tag matching this pubspec version plus the asset filename for
every delivery=download core that has a pin for that platform-arch **and
whose bytes are actually attached to the release**. The app downloads
exactly these names, sha256-verifies them against the pin in the catalog,
and stages them. Every buildable platform that publishes no assets is
listed in `unavailablePlatforms` with the reason, so the app can say
plainly why a core cannot be downloaded there.

cores/published-sha256.txt is the release's own SHA256SUMS.txt with the tag
on a `# vX.Y.Z` line. It is what makes the map honest: an asset the host
does not serve is never offered, and a pin that disagrees with the served
bytes is a hard failure here rather than a download that verifies and is
then thrown away on every device.

    python3 scripts/build_catalog.py --check   # verify the committed files

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
PUBLISHED = CORES / "published-sha256.txt"

# Repository slug whose releases host the on-demand core assets. Manual
# uploads only (`gh release upload`) — GitHub is repo-hosting, no CI (hybrid core delivery).
REPO = "0xJ1nn/ezcore"

# Platform-arch keys release.sh assembles an app for. Core assets for the
# release are uploaded by hand; every key is reported here, published or not,
# so the app can name an absent platform instead of silently omitting it.
RELEASE_PLATFORMS = (
    "macos-arm64",
    "windows-x64",
    "linux-x64",
    "android-arm64",
    "ios-arm64",
)

PLATFORM_LABELS = {
    "macos": "macOS",
    "windows": "Windows",
    "linux": "Linux",
    "android": "Android",
    "ios": "iOS",
}

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


def read_published() -> "tuple[str, dict[str, str]]":
    """The release's own SHA256SUMS.txt, with its tag on a `# vX.Y.Z` line."""
    if not PUBLISHED.is_file():
        fail(f"{PUBLISHED} is missing; it records what the release host serves")
    tag = ""
    sums: dict[str, str] = {}
    for line in PUBLISHED.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            if not tag and stripped[1:].strip().startswith("v"):
                tag = stripped[1:].strip()
            continue
        parts = stripped.split()
        if len(parts) == 2:
            sums[parts[1]] = parts[0].lower()
    if not tag:
        fail(f"{PUBLISHED}: record the release tag on a '# vX.Y.Z' line")
    if not sums:
        fail(f"{PUBLISHED}: no asset digests recorded")
    return tag, sums


def unavailable_platforms(catalog: dict, assets: dict) -> dict:
    """Plain reason for every buildable platform with no published assets."""
    result = {}
    for plat in RELEASE_PLATFORMS:
        if plat in assets:
            continue
        os_name = plat.split("-")[0]
        label = PLATFORM_LABELS[os_name]
        if os_name == "ios":
            result[plat] = {
                "reason": "policy",
                "message": "On-demand core downloads are not offered on iOS.",
            }
        elif any(
            m.get("delivery", {}).get(os_name) == "download"
            for m in catalog.values()
        ):
            result[plat] = {
                "reason": "assetsNotPublished",
                "message": (
                    f"No on-demand core assets are published for {label} yet. "
                    "Install a core from a file instead."
                ),
            }
        else:
            result[plat] = {
                "reason": "bundledElsewhere",
                "message": (
                    f"Cores are bundled with the {label} app; no on-demand "
                    "downloads are published."
                ),
            }
    return result


def build_release(catalog: dict) -> dict:
    """cores/release.json — tag + downloadable asset names (hybrid core delivery)."""
    tag, published = read_published()
    expected_tag = f"v{pubspec_version()}"
    if tag != expected_tag:
        fail(
            f"{PUBLISHED} describes {tag} but this build downloads from "
            f"{expected_tag}; copy the current release's SHA256SUMS.txt"
        )
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
            name = f"{cid}_libretro-{plat}.{asset_ext(plat)}"
            digest = published.get(name)
            if digest is None:
                # Not attached to the release: offering it would install a
                # button that only ever 404s. The platform is reported below.
                continue
            if digest != pin.lower():
                fail(
                    f"{cid}: {plat} pin {pin[:12]} does not match the "
                    f"{tag} asset {digest[:12]} ({name}); the app would "
                    "download, verify and discard it"
                )
            assets.setdefault(plat, {})[cid] = name
    # The catalog and the release map must agree, or the app offers an
    # install that can only ever fail. Three impossible states are refused
    # here rather than shipped to a device:
    #   * a core whose delivery is absent everywhere but that still has pins;
    #   * a download-delivery pin with no asset on the release host;
    #   * a download-delivery core that no platform can fetch at all.
    download_cores: set[str] = set()
    for cid, m in sorted(catalog.items()):
        if m.get("blocked_reason"):
            continue
        delivery = m.get("delivery", {})
        if not any(v in ("bundled", "download") for v in delivery.values()):
            if m.get("artifacts"):
                fail(
                    f"{cid}: every platform says absent, so pins for "
                    f"{sorted(m['artifacts'])} can never be installed"
                )
            continue
        if any(v == "download" for v in delivery.values()):
            download_cores.add(cid)
        for plat, pin in sorted((m.get("artifacts") or {}).items()):
            if not pin or delivery.get(plat.split("-")[0]) != "download":
                continue
            name = f"{cid}_libretro-{plat}.{asset_ext(plat)}"
            if name not in published:
                fail(
                    f"{cid}: {plat} has pin {pin[:12]} but the {tag} release "
                    f"serves no {name}; remove the pin or publish the asset"
                )
    offered = {cid for group in assets.values() for cid in group}
    unreachable = sorted(download_cores - offered)
    if unreachable:
        fail(
            f"no platform can download {', '.join(unreachable)}; "
            "change delivery to bundled/absent or publish their assets"
        )

    ordered_assets = {k: dict(sorted(v.items())) for k, v in sorted(assets.items())}
    return {
        "repo": REPO,
        "tag": tag,
        "assets": ordered_assets,
        "unavailablePlatforms": unavailable_platforms(catalog, ordered_assets),
    }


def main() -> None:
    check = "--check" in sys.argv
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
    release = build_release(ordered)
    catalog_text = json.dumps(ordered, indent=2, sort_keys=True) + "\n"
    release_text = json.dumps(release, indent=2, sort_keys=True) + "\n"
    if check:
        if CATALOG.read_text() != catalog_text:
            fail(f"{CATALOG} is out of date (run scripts/build_catalog.py)")
        if RELEASE.read_text() != release_text:
            fail(f"{RELEASE} is out of date (run scripts/build_catalog.py)")
        print("build_catalog: checked catalog and release map")
        return
    CATALOG.write_text(catalog_text)
    print(f"build_catalog: wrote {CATALOG} ({len(ordered)} cores)")
    RELEASE.write_text(release_text)
    n_assets = sum(len(v) for v in release["assets"].values())
    n_absent = len(release["unavailablePlatforms"])
    print(
        f"build_catalog: wrote {RELEASE} "
        f"(tag {release['tag']}, {n_assets} downloadable assets, "
        f"{n_absent} platforms with no assets)"
    )


if __name__ == "__main__":
    from typing import NoReturn

    main()

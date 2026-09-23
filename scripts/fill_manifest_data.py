#!/usr/bin/env python3
"""Fills per-OS `execution` strategy + verified cheat flags across manifests.

Policy (mirrors docs/ARCHITECTURE.md rule 3):
- iOS must never resolve to dynarec (no JIT). iOS entries are interpreter-only
  requirements that the platform core builds (scripts/build_core.sh) enforce.
- Desktop/Android entries describe the strategy the shipped artifact uses;
  the platform build matrix verifies them (docs/MATRIX.md).
- Cheat flags only flip where upstream libretro capability is documented
  (docs.libretro.com feature tables / .info `cheats = "true"`).

Usage:  python3 scripts/fill_manifest_data.py [--check]
--check exits nonzero on any drift without writing (CI gate).
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OS5 = ("macos", "windows", "linux", "android", "ios")

INTERP_ALL = {os: "interpreter" for os in OS5}
JIT_DESKTOP = {
    "macos": "dynarec",
    "windows": "dynarec",
    "linux": "dynarec",
    "android": "dynarec",
    "ios": "interpreter",
}
JIT_NO_IOS = {k: v for k, v in JIT_DESKTOP.items() if k != "ios"}

EXECUTION = {
    "pocketbit": INTERP_ALL,
    "gambatte": INTERP_ALL,
    "advancebit": JIT_DESKTOP,
    "nesbyte": INTERP_ALL,
    "superfx": INTERP_ALL,
    "blastproc": INTERP_ALL,
    "joystick": INTERP_ALL,
    "realmode": INTERP_ALL,  # ARM/PPC ships the normal core; see MATRIX.md
    "cardcon": INTERP_ALL,
    "geometry1": JIT_DESKTOP,
    "rcp64": JIT_DESKTOP,
    "dualscreen": JIT_DESKTOP,
    "portcomp": JIT_DESKTOP,
    "dreamarc": JIT_DESKTOP,
    "powercube": JIT_NO_IOS,  # ios delivery absent; do not declare it
    "twinsh": INTERP_ALL,  # Mednafen Saturn: SH-2 interpreter
    # Verified 2026-09-18: USE_CYCLONE=0 by default and only enabled for
    # 32-bit ARM (rpi1/rpi2/rpi3-32); all 64-bit builds use the Musashi C
    # interpreter. No JIT anywhere we ship.
    "coinbox": INTERP_ALL,
    "pointclick": INTERP_ALL,
}

# Verified against libretro docs/.info (cheats = "true"); families must exist
# in lib/cores/cheat_validators.dart (CI cross-checks).
CHEATS = {
    "twinsh": ["saturn_gameshark"],
}

# Delivery = what release.sh ships per OS. Three values ship: `bundled`
# (in the package), `download` (fetched on demand from this release's core
# assets and sha256-verified before staging — ADR-013), and `absent`.
# iOS is never `download` (App Review 2.5.2/4.7; see CoreManifest.validate)
# and desktop/mobile apps otherwise carry their tier, verified by MATRIX.md.
_TIER_DESKTOP = [
    "pocketbit", "advancebit", "nesbyte", "superfx", "blastproc",
    "joystick", "cardcon", "twinsh", "coinbox", "pointclick",
    "realmode", "geometry1", "rcp64", "dualscreen", "portcomp",
    "dreamarc", "powercube",
]
_TIER_ANDROID = [
    "pocketbit", "advancebit", "nesbyte", "superfx", "blastproc",
    "joystick", "cardcon", "realmode", "pointclick", "coinbox",
]
_TIER_IOS = [
    "pocketbit", "nesbyte", "superfx", "blastproc",
    "joystick", "cardcon", "realmode", "pointclick",
    # fbneo excluded: its gated_reason requires IP-lawyer review +
    # compat-allowlist + no-CHD posture first (see manifest + MATRIX.md).
]

# Hybrid download set (ADR-013): staged giants (>= ~25 MB — pointclick
# 170M, dreamarc 39M, powercube 27M on linux-x64) leave the desktop
# package so the app stays lightweight; the app fetches them on demand,
# sha256-verified against the manifest pin before staging. Android keeps
# even the giants bundled (heuristic: ship built-in while the APK stays
# reasonable; no android download assets are published yet). iOS keeps its
# tier value — never `download` (App Review 2.5.2/4.7).
# gambatte is in NO tier anywhere: GPL-2.0-only cannot combine with this
# GPL-3.0-only app, so its manifest delivery is absent on every OS
# (b1bb9d9); re-adding it without a license re-clear reopens the
# violation license_audit rejects.
_DOWNLOAD_DESKTOP = {"pointclick", "dreamarc", "powercube"}


def _delivery(cid: str) -> "dict[str, str] | None":
    if cid.endswith("_hold"):
        return None
    if cid in ("coinbox", "superfx", "blastproc"):
        # Non-commercial upstream licenses: never distributed in any binary,
        # free or paid — kept as build recipes only. See gated_reason in each
        # manifest + docs/MONETIZATION.md.
        return {
            "macos": "absent",
            "windows": "absent",
            "linux": "absent",
            "android": "absent",
            "ios": "absent",
        }
    ships = {
        "macos": "bundled" if cid in _TIER_DESKTOP else "absent",
        "windows": "bundled" if cid in _TIER_DESKTOP else "absent",
        "linux": "bundled" if cid in _TIER_DESKTOP else "absent",
        "android": "bundled" if cid in _TIER_ANDROID else "absent",
        "ios": "bundled" if cid in _TIER_IOS else "absent",
    }
    if cid in _DOWNLOAD_DESKTOP:
        # Hybrid set (ADR-013): desktop fetches these on demand; android
        # and ios keep their tier value unchanged (see _DOWNLOAD_DESKTOP).
        for os_name in ("macos", "windows", "linux"):
            if ships[os_name] == "bundled":
                ships[os_name] = "download"
    return ships


def fail(msg: str) -> "NoReturn":
    print(f"fill_manifest_data: ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    check = "--check" in sys.argv
    dirty: list[str] = []
    for path in sorted((ROOT / "cores").glob("*/manifest.json")):
        original = path.read_text()
        data = json.loads(original)
        cid = data["id"]
        changed = False
        want_exec = EXECUTION.get(cid)
        if want_exec is not None and data.get("execution") != want_exec:
            if check:
                dirty.append(f"{cid}: execution")
            else:
                data["execution"] = want_exec
                changed = True
        if cid in CHEATS:
            if data.get("cheats_supported") is not True or data.get(
                "cheat_families"
            ) != CHEATS[cid]:
                if check:
                    dirty.append(f"{cid}: cheats")
                else:
                    data["cheats_supported"] = True
                    data["cheat_families"] = CHEATS[cid]
                    changed = True
        want_delivery = _delivery(cid)
        if want_delivery is not None and data.get("delivery") != want_delivery:
            if check:
                dirty.append(f"{cid}: delivery")
            else:
                data["delivery"] = want_delivery
                changed = True
        if changed and not check:
            path.write_text(
                json.dumps(data, indent=2, ensure_ascii=False) + "\n"
            )
    if check and dirty:
        fail("manifest drift: " + ", ".join(dirty))
    print(f"fill_manifest_data: {'checked' if check else 'wrote'} "
          f"{len(EXECUTION)} execution entries")


if __name__ == "__main__":
    from typing import NoReturn

    main()

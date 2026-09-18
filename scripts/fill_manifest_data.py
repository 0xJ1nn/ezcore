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
    "sameboy": INTERP_ALL,
    "gambatte": INTERP_ALL,
    "mgba": JIT_DESKTOP,
    "mesen": INTERP_ALL,
    "snes9x": INTERP_ALL,
    "genesis_plus_gx": INTERP_ALL,
    "stella": INTERP_ALL,
    "dosbox_pure": INTERP_ALL,  # ARM/PPC ships the normal core; see MATRIX.md
    "beetle_pce": INTERP_ALL,
    "swanstation": JIT_DESKTOP,
    "mupen64plus": JIT_DESKTOP,
    "melonds": JIT_DESKTOP,
    "ppsspp": JIT_DESKTOP,
    "flycast": JIT_DESKTOP,
    "dolphin": JIT_NO_IOS,  # ios delivery absent; do not declare it
    "beetle_saturn": INTERP_ALL,  # Mednafen Saturn: SH-2 interpreter
    # Verified 2026-09-18: USE_CYCLONE=0 by default and only enabled for
    # 32-bit ARM (rpi1/rpi2/rpi3-32); all 64-bit builds use the Musashi C
    # interpreter. No JIT anywhere we ship.
    "fbneo": INTERP_ALL,
    "scummvm": INTERP_ALL,
}

# Verified against libretro docs/.info (cheats = "true"); families must exist
# in lib/cores/cheat_validators.dart (CI cross-checks).
CHEATS = {
    "beetle_saturn": ["saturn_gameshark"],
}

# Delivery = what release.sh ships per OS (bundled), or absent. There is
# no download infrastructure in v1 (see delivery_note in CoreManifest):
# desktop and mobile apps carry their tier, verified by MATRIX.md.
_TIER_DESKTOP = [
    "sameboy", "gambatte", "mgba", "mesen", "snes9x", "genesis_plus_gx",
    "stella", "beetle_pce", "beetle_saturn", "fbneo", "scummvm",
    "dosbox_pure", "swanstation", "mupen64plus", "melonds", "ppsspp",
    "flycast", "dolphin",
]
_TIER_ANDROID = [
    "sameboy", "gambatte", "mgba", "mesen", "snes9x", "genesis_plus_gx",
    "stella", "beetle_pce", "dosbox_pure", "scummvm", "fbneo",
]
_TIER_IOS = [
    "sameboy", "gambatte", "mesen", "snes9x", "genesis_plus_gx",
    "stella", "beetle_pce", "dosbox_pure", "scummvm",
    # fbneo excluded: its gated_reason requires IP-lawyer review +
    # compat-allowlist + no-CHD posture first (see manifest + MATRIX.md).
]


def _delivery(cid: str) -> "dict[str, str] | None":
    if cid.endswith("_hold"):
        return None
    if cid == "fbneo":
        # Manifest-gated: desktop/Android installable only, and only after
        # the review/posture conditions in gated_reason are met.
        return {
            "macos": "bundled",
            "windows": "bundled",
            "linux": "bundled",
            "android": "bundled",
            "ios": "absent",
        }
    return {
        "macos": "bundled" if cid in _TIER_DESKTOP else "absent",
        "windows": "bundled" if cid in _TIER_DESKTOP else "absent",
        "linux": "bundled" if cid in _TIER_DESKTOP else "absent",
        "android": "bundled" if cid in _TIER_ANDROID else "absent",
        "ios": "bundled" if cid in _TIER_IOS else "absent",
    }


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

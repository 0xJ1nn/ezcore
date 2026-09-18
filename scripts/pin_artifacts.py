#!/usr/bin/env python3
"""Records built core hashes into manifests as platform-arch pins.

Usage: python3 scripts/pin_artifacts.py <platform-arch> [--out <dir>]
       python3 scripts/pin_artifacts.py <platform-arch> [--out <dir>] --check

Reads <out>/<id>/SHA256SUMS (written by build_core.sh stage()), verifies
each staged artifact, and writes artifacts[<platform-arch>] into
cores/<id>/manifest.json, then regenerates cores/catalog.json.

--check verifies staged hashes against committed pins without writing
(release gate: the bundle must match the reviewed pins exactly).

Pins are build evidence, never aspirational: only run this after a real
platform build + boot matrix pass (docs/MATRIX.md). Review the manifest
diff before committing.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def fail(msg: str) -> "NoReturn":
    print(f"pin_artifacts: ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--out")]
    check_only = "--check" in sys.argv
    args = [a for a in args if a != "--check"]
    out_idx = next(
        (i for i, a in enumerate(sys.argv) if a == "--out"), None
    )
    if not args:
        fail("usage: pin_artifacts.py <platform-arch> [--out <dir>] [--check]")
    plat = args[0]
    if not re.fullmatch(r"[a-z]+-[a-z0-9]+", plat):
        fail(f"bad platform-arch key: {plat!r}")
    out = (
        Path(sys.argv[out_idx + 1])
        if out_idx is not None
        else ROOT / "native" / f"cores-{plat}"
    )
    if not out.is_dir():
        fail(f"no staged output at {out}")
    updated: list[str] = []
    mismatched: list[str] = []
    for core_dir in sorted(out.iterdir()):
        if not core_dir.is_dir():
            continue
        sums = core_dir / "SHA256SUMS"
        if not sums.is_file():
            print(f"pin_artifacts: skip {core_dir.name} (no SHA256SUMS)")
            continue
        line = sums.read_text().strip().splitlines()[0]
        sha, _, fname = line.partition("  ")
        if len(sha) != 64:
            fail(f"{sums}: unparseable sums line")
        artifact = core_dir / fname.strip()
        if not artifact.is_file():
            fail(f"{sums}: missing artifact {fname.strip()}")
        manifest_path = ROOT / "cores" / core_dir.name / "manifest.json"
        if not manifest_path.is_file():
            fail(f"no manifest for staged core {core_dir.name}")
        data = json.loads(manifest_path.read_text())
        if data.get("blocked_reason"):
            fail(f"refusing to pin blocked core {core_dir.name}")
        current = data.get("artifacts", {}).get(plat)
        if current == sha:
            continue
        if check_only:
            mismatched.append(f"{core_dir.name} (staged {sha[:12]} != pinned {(current or 'absent')[:12]})")
            continue
        data.setdefault("artifacts", {})[plat] = sha
        manifest_path.write_text(
            json.dumps(data, indent=2, ensure_ascii=False) + "\n"
        )
        updated.append(f"{core_dir.name}={sha[:12]}")
    if check_only:
        if mismatched:
            fail("pin drift: " + ", ".join(mismatched))
        # Reverse direction: every pinned manifest must be staged, or the
        # release would silently ship an incomplete set. Same for every
        # core the delivery map promises this OS.
        os_name = plat.split("-")[0]
        staged_ids = {
            p.name for p in out.iterdir() if p.is_dir()
        }
        for path in sorted((ROOT / "cores").glob("*/manifest.json")):
            data = json.loads(path.read_text())
            if data.get("blocked_reason"):
                continue
            if data.get("artifacts", {}).get(plat) and data["id"] not in staged_ids:
                mismatched.append(f"{data['id']}: pinned but not staged")
            if data.get("delivery", {}).get(os_name) == "bundled" and data[
                "id"
            ] not in staged_ids:
                mismatched.append(
                    f"{data['id']}: delivery promises {os_name} but not staged"
                )
        if mismatched:
            fail("incomplete staged set: " + ", ".join(mismatched))
        print(f"pin_artifacts: {plat}: staged tree matches committed pins")
        return
    if updated:
        import subprocess

        subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "build_catalog.py")],
            check=True,
        )
    print(f"pin_artifacts: {plat}: pinned {len(updated)}: "
          f"{', '.join(updated) or 'already current'}")


if __name__ == "__main__":
    from typing import NoReturn

    main()

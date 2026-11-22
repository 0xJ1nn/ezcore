#!/usr/bin/env python3
"""Regression: frame evidence from test_core_boot must actually be reproducible.

Earlier evidence runs recorded `reproducible` by comparing two EXIT CODES and
did not capture a frame on the second run, so a core that paints a different
picture on every boot still counted as reproducible. A stored frame is
evidence only when

  1. the boot succeeds (exit 0),
  2. two independent runs print the SAME frame SHA-256, and
  3. that hash equals SHA-256 over the RGB bytes of the stored PPM.

Also assert the opposite failure is loud: asking for a frame at an unwritable
path must be exit 7, never a silent skip with a successful verdict.

Usage: test_frame_reproducibility.py <harness> <core> <rom> <workdir>
"""
from __future__ import annotations

import hashlib
import os
import pathlib
import re
import subprocess
import sys

FRAME_RE = re.compile(
    r"frame: (\d+)x(\d+) sum=(-?\d+) sha256=([0-9a-f]{64}) file=(\S+)")


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def boot(harness: str, core: str, rom: str, workdir: pathlib.Path,
         frame: pathlib.Path | None) -> tuple[int, dict | None, str]:
    env = dict(os.environ)
    if frame is not None:
        env["EZCORE_FRAME_PPM"] = str(frame)
    try:
        r = subprocess.run([harness, core, rom], cwd=str(workdir), env=env,
                           capture_output=True, text=True, timeout=300)
        rc, out = r.returncode, (r.stdout or "") + (r.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, None, "timed out"
    m = FRAME_RE.search(out)
    info = None
    if m:
        info = dict(w=int(m.group(1)), h=int(m.group(2)),
                    sum=int(m.group(3)), sha=m.group(4), file=m.group(5))
    return rc, info, out


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        fail("usage: test_frame_reproducibility.py <harness> <core> <rom> <workdir>")
    harness, core, rom = argv[1:4]
    workdir = pathlib.Path(argv[4])
    (workdir / "test-system").mkdir(parents=True, exist_ok=True)
    (workdir / "test-save").mkdir(parents=True, exist_ok=True)

    frames = []
    for i in (1, 2):
        p = workdir / f"frame{i}.ppm"
        rc, info, out = boot(harness, core, rom, workdir, p)
        if rc != 0:
            fail(f"run {i} exited {rc}: {out[-300:]}")
        if info is None:
            fail(f"run {i} printed no frame line")
        if info["sum"] <= 0:
            fail(f"run {i} pixel sum is {info['sum']}")
        if not p.exists():
            fail(f"run {i} named {p} but did not write it")
        raw = p.read_bytes()
        magic, _, rest = raw.partition(b"\n")
        _size, _, rest = rest.partition(b"\n")
        _maxval, _, pixels = rest.partition(b"\n")
        if magic.strip() != b"P6":
            fail(f"run {i} wrote a non-P6 PPM")
        actual = hashlib.sha256(pixels).hexdigest()
        if actual != info["sha"]:
            fail(f"run {i} printed sha {info['sha']} but PPM RGB hashes to {actual}")
        frames.append(info)

    if frames[0]["sha"] != frames[1]["sha"]:
        fail(f"frame hash not reproducible: {frames[0]['sha']} vs {frames[1]['sha']}")
    if frames[0]["sum"] != frames[1]["sum"]:
        fail(f"pixel sum not reproducible: {frames[0]['sum']} vs {frames[1]['sum']}")

    # A requested capture that cannot be written must fail the evidence, not
    # be silently skipped (test_core_boot.c exit 7 / MATRIX.md frame rule).
    rc, _info, _out = boot(harness, core, rom, workdir,
                           workdir / "no-such-dir" / "frame.ppm")
    if rc != 7:
        fail(f"unwritable EZCORE_FRAME_PPM exited {rc}, expected 7")

    print(f"PASS: frame {frames[0]['w']}x{frames[0]['h']} "
          f"sum={frames[0]['sum']} sha256={frames[0]['sha']} reproduced twice; "
          f"unwritable capture exits 7")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

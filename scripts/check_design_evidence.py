#!/usr/bin/env python3
"""Gate the committed Orbit design evidence.

Why this exists
---------------
`design/ezcore-orbit/verification/` is release evidence: the README and the
public claim of a verified multi-platform shell point at it. Three failures
were possible before this gate, and all three had already happened:

1. **Height drift was invisible.** `verify_brand.py` recorded `width`,
   `scrollWidth`, `accent` and `visibleText` but never the captured surface
   height, so `report.json` stayed byte-identical while 18 committed PNGs
   silently changed height (android +4px, ios +4px, windows +21px).
2. **A screenshot could be captured mid-animation.** The overlay has a `.3s`
   fade-in and the capture path had no settle wait, so a semi-transparent
   overlay with the library legible through it could be committed. The gate
   that graded those 36 states passed, because it only measured layout.
3. **A missing or truncated capture looked like success.** The matrix is only
   written at the end of a run, so a partial run left stale evidence in place.

This script is deliberately dependency-free (standard library only, PNG header
parsing included) so it can run in the pre-commit hook on any machine, with no
Playwright, no Pillow, and no local web server. It validates the *committed*
artefacts. Regenerating them is `verify_brand.py`'s job.

Usage:
    python3 scripts/check_design_evidence.py          # gate
    python3 scripts/check_design_evidence.py --json   # machine-readable
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERIFICATION = ROOT / "design" / "ezcore-orbit" / "verification"
REPORT = VERIFICATION / "report.json"

PLATFORMS = ("ios", "android", "mac", "windows", "linux", "web")
SCREENS = ("library", "systems", "details", "vault", "pause", "settings")
OVERLAY_SCREENS = ("details", "pause")

# full_page=True screenshots are at least the viewport tall. Anything shorter
# means the page failed to lay out and the capture is worthless.
MIN_HEIGHT = 900
MIN_WIDTH = 1000
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
# 1x1 fully transparent PNG — the classic "screenshot succeeded but page was
# blank" failure that a file-exists check cannot see.
BLANK_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
    "1f15c4890000000a49444154789c6360000002000154a24f5f0000000049454e44ae426082"
)

# Sizes legitimately vary per platform (phone portrait vs desktop shell), so
# there is no single hard-coded expectation. The invariant that must hold is
# that every capture from one run agrees on width, and that the recorded
# report matches the files on disk.
EXPECTED_STATES = len(PLATFORMS) * len(SCREENS)


class Failure(Exception):
    """A gate violation worth reporting with a file and a reason."""


def png_dimensions(path: Path) -> tuple[int, int]:
    """Read width/height from the IHDR chunk without decompressing pixel data."""
    try:
        blob = path.read_bytes()
    except OSError as exc:
        raise Failure(f"{path.name}: cannot read ({exc})") from exc
    if not blob.startswith(PNG_MAGIC):
        raise Failure(f"{path.name}: not a PNG")
    if len(blob) < 24:
        raise Failure(f"{path.name}: truncated ({len(blob)} bytes)")
    width, height = struct.unpack(">II", blob[16:24])
    return width, height


def check_images() -> list[dict]:
    """Every expected capture exists, is a real image, and is plausibly sized."""
    if not VERIFICATION.is_dir():
        raise Failure(f"missing evidence directory: {VERIFICATION}")

    results: list[dict] = []
    for platform in PLATFORMS:
        for screen in SCREENS:
            name = f"{platform}-{screen}.png"
            path = VERIFICATION / name
            if not path.is_file():
                raise Failure(f"{name}: missing capture for {platform}/{screen}")
            if path.stat().st_size == 0:
                raise Failure(f"{name}: empty file")
            width, height = png_dimensions(path)
            if width < MIN_WIDTH:
                raise Failure(
                    f"{name}: width {width}px is below the {MIN_WIDTH}px capture floor; "
                    "the page probably failed to lay out"
                )
            if height < MIN_HEIGHT:
                raise Failure(
                    f"{name}: height {height}px is below the {MIN_HEIGHT}px full-page "
                    "floor; the page probably failed to lay out"
                )
            results.append(
                {
                    "file": name,
                    "platform": platform,
                    "screen": screen,
                    "overlay": screen in OVERLAY_SCREENS,
                    "width": width,
                    "height": height,
                    "bytes": path.stat().st_size,
                    "blank": path.read_bytes() == BLANK_PNG,
                }
            )

    blanks = [r["file"] for r in results if r["blank"]]
    if blanks:
        raise Failure("blank 1x1 capture committed: " + ", ".join(sorted(blanks)))

    widths = {r["width"] for r in results}
    if len(widths) != 1:
        by_width: dict[int, list[str]] = {}
        for r in results:
            by_width.setdefault(r["width"], []).append(r["file"])
        raise Failure(
            "captures disagree on width, which means they are from different runs: "
            + "; ".join(f"{w}px -> {len(v)} files" for w, v in sorted(by_width.items()))
        )
    return results


def check_report(images: list[dict]) -> dict:
    """The report must describe this run, and its heights must match the files."""
    if not REPORT.is_file():
        raise Failure(f"missing {REPORT.relative_to(ROOT)}; no capture has been recorded")
    try:
        report = json.loads(REPORT.read_text())
    except json.JSONDecodeError as exc:
        raise Failure(f"report.json is not valid JSON: {exc}") from exc

    if report.get("errors"):
        raise Failure(f"report.json records page errors: {report['errors']}")

    matrix = report.get("matrix")
    if not isinstance(matrix, list):
        raise Failure("report.json has no matrix list")
    if len(matrix) != EXPECTED_STATES:
        raise Failure(
            f"report.json records {len(matrix)} states, expected {EXPECTED_STATES} "
            f"({len(PLATFORMS)} platforms x {len(SCREENS)} screens); a partial run "
            "would otherwise leave stale evidence looking current"
        )

    seen: dict[tuple[str, str], dict] = {}
    for row in matrix:
        key = (row.get("platform"), row.get("screen"))
        if key in seen:
            raise Failure(f"report.json has duplicate state {key[0]}/{key[1]}")
        seen[key] = row

    missing = [
        f"{p}/{s}"
        for p in PLATFORMS
        for s in SCREENS
        if (p, s) not in seen
    ]
    if missing:
        raise Failure("report.json is missing states: " + ", ".join(missing))

    # The blind spot that let 18 PNGs change height unnoticed: the report never
    # recorded a height, so nothing could cross-check the files. Now it does.
    #
    # Compare the CAPTURE size, not the child frame's viewport. The screenshots
    # are full_page and cover the whole wrapper page (masthead + device shell +
    # footer), so their pixel size is intentionally larger than the emulated
    # viewport. The report records both, under distinct keys, precisely so this
    # comparison is like-for-like.
    unrecorded = [
        f"{p}/{s}"
        for (p, s), row in seen.items()
        if "captureHeight" not in row or "captureWidth" not in row
    ]
    if unrecorded:
        raise Failure(
            "report.json states predate the capture-size recording, so drift "
            "cannot be detected; re-run design/ezcore-orbit/verify_brand.py. "
            "Affected: "
            + ", ".join(sorted(unrecorded)[:6])
            + (" …" if len(unrecorded) > 6 else "")
        )

    mismatches: list[str] = []
    for image in images:
        row = seen[(image["platform"], image["screen"])]
        if (row["captureHeight"] != image["height"]
                or row["captureWidth"] != image["width"]):
            mismatches.append(
                f"{image['file']} is {image['width']}x{image['height']} but report.json "
                f"says {row['captureWidth']}x{row['captureHeight']}"
            )
    if mismatches:
        raise Failure(
            "captures do not match the report that describes them, so the evidence is "
            "from more than one run:\n  " + "\n  ".join(sorted(mismatches))
        )

    checks = report.get("checks") or []
    if not any("backdrop-filter" in c for c in checks):
        raise Failure(
            "report.json does not record the overlay backdrop-filter check; the "
            "legibility regression this gate exists to catch would be invisible. "
            "Re-run design/ezcore-orbit/verify_brand.py"
        )
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument(
        "--evidence-dir",
        type=Path,
        default=None,
        help="override the verification directory (used by the test suite)",
    )
    args = parser.parse_args()

    if args.evidence_dir is not None:
        global VERIFICATION, REPORT
        VERIFICATION = args.evidence_dir.resolve()
        REPORT = VERIFICATION / "report.json"

    try:
        images = check_images()
        report = check_report(images)
    except Failure as exc:
        if args.json:
            print(json.dumps({"ok": False, "error": str(exc)}, indent=2))
        else:
            print("design evidence check FAILED\n")
            print(f"  {exc}\n")
            print("  Regenerate with: python3 design/ezcore-orbit/verify_brand.py")
            print("  (needs Playwright and a local server on 127.0.0.1:8770)")
        return 1

    heights = sorted({i["height"] for i in images})
    summary = {
        "ok": True,
        "captures": len(images),
        "build": report.get("build"),
        "errors": report.get("errors", []),
        "widths": sorted({i["width"] for i in images}),
        "distinct_heights": heights,
        "overlay_captures": sum(1 for i in images if i["overlay"]),
    }
    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print(
            f"PASS: {summary['captures']} captures, build {summary['build']}, "
            f"width {summary['widths']}, {summary['overlay_captures']} overlay states, "
            f"heights {heights}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())

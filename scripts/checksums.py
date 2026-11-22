#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

"""Writes and verifies the checksum sidecar a release publishes with its
downloads.

The record a reader can check is the one attached to the release: docs/INSTALL.md
tells them to verify a downloaded file against `SHA256SUMS.txt`, and the release
workflow writes that file over the artifacts it attaches. This script produces
it and re-verifies it:

    python3 scripts/checksums.py --write --root dist --record SHA256SUMS.txt
    python3 scripts/checksums.py --check --root dist --record SHA256SUMS.txt

No record of the source tree is committed. Such a record would go stale the
moment any pull request edits a tracked file, so every contribution would have
to regenerate it, and it could prove nothing that git does not already prove:
each commit and tree is named by the hash of its contents, and a hand that can
change a file can rewrite its line in the record too.

The subject is every regular file below `--root`, sorted, written as
`<sha256>  <path>` in the two-column form `sha256sum -c` and `shasum -a 256 -c`
already read. A `.git` directory inside the target is skipped, so an unpacked
checkout and a release directory are described the same way, and the record
file itself is never a subject: a digest cannot contain its own value, and a
record that listed itself could never verify. `--write` leaves an already
correct file untouched, so a second run writes nothing.

`--check` reports three kinds of finding and exits 1 when there is any: a file
whose bytes changed (CHANGED), a file on disk the record does not mention
(MISSING), and a record entry for a path that is not there (STALE).
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys
from pathlib import Path

RECORD_NAME = "SHA256SUMS.txt"


def fail(msg: str) -> "NoReturn":
    print(f"checksums: ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def file_names(root: Path) -> list[str]:
    """Every regular file below root, relative and sorted, minus git internals."""
    names = []
    for dirpath, dirnames, filenames in os.walk(root):
        # Prune rather than visit and discard: a checkout's .git can hold
        # thousands of files that no release record should ever name.
        dirnames[:] = sorted(name for name in dirnames if name != ".git")
        for name in filenames:
            if name == ".git":
                continue
            path = Path(dirpath, name)
            if path.is_file():
                names.append(path.relative_to(root).as_posix())
    return sorted(names)


def subjects(root: Path, record: str) -> list[str]:
    """The paths a record describes, sorted, never including the record."""
    return [name for name in file_names(root) if name != record]


def digest(path: Path) -> str:
    h = hashlib.sha256()
    try:
        with path.open("rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
    except OSError as e:
        fail(f"cannot hash {path}: {e.strerror}")
    return h.hexdigest()


def render(root: Path, record: str) -> tuple[str, int]:
    """The full record text and the number of files it covers."""
    lines = []
    for name in subjects(root, record):
        if "\n" in name:
            # A newline cannot be represented in the two-column form without
            # inventing an escaping scheme sha256sum would not understand.
            fail(f"path contains a newline: {name!r}")
        lines.append(f"{digest(root / name)}  {name}\n")
    return "".join(lines), len(lines)


def parse(record: Path) -> dict[str, str]:
    """path -> recorded digest, from a record in sha256sum's format."""
    entries: dict[str, str] = {}
    for number, line in enumerate(record.read_text().splitlines(), 1):
        stripped = line.strip()
        if not stripped:
            continue
        parts = stripped.split(None, 1)
        if len(parts) != 2:
            fail(f"{record}:{number}: expected '<sha256>  <path>'")
        sha, name = parts[0].lower(), parts[1].lstrip("*")
        if len(sha) != 64 or any(c not in "0123456789abcdef" for c in sha):
            fail(f"{record}:{number}: not a sha256 digest: {parts[0]!r}")
        entries[name] = sha
    return entries


def write(root: Path, record: str) -> None:
    sums = root / record
    if not sums.parent.is_dir():
        fail(f"no such directory: {sums.parent}")
    text, count = render(root, record)
    if sums.is_file() and sums.read_text() == text:
        print(f"checksums: {sums} is current ({count} files)")
        return
    sums.write_text(text)
    print(f"checksums: wrote {sums} ({count} files)")


def check(root: Path, record: str) -> None:
    sums = root / record
    if not sums.is_file():
        fail(f"{sums} is missing; run scripts/checksums.py --write --root {root}")
    recorded = parse(sums)
    current = subjects(root, record)
    changed: list[str] = []
    missing: list[str] = []
    for name in current:
        want = recorded.get(name)
        if want is None:
            missing.append(name)
        elif digest(root / name) != want:
            changed.append(name)
    stale = sorted(set(recorded) - set(current))
    findings = len(changed) + len(missing) + len(stale)
    if findings:
        print(f"checksums: {findings} finding(s):", file=sys.stderr)
        for name in changed:
            print(f"  CHANGED  {name}", file=sys.stderr)
        for name in missing:
            print(f"  MISSING  {name}", file=sys.stderr)
        for name in stale:
            print(f"  STALE    {name}", file=sys.stderr)
        print(
            f"checksums: run scripts/checksums.py --write --root {root} "
            f"--record {record} and publish the result",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"checksums: {sums} matches the files it covers ({len(current)} files)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--write",
        action="store_true",
        help=f"write {RECORD_NAME} from every file below --root",
    )
    mode.add_argument(
        "--check",
        action="store_true",
        help=f"verify {RECORD_NAME} against the files below --root",
    )
    parser.add_argument(
        "--root",
        type=Path,
        required=True,
        help="directory to describe, such as dist/ or an unpacked download",
    )
    parser.add_argument(
        "--record",
        default=RECORD_NAME,
        help=f"name of the record inside --root (default: {RECORD_NAME})",
    )
    args = parser.parse_args()
    root = args.root.resolve()
    if not root.is_dir():
        fail(f"no such directory: {root}")
    if args.write:
        write(root, args.record)
    else:
        check(root, args.record)


if __name__ == "__main__":
    from typing import NoReturn

    main()

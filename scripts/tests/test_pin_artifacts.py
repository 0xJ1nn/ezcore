# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "pin_artifacts.py"
PLAT = "linux-x64"
OS = "linux"


def digest(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


class PinArtifactsTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        (self.root / "scripts").mkdir()
        shutil.copy(SCRIPT, self.root / "scripts" / "pin_artifacts.py")
        (self.root / "cores").mkdir()
        (self.root / "native" / "pin-waivers").mkdir(parents=True)
        self.staged = self.root / "native" / f"cores-{PLAT}"
        self.staged.mkdir(parents=True)
        self.waiver = self.root / "native" / "pin-waivers" / f"{PLAT}.txt"

    def manifest(self, cid, pin, delivery="bundled"):
        core_dir = self.root / "cores" / cid
        core_dir.mkdir(parents=True, exist_ok=True)
        (core_dir / "manifest.json").write_text(
            json.dumps(
                {"id": cid, "artifacts": {PLAT: pin}, "delivery": {OS: delivery}}
            )
        )

    def stage(self, cid, content):
        core_dir = self.staged / cid
        core_dir.mkdir(parents=True, exist_ok=True)
        (core_dir / f"{cid}.so").write_bytes(content)

    def run_script(self, *flags):
        return subprocess.run(
            [
                "python3",
                str(self.root / "scripts" / "pin_artifacts.py"),
                PLAT,
                "--out",
                str(self.staged),
                *flags,
            ],
            capture_output=True,
            text=True,
        )

    def test_forward_drift_fails(self):
        self.manifest("corea", digest(b"pinned bytes"))
        self.stage("corea", b"staged bytes")
        result = self.run_script("--check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pin drift: corea (staged ", result.stderr)
        self.assertIn(" != pinned ", result.stderr)
        self.assertNotIn("incomplete staged set", result.stderr)

    def test_forward_match_reverse_omission_reports_incomplete_set(self):
        self.manifest("corea", digest(b"good bytes"))
        self.stage("corea", b"good bytes")
        self.manifest("coreb", digest(b"missing bytes"), delivery="absent")
        result = self.run_script("--check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("incomplete staged set: ", result.stderr)
        self.assertIn("coreb: pinned but not staged", result.stderr)
        self.assertNotIn("pin drift", result.stderr)

    def test_drift_only_passes_with_partial_tree(self):
        self.manifest("dlcore", digest(b"download bytes"), delivery="download")
        self.stage("dlcore", b"download bytes")
        self.manifest("coreb", digest(b"missing bytes"), delivery="bundled")
        result = self.run_script("--drift-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("drift-only", result.stdout)
        self.assertNotEqual(self.run_script("--check").returncode, 0)

    def test_waiver_cannot_mask_drift(self):
        self.manifest("corea", digest(b"pinned bytes"))
        self.stage("corea", b"staged bytes")
        self.waiver.write_text("corea  # audited gap\n")
        result = self.run_script("--check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pin drift: corea", result.stderr)
        self.assertNotIn("incomplete staged set", result.stderr)

    def test_waiver_still_excuses_reverse_omission(self):
        self.manifest("corea", digest(b"missing bytes"), delivery="bundled")
        self.waiver.write_text("corea  # audited gap\n")
        result = self.run_script("--check")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("incomplete staged set: ", result.stderr)
        self.assertIn("corea: pinned but not staged", result.stderr)


if __name__ == "__main__":
    unittest.main()

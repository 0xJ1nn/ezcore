# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "check_changelog.py"
CHANGELOG = """# Changelog

## [Unreleased]

### Added

- Existing work.

## [0.1.0]

- First release.
"""
WATCHED = (
    "lib", "runtime", "cores", "android", "ios", "macos", "linux", "windows",
)


class CheckChangelogTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        (self.root / "scripts").mkdir()
        shutil.copy(SCRIPT, self.root / "scripts" / "check_changelog.py")
        (self.root / "CHANGELOG.md").write_text(CHANGELOG)
        (self.root / "lib").mkdir()
        (self.root / "lib" / "app.dart").write_text("// base\n")
        self.git("init", "-q")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "base")
        self.base = self.git("rev-parse", "HEAD").stdout.strip()

    def git(self, *args):
        return subprocess.run(
            ["git", "-C", str(self.root), *args],
            capture_output=True, text=True,
        )

    def run_check(self, head="HEAD"):
        return subprocess.run(
            ["python3", str(self.root / "scripts" / "check_changelog.py"),
             "--root", str(self.root), "--base", self.base, "--head", head],
            capture_output=True, text=True,
        )

    def commit_all(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def change(self, path, content="// changed\n"):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)

    def add_unreleased_line(self, line="- A user-visible change. [linux]"):
        text = (self.root / "CHANGELOG.md").read_text()
        (self.root / "CHANGELOG.md").write_text(
            text.replace("### Added\n", f"### Added\n\n{line}", 1)
        )

    def test_code_change_without_changelog_line_is_rejected(self):
        self.change("lib/app.dart")
        self.commit_all("change lib")
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("CHANGELOG.md", result.stdout + result.stderr)
        self.assertIn("lib/app.dart", result.stdout + result.stderr)

    def test_code_change_with_unreleased_line_is_accepted(self):
        self.change("lib/app.dart")
        self.add_unreleased_line()
        self.commit_all("change lib and document it")
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_docs_only_change_without_changelog_line_is_accepted(self):
        self.change("docs/RELEASING.md", "# Releasing\n")
        self.commit_all("docs only")
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_every_watched_directory_is_checked(self):
        for directory in WATCHED:
            with self.subTest(directory=directory):
                self.change(f"{directory}/changed.txt", "x\n")
                self.commit_all(f"change {directory}")
                result = self.run_check()
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f"{directory}/", result.stdout + result.stderr)
                self.git("reset", "--hard", "-q", self.base)

    def test_changelog_line_outside_unreleased_is_rejected(self):
        self.change("lib/app.dart")
        text = (self.root / "CHANGELOG.md").read_text()
        (self.root / "CHANGELOG.md").write_text(text + "- stray line\n")
        self.commit_all("change lib with stray changelog line")
        result = self.run_check()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Unreleased", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()

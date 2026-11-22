"""Behavioural tests for scripts/checksums.py.

Each case builds a throwaway directory that looks like a release drop -- a
couple of artifacts, a nested file and a `.git` directory -- then writes the
record, mutates exactly one thing and asserts the finding `--check` reports: a
changed file, a file the record omits, a stale entry, and a directory that
still matches.

The tests drive `--root` at a plain directory because that is the only way the
script works: `--root` is required, so a bare `--write` cannot describe the
checkout it happens to be run from and leave a source-tree record behind.
"""
import hashlib
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "checksums.py"


class ChecksumsTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.write("ezcore-0.2.0-linux-x64.tar.gz", b"archive bytes")
        self.write("ezcore-0.2.0-x86_64.AppImage", b"appimage bytes")
        self.write("README.txt", b"how to install\n")

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data if isinstance(data, bytes) else data.encode())

    def run_script(self, *flags):
        return subprocess.run(
            ["python3", str(SCRIPT), *flags],
            capture_output=True,
            text=True,
            cwd=self.root,
        )

    def write_record(self, name="SHA256SUMS.txt"):
        result = self.run_script(
            "--write", "--root", str(self.root), "--record", name
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def record(self, name="SHA256SUMS.txt"):
        return (self.root / name).read_text().splitlines()

    def test_write_records_every_file_sorted_in_two_columns(self):
        written = self.write_record()
        self.assertIn("(3 files)", written.stdout)
        names = [line.split("  ", 1)[1] for line in self.record()]
        self.assertEqual(names, sorted(names))
        self.assertEqual(
            names,
            [
                "README.txt",
                "ezcore-0.2.0-linux-x64.tar.gz",
                "ezcore-0.2.0-x86_64.AppImage",
            ],
        )
        for line in self.record():
            sha, name = line.split("  ", 1)
            data = (self.root / name).read_bytes()
            self.assertEqual(sha, hashlib.sha256(data).hexdigest())

    def test_check_passes_on_the_tree_it_was_written_from(self):
        self.write_record()
        checked = self.run_script(
            "--check", "--root", str(self.root)
        )
        self.assertEqual(checked.returncode, 0, checked.stderr)
        self.assertIn("matches the files it covers", checked.stdout)
        self.assertIn("(3 files)", checked.stdout)

    def test_second_write_leaves_a_current_record_untouched(self):
        self.write_record()
        first = self.record()
        again = self.write_record()
        self.assertIn("is current", again.stdout)
        self.assertEqual(self.record(), first)

    def test_modified_file_is_reported_as_changed(self):
        self.write_record()
        self.write("README.txt", b"how to install, differently\n")
        result = self.run_script("--check", "--root", str(self.root))
        self.assertEqual(result.returncode, 1)
        self.assertIn("CHANGED  README.txt", result.stderr)
        self.assertNotIn("MISSING", result.stderr)
        self.assertNotIn("STALE", result.stderr)

    def test_file_the_record_omits_is_reported(self):
        self.write_record()
        self.write("ezcore-0.2.0-windows-x64.zip", b"zip bytes")
        result = self.run_script("--check", "--root", str(self.root))
        self.assertEqual(result.returncode, 1)
        self.assertIn("MISSING  ezcore-0.2.0-windows-x64.zip", result.stderr)
        self.assertNotIn("CHANGED", result.stderr)
        self.assertNotIn("STALE", result.stderr)

    def test_entry_for_a_removed_path_is_reported_as_stale(self):
        self.write_record()
        (self.root / "README.txt").unlink()
        result = self.run_script("--check", "--root", str(self.root))
        self.assertEqual(result.returncode, 1)
        self.assertIn("STALE    README.txt", result.stderr)
        self.assertNotIn("CHANGED", result.stderr)
        self.assertNotIn("MISSING", result.stderr)

    def test_missing_record_is_an_error_not_a_pass(self):
        result = self.run_script("--check", "--root", str(self.root))
        self.assertEqual(result.returncode, 1)
        self.assertIn("is missing", result.stderr)

    def test_nested_files_are_recorded_with_their_directory(self):
        self.write("nested/deep/notes.md", b"notes\n")
        self.write_record()
        names = [line.split("  ", 1)[1] for line in self.record()]
        self.assertIn("nested/deep/notes.md", names)

    def test_git_internals_are_never_recorded(self):
        # An unpacked checkout next to the artifacts: its .git can be large and
        # none of it is a released file.
        self.write(".git/config", b"[core]\n")
        self.write(".git/objects/ab/cdef", b"loose object\n")
        self.write("unpacked/ezcore/README.md", b"read me\n")
        self.write("unpacked/ezcore/.git/HEAD", b"ref: refs/heads/main\n")
        self.write_record()
        names = [line.split("  ", 1)[1] for line in self.record()]
        self.assertIn("unpacked/ezcore/README.md", names)
        self.assertEqual(
            [name for name in names if "/.git/" in f"/{name}"], []
        )

    def test_record_never_lists_itself(self):
        self.write_record()
        self.assertNotIn(
            "SHA256SUMS.txt",
            [line.split("  ", 1)[1] for line in self.record()],
        )

    def test_record_name_is_configurable(self):
        self.write_record("PACKAGE-SUMS")
        self.assertIn(
            "ezcore-0.2.0-linux-x64.tar.gz",
            [line.split("  ", 1)[1] for line in self.record("PACKAGE-SUMS")],
        )
        self.assertFalse((self.root / "SHA256SUMS.txt").exists())
        checked = self.run_script(
            "--check", "--root", str(self.root), "--record", "PACKAGE-SUMS"
        )
        self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_root_is_required(self):
        result = self.run_script("--write")
        self.assertEqual(result.returncode, 2)
        self.assertIn("--root", result.stderr)
        self.assertFalse((self.root / "SHA256SUMS.txt").exists())

    def test_root_that_does_not_exist_is_an_error(self):
        result = self.run_script(
            "--write", "--root", str(self.root / "absent")
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("no such directory", result.stderr)

    def test_write_and_check_are_mutually_exclusive(self):
        result = self.run_script("--write", "--check", "--root", str(self.root))
        self.assertEqual(result.returncode, 2)

    def test_record_verifies_with_the_platform_tools(self):
        """The format must stay readable by sha256sum and shasum, not just us."""
        self.write_record()
        tools = [
            ("sha256sum", ["sha256sum", "-c", "--quiet", "SHA256SUMS.txt"]),
            ("shasum", ["shasum", "-a", "256", "-c", "--quiet", "SHA256SUMS.txt"]),
        ]
        ran = False
        for name, argv in tools:
            probe = subprocess.run(
                ["sh", "-c", f"command -v {name}"], capture_output=True
            )
            if probe.returncode != 0:
                continue
            ran = True
            checked = subprocess.run(argv, cwd=self.root, capture_output=True)
            self.assertEqual(
                checked.returncode,
                0,
                f"{name} rejected the record: {checked.stderr!r}",
            )
        if not ran:
            self.skipTest("neither sha256sum nor shasum is installed")


if __name__ == "__main__":
    unittest.main()

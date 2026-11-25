#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception
"""End-to-end checks for the ezplay harness.

Runs ezplay against the deterministic synthetic core: no ROM, BIOS or game
content is involved. The harness must emit a JSON result with every check the
play spec defines, and must fail loudly on arguments it cannot honour.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

RUNTIME = Path(__file__).resolve().parent.parent
APP = RUNTIME.parent


def build_dir() -> Path:
    return Path(os.environ.get("EZPLAY_BUILD_DIR", RUNTIME / "build-linux"))


def ezplay_bin() -> Path:
    return build_dir() / "ezplay"


def synth_core() -> Path:
    candidates = [
        Path(os.environ.get("EZPLAY_CORE", build_dir() / "libsynth_libretro.so")),
        APP / "native" / "cores-linux-x64" / "synth" / "synth_libretro.so",
    ]
    for c in candidates:
        if c.exists():
            return c
    return candidates[0]


class EzplayTest(unittest.TestCase):
    def test_source_exists(self):
        self.assertTrue((RUNTIME / "test" / "ezplay.c").is_file(),
                        "runtime/test/ezplay.c has not been added")

    def test_harness_runs_synth_spec(self):
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        self.assertTrue(synth_core().is_file(), f"build the synthetic core: {synth_core()}")
        spec = RUNTIME / "test" / "ezplay_spec_synth.json"
        self.assertTrue(spec.is_file(), "the synthetic spec fixture is missing")
        with tempfile.TemporaryDirectory() as d:
            content = Path(d) / "fixture.synth"
            content.write_text("Synthetic harness fixture. Not game content.\n")
            proc = subprocess.run(
                [str(ezplay_bin()),
                 "--core", str(synth_core()),
                 "--content", str(content),
                 "--system-dir", d,
                 "--save-dir", d,
                 "--spec", str(spec),
                 "--cheat", "0101ABCD"],
                capture_output=True, text=True, timeout=600)
        self.assertEqual(proc.returncode, 0,
                         f"ezplay failed: {proc.stdout[-2000:]}\n{proc.stderr[-2000:]}")
        result = json.loads(proc.stdout)
        self.assertEqual(result["schema"], 1)
        self.assertEqual(result["system"], "synth")
        self.assertIn("frame_checkpoints", result)
        self.assertTrue(result["frame_checkpoints"])
        for cp in result["frame_checkpoints"]:
            self.assertEqual(len(cp["sha256"]), 64)
            self.assertGreaterEqual(cp["colours"], 1)
        self.assertGreater(result["audio"]["total_samples"], 0)
        self.assertGreater(result["audio"]["rms"], 0.0)
        self.assertGreater(result["speed"]["unpaced_fps"], 0.0)
        self.assertGreater(result["speed"]["realtime_ratio"], 0.0)
        self.assertEqual(result["save_state"]["verdict"], "PASS")
        self.assertEqual(result["save_state"]["mismatches"], 0)
        # The synthetic core has no SRAM, so the battery save is skipped.
        self.assertEqual(result["battery_save"]["verdict"], "SKIP")
        # The synthetic core exposes both cheat hooks and marks the frame.
        self.assertEqual(result["cheat"]["verdict"], "PASS")
        self.assertTrue(result["cheat"]["frame_changed"])
        self.assertGreaterEqual(result["fast_forward"]["2x"], 1.0)
        self.assertGreaterEqual(result["fast_forward"]["4x"], 1.0)
        self.assertEqual(result["verdict"], "PASS")

    def test_binary_finds_runtime_staged_beside_it(self):
        """The adb driver stages the runtime next to ezplay; no absolute path exists on device."""
        binary = ezplay_bin()
        self.assertTrue(binary.is_file(), f"build ezplay first: {binary}")
        if not sys.platform.startswith("linux"):
            self.skipTest("readelf check runs on the Linux build host")
        dynamic = subprocess.run(["readelf", "-d", str(binary)],
                                 capture_output=True, text=True, timeout=60)
        self.assertEqual(dynamic.returncode, 0, dynamic.stderr)
        self.assertIn("$ORIGIN", dynamic.stdout,
                      "ezplay must resolve libezcore_runtime.so beside itself")

    def test_foreign_content_is_rejected(self):
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        spec = RUNTIME / "test" / "ezplay_spec_synth.json"
        with tempfile.TemporaryDirectory() as d:
            wrong = Path(d) / "foreign.nes"
            wrong.write_bytes(b"\x00" * 64)
            proc = subprocess.run(
                [str(ezplay_bin()),
                 "--core", str(synth_core()),
                 "--content", str(wrong),
                 "--system-dir", d,
                 "--save-dir", d,
                 "--spec", str(spec)],
                capture_output=True, text=True, timeout=120)
        self.assertEqual(proc.returncode, 12, proc.stdout[-1000:])
        result = json.loads(proc.stdout)
        self.assertEqual(result["verdict"], "FAIL")
        self.assertIn("content", result["error"].lower())

    def test_unsupported_content_names_the_accepted_formats(self):
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        spec = RUNTIME / "test" / "ezplay_spec_psx_reject.json"
        self.assertTrue(spec.is_file(), "the disc-system spec fixture is missing")
        with tempfile.TemporaryDirectory() as d:
            unsupported = Path(d) / "program.exe"
            unsupported.write_text("Synthetic harness fixture. Not game content.\n")
            proc = subprocess.run(
                [str(ezplay_bin()),
                 "--core", str(synth_core()),
                 "--content", str(unsupported),
                 "--system-dir", d,
                 "--save-dir", d,
                 "--spec", str(spec)],
                capture_output=True, text=True, timeout=120)
        self.assertEqual(proc.returncode, 12,
                         f"ezplay output: {proc.stdout[-1000:]}\n{proc.stderr[-1000:]}")
        result = json.loads(proc.stdout)
        self.assertEqual(result["verdict"], "FAIL")
        diagnostic = result.get("error", "") + " " + proc.stderr
        self.assertIn("unsupported", diagnostic.lower())
        self.assertIn(".exe", diagnostic)
        self.assertIn("psx", diagnostic)
        for accepted in (".cue", ".bin", ".chd"):
            self.assertIn(accepted, diagnostic)

    def _legacy_core(self, zero: bool = False) -> Path:
        suffix = {"darwin": ".dylib", "win32": ".dll"}.get(sys.platform, ".so")
        name = "synth_legacy_sram_zero" if zero else "synth_legacy_sram"
        return build_dir() / f"lib{name}_libretro{suffix}"

    def _battery_spec(self, tmp: Path) -> Path:
        spec = json.loads((RUNTIME / "test" / "ezplay_spec_synth.json").read_text())
        spec["checks"]["battery_save_roundtrip"] = True
        path = tmp / "battery-spec.json"
        path.write_text(json.dumps(spec), encoding="utf-8")
        return path

    def _run_legacy(self, core: Path, spec: Path, tmp: Path):
        content = tmp / "fixture.synth"
        content.write_text("Synthetic harness fixture. Not game content.\n",
                           encoding="utf-8")
        return subprocess.run(
            [str(ezplay_bin()), "--core", str(core), "--content", str(content),
             "--system-dir", str(tmp), "--save-dir", str(tmp),
             "--spec", str(spec)],
            capture_output=True, text=True, timeout=600)

    def test_battery_reads_legacy_sram(self):
        """SRAM exposed only via retro_get_memory_data must round-trip."""
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        core = self._legacy_core()
        self.assertTrue(core.is_file(), f"build the legacy-SRAM core first: {core}")
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            proc = self._run_legacy(core, self._battery_spec(tmp), tmp)
        self.assertEqual(proc.returncode, 0,
                         f"ezplay: {proc.stdout[-1500:]}\n{proc.stderr[-1500:]}")
        result = json.loads(proc.stdout)
        battery = result["battery_save"]
        self.assertEqual(battery["verdict"], "PASS", battery.get("reason"))
        self.assertGreater(battery["bytes"], 0)
        self.assertEqual(result["checks"]["battery_save_roundtrip"], "PASS")

    def test_zero_filled_sram_is_not_battery_evidence(self):
        """A zero-filled legacy SRAM region must not pass the battery gate."""
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        core = self._legacy_core(zero=True)
        self.assertTrue(core.is_file(), f"build the zero-SRAM core first: {core}")
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            proc = self._run_legacy(core, self._battery_spec(tmp), tmp)
        result = json.loads(proc.stdout)
        battery = result["battery_save"]
        self.assertEqual(battery["verdict"], "FAIL")
        self.assertEqual(battery["bytes"], 0)
        self.assertEqual(result["checks"]["battery_save_roundtrip"], "FAIL")

    def test_watara_sv_content_is_accepted(self):
        """Supervision cartridges use .sv; the manifest lists it as supported."""
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        spec = RUNTIME / "test" / "ezplay_spec_watara.json"
        self.assertTrue(spec.is_file(), "the watara spec fixture is missing")
        with tempfile.TemporaryDirectory() as d:
            content = Path(d) / "fixture.sv"
            content.write_text("Synthetic harness fixture. Not game content.\n")
            proc = subprocess.run(
                [str(ezplay_bin()),
                 "--core", str(synth_core()),
                 "--content", str(content),
                 "--system-dir", d,
                 "--save-dir", d,
                 "--spec", str(spec)],
                capture_output=True, text=True, timeout=600)
        self.assertEqual(proc.returncode, 0,
                         f"ezplay refused a .sv cartridge: {proc.stdout[-1000:]}"
                         f"\n{proc.stderr[-1000:]}")
        result = json.loads(proc.stdout)
        self.assertEqual(result["system"], "watara")
        self.assertEqual(result["verdict"], "PASS")

    def test_watara_foreign_content_is_rejected(self):
        """Adding .sv must not open the gate to unrelated cartridges."""
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        spec = RUNTIME / "test" / "ezplay_spec_watara.json"
        with tempfile.TemporaryDirectory() as d:
            wrong = Path(d) / "foreign.nes"
            wrong.write_bytes(b"\x00" * 64)
            proc = subprocess.run(
                [str(ezplay_bin()),
                 "--core", str(synth_core()),
                 "--content", str(wrong),
                 "--system-dir", d,
                 "--save-dir", d,
                 "--spec", str(spec)],
                capture_output=True, text=True, timeout=120)
        self.assertEqual(proc.returncode, 12, proc.stdout[-1000:])
        result = json.loads(proc.stdout)
        self.assertEqual(result["verdict"], "FAIL")
        self.assertIn("unsupported content", result["error"].lower())

    def test_bad_arguments_are_rejected(self):
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        proc = subprocess.run([str(ezplay_bin()), "--core", "x"],
                              capture_output=True, text=True, timeout=120)
        self.assertEqual(proc.returncode, 10)
        self.assertIn("missing", (proc.stderr + proc.stdout).lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)

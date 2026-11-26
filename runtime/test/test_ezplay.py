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


def joystick_core() -> Path:
    override = os.environ.get("EZCORE_JOYSTICK_CORE")
    if override:
        return Path(override)
    return APP / "native" / "cores-linux-x64" / "joystick" / "joystick_libretro.so"


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

    def test_serialize_failure_keeps_frame_and_audio_evidence(self):
        """A failed snapshot is one check, not a reason to discard the session."""
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        core = build_dir() / "libsynth_save_fail_libretro.so"
        self.assertTrue(core.is_file(), f"build the save-failing core: {core}")
        spec = {
            "system": "synth",
            "frames": 120,
            "input": [{"at": 20, "press": ["a"], "hold": 6},
                      {"at": 40, "press": ["start"], "hold": 6}],
            "checks": {"video_changes_after_input": False, "min_colours": 1,
                       "audio_rms_min": 0.005, "speed_min": 0,
                       "save_state_roundtrip": True,
                       "battery_save_roundtrip": "n/a",
                       "fast_forward": {}, "cheat": False},
        }
        with tempfile.TemporaryDirectory() as d:
            spec_path = Path(d) / "spec.json"
            spec_path.write_text(json.dumps(spec), encoding="utf-8")
            content = Path(d) / "fixture.synth"
            content.write_text("Synthetic harness fixture. Not game content.\n",
                               encoding="utf-8")
            proc = subprocess.run(
                [str(ezplay_bin()), "--core", str(core), "--content", str(content),
                 "--system-dir", d, "--save-dir", d, "--spec", str(spec_path)],
                capture_output=True, text=True, timeout=120)
        result = json.loads(proc.stdout)
        self.assertIn("retro_serialize() failed", result["save_state"]["reason"])
        self.assertEqual(result["save_state"]["verdict"], "FAIL")
        self.assertEqual(result["checks"]["save_state_roundtrip"], "FAIL")
        # The rest of the session still produced real evidence.
        self.assertTrue(result["frame_checkpoints"])
        self.assertGreater(result["audio"]["total_samples"], 0)
        self.assertGreater(result["audio"]["rms"], 0.0)
        self.assertEqual(result["checks"]["min_colours"], "PASS")
        self.assertEqual(result["verdict"], "FAIL")

    def _save_state_result(self, core_name, spec_frames=120):
        core = build_dir() / f"lib{core_name}_libretro.so"
        self.assertTrue(core.is_file(), f"build the {core_name} core: {core}")
        spec = {
            "system": "synth",
            "frames": spec_frames,
            "input": [{"at": 20, "press": ["a"], "hold": 6},
                      {"at": 40, "press": ["start"], "hold": 6}],
            "checks": {"video_changes_after_input": False, "min_colours": 1,
                       "audio_rms_min": 0.005, "speed_min": 0,
                       "save_state_roundtrip": True,
                       "battery_save_roundtrip": "n/a",
                       "fast_forward": {}, "cheat": False},
        }
        with tempfile.TemporaryDirectory() as d:
            spec_path = Path(d) / "spec.json"
            spec_path.write_text(json.dumps(spec), encoding="utf-8")
            content = Path(d) / "fixture.synth"
            content.write_text("Synthetic harness fixture. Not game content.\n",
                               encoding="utf-8")
            proc = subprocess.run(
                [str(ezplay_bin()), "--core", str(core), "--content", str(content),
                 "--system-dir", d, "--save-dir", d, "--spec", str(spec_path)],
                capture_output=True, text=True, timeout=120)
        return json.loads(proc.stdout)

    def test_first_frame_after_snapshot_load_may_settle(self):
        """A render surface outside the snapshot may differ on one frame."""
        result = self._save_state_result("synth_volatile_frame")
        self.assertEqual(result["save_state"]["verdict"], "PASS",
                         result["save_state"]["reason"])
        self.assertEqual(result["save_state"]["mismatches"], 0)
        self.assertGreaterEqual(result["save_state"]["frames_compared"], 60)

    def test_settling_window_handles_two_volatile_frames(self):
        """A bounded settling window covers more than one transient frame."""
        result = self._save_state_result("synth_volatile_frames2")
        self.assertEqual(result["save_state"]["verdict"], "PASS",
                         result["save_state"]["reason"])
        self.assertEqual(result["save_state"]["mismatches"], 0)
        self.assertGreaterEqual(result["save_state"]["frames_compared"], 60)

    def test_settling_frame_does_not_hide_a_wrong_state(self):
        """Sixty compared frames must still catch a genuinely wrong snapshot."""
        result = self._save_state_result("synth_save_diverge")
        self.assertEqual(result["save_state"]["verdict"], "FAIL")
        self.assertGreater(result["save_state"]["mismatches"], 0)

    def test_audio_rms_uses_the_release_frame_window(self):
        """The spec measures RMS from the last event's release, not boot audio."""
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        core = build_dir() / "libsynth_audio_head_libretro.so"
        self.assertTrue(core.is_file(), f"build the audio-window core: {core}")
        spec = {
            "system": "synth",
            "frames": 120,
            "input": [{"at": 20, "press": ["a"], "hold": 6},
                      {"at": 40, "press": ["start"], "hold": 6}],
            "checks": {"video_changes_after_input": False, "min_colours": 1,
                       "audio_rms_min": 0.005, "speed_min": 0,
                       "save_state_roundtrip": "n/a",
                       "battery_save_roundtrip": "n/a",
                       "fast_forward": {}, "cheat": False},
        }
        with tempfile.TemporaryDirectory() as d:
            spec_path = Path(d) / "spec.json"
            spec_path.write_text(json.dumps(spec), encoding="utf-8")
            content = Path(d) / "fixture.synth"
            content.write_text("Synthetic harness fixture. Not game content.\n",
                               encoding="utf-8")
            proc = subprocess.run(
                [str(ezplay_bin()), "--core", str(core), "--content", str(content),
                 "--system-dir", d, "--save-dir", d, "--spec", str(spec_path)],
                capture_output=True, text=True, timeout=120)
        self.assertEqual(proc.returncode, 11, proc.stdout[-1000:] + proc.stderr[-500:])
        result = json.loads(proc.stdout)
        self.assertEqual(result["audio"]["rms"], 0.0)
        self.assertEqual(result["checks"]["audio_rms"], "FAIL")

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

    def _legacy_core(self, zero: bool = False, erased: bool = False) -> Path:
        suffix = {"darwin": ".dylib", "win32": ".dll"}.get(sys.platform, ".so")
        name = ("synth_legacy_sram_erased" if erased else
                "synth_legacy_sram_zero" if zero else "synth_legacy_sram")
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

    def test_directory_load_location_reaches_the_core(self):
        """A container's expanded location must be handed to the core."""
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        core = build_dir() / ("libsynth_dir_libretro" +
                              {"darwin": ".dylib", "win32": ".dll"}.get(sys.platform, ".so"))
        self.assertTrue(core.is_file(), f"build the directory core first: {core}")
        spec = json.loads((RUNTIME / "test" / "ezplay_spec_synth.json").read_text())
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            content = tmp / "fixture.synth"
            content.write_text("Synthetic harness fixture. Not game content.\n",
                               encoding="utf-8")
            location = tmp / "expanded"
            location.mkdir()
            (location / "SYNTH-DIR-MARKER").write_text("ready\n", encoding="utf-8")
            spec_path = tmp / "spec.json"
            spec_path.write_text(json.dumps(spec), encoding="utf-8")
            proc = subprocess.run(
                [str(ezplay_bin()), "--core", str(core), "--content", str(content),
                 "--system-dir", str(tmp), "--save-dir", str(tmp),
                 "--spec", str(spec_path), "--load-path", str(location)],
                capture_output=True, text=True, timeout=120)
        self.assertEqual(proc.returncode, 0,
                         f"ezplay did not use the expanded location: {proc.stderr[-1500:]}")
        result = json.loads(proc.stdout)
        self.assertEqual(result["verdict"], "PASS")
        self.assertGreater(result["audio"]["total_samples"], 0)
        self.assertEqual(result["checks"]["min_colours"], "PASS")

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

    def test_erased_flash_is_not_battery_evidence(self):
        """An all-0xFF save region is erased flash, not a gameplay write."""
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        core = self._legacy_core(erased=True)
        self.assertTrue(core.is_file(), f"build the erased-SRAM core first: {core}")
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            proc = self._run_legacy(core, self._battery_spec(tmp), tmp)
        result = json.loads(proc.stdout)
        battery = result["battery_save"]
        self.assertEqual(battery["verdict"], "FAIL")
        self.assertEqual(battery["bytes"], 0)
        self.assertEqual(result["checks"]["battery_save_roundtrip"], "FAIL")

    def test_battery_session_runs_scripted_input(self):
        """Battery evidence must include the spec's scripted button presses.

        This fixture's save RAM stays erased until the scripted button press
        at frame 180. A battery check that stops at frame 120 cannot see it.
        """
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        suffix = {"darwin": ".dylib", "win32": ".dll"}.get(sys.platform, ".so")
        core = build_dir() / f"libsynth_input_sram_libretro{suffix}"
        self.assertTrue(core.is_file(), f"build the input-SRAM core first: {core}")
        spec = RUNTIME / "test" / "ezplay_spec_input_sram.json"
        self.assertTrue(spec.is_file(), "the input-SRAM spec fixture is missing")
        with tempfile.TemporaryDirectory() as d:
            tmp = Path(d)
            content = tmp / "fixture.synth"
            content.write_text("Synthetic harness fixture. Not game content.\n",
                               encoding="utf-8")
            proc = subprocess.run(
                [str(ezplay_bin()), "--core", str(core), "--content", str(content),
                 "--system-dir", str(tmp), "--save-dir", str(tmp),
                 "--spec", str(spec)],
                capture_output=True, text=True, timeout=600)
        result = json.loads(proc.stdout)
        battery = result["battery_save"]
        self.assertEqual(battery["verdict"], "PASS",
                         f"battery check skipped the scripted input: {battery.get('reason')}")
        self.assertGreater(battery["bytes"], 0)
        self.assertEqual(result["checks"]["battery_save_roundtrip"], "PASS")

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

    def test_snes_cartridge_suffix_is_accepted(self):
        """The harness must accept the widespread .smc cartridge suffix."""
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        spec = RUNTIME / "test" / "ezplay_spec_snes_suffix.json"
        self.assertTrue(spec.is_file(), "the suffix spec fixture is missing")
        with tempfile.TemporaryDirectory() as d:
            content = Path(d) / "fixture.smc"
            content.write_text("Synthetic harness fixture. Not game content.\n")
            proc = subprocess.run(
                [str(ezplay_bin()),
                 "--core", str(synth_core()),
                 "--content", str(content),
                 "--system-dir", d,
                 "--save-dir", d,
                 "--spec", str(spec)],
                capture_output=True, text=True, timeout=120)
        self.assertNotEqual(proc.returncode, 12,
                            f"harness refused a .smc cartridge: {proc.stdout[-800:]}"
                            f"\n{proc.stderr[-800:]}")
        result = json.loads(proc.stdout)
        self.assertNotIn("unsupported content", (result.get("error") or "").lower())

    def test_indexed_filename_suffix_is_accepted(self):
        """A snapshot's trailing __N copy index is not part of the file type."""
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        spec = RUNTIME / "test" / "ezplay_spec_atari_suffix.json"
        self.assertTrue(spec.is_file(), "the indexed-suffix spec fixture is missing")
        with tempfile.TemporaryDirectory() as d:
            content = Path(d) / "fixture.a26__0"
            content.write_text("Synthetic harness fixture. Not game content.\n")
            proc = subprocess.run(
                [str(ezplay_bin()),
                 "--core", str(synth_core()),
                 "--content", str(content),
                 "--system-dir", d,
                 "--save-dir", d,
                 "--spec", str(spec)],
                capture_output=True, text=True, timeout=120)
        self.assertNotEqual(proc.returncode, 12,
                            f"harness refused an indexed cartridge: {proc.stdout[-800:]}"
                            f"\n{proc.stderr[-800:]}")
        result = json.loads(proc.stdout)
        self.assertNotIn("unsupported content", (result.get("error") or "").lower())

    def test_joystick_core_accepts_indexed_snapshot_name(self):
        """A copy index after the file type must not stop the core loading."""
        core = joystick_core()
        if not core.is_file():
            self.skipTest(f"build the joystick core first: {core}")
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        spec = RUNTIME / "test" / "ezplay_spec_atari_load.json"
        self.assertTrue(spec.is_file(), "the core load spec fixture is missing")
        with tempfile.TemporaryDirectory() as d:
            content = Path(d) / "fixture.a26__0"
            # Invented, silent image bytes: this checks filename handling,
            # not the quality of any particular game.
            content.write_bytes(bytes(4096))
            proc = subprocess.run(
                [str(ezplay_bin()),
                 "--core", str(core),
                 "--content", str(content),
                 "--system-dir", d,
                 "--save-dir", d,
                 "--spec", str(spec)],
                capture_output=True, text=True, timeout=180)
        self.assertNotEqual(proc.returncode, 12,
                            f"harness refused an indexed snapshot: {proc.stdout[-800:]}")
        self.assertNotIn("unrecognized",
                         (proc.stderr + (proc.stdout or "")).lower(),
                         "the core rejected the copy index as a file type")
        result = json.loads(proc.stdout)
        self.assertTrue(result["core"], "the core never identified itself")
        self.assertTrue(result["frame_checkpoints"],
                        "no play checkpoints were produced after loading")

    def test_bad_arguments_are_rejected(self):
        self.assertTrue(ezplay_bin().is_file(), f"build ezplay first: {ezplay_bin()}")
        proc = subprocess.run([str(ezplay_bin()), "--core", "x"],
                              capture_output=True, text=True, timeout=120)
        self.assertEqual(proc.returncode, 10)
        self.assertIn("missing", (proc.stderr + proc.stdout).lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)

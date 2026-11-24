# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

"""Recipe validation, pin enforcement and argument handling for the core driver.

Every case here runs without a compiler, a source checkout or a network call:
the driver is checked at the data and argument boundary, where silent source
drift and accidental builds of held cores have to be caught.
"""
import importlib.util
import io
import json
import re
import tempfile
import unittest
import zipfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("corebuild", ROOT / "scripts" / "corebuild.py")
cb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cb)

PIN = "a" * 40
OTHER = "b" * 40
ALL_TARGETS = list(cb.TARGETS)


def recipe(**overrides):
    """A minimal valid recipe; each caller breaks exactly one thing."""
    data = {
        "schema": 1,
        "id": "potator",
        "upstream": "https://github.com/libretro/potator.git",
        "source_dir": "potator",
        "pin": PIN,
        "pin_verified": True,
        "submodules": False,
        "patches": [],
        "build": {
            "system": "make",
            "dir": "platform/libretro",
            "target": "libretro",
            "jobs": 4,
            "args": {"default": []},
        },
        "outputs": {
            "macos-arm64": "potator_libretro.dylib",
            "ios-arm64": "potator_libretro.dylib",
            "android-arm64": "potator_libretro.so",
            "linux-x64": "potator_libretro.so",
            "windows-x64": "potator_libretro.dll",
        },
        "strip": {target: "none" for target in ALL_TARGETS},
        "license_files": ["LICENSE", "COPYING"],
        "platforms": list(cb.TARGETS),
    }
    data.update(overrides)
    return data


def documents(**overrides):
    """Catalog, lock and toolchain documents that agree with recipe()."""
    catalog = {
        "potator": {
            "id": "potator", "name": "Potator", "version": "1.0.5",
            "license": "Unlicense", "license_url": "https://example.invalid/license",
            "homepage": "https://example.invalid", "upstream": "libretro/potator",
            "systems": ["watara"], "extensions": ["bin"],
            "bios_required": False, "bios_files": [],
            "delivery": {p: "bundled" for p in cb.PLATFORMS},
            "execution": {p: "interpreter" for p in cb.PLATFORMS},
            "artifacts": {"linux-x64": "c" * 64},
            "provenance": {"built_from": "https://github.com/libretro/potator"},
        }
    }
    lock = {"schema": 1, "cores": {"potator": PIN}}
    toolchain = {
        "flutter": "3.47.8", "dart": "3.13.7", "ndk": "28.2.13676358",
        "cmake": "3.22.1", "xcode_minimum": "27",
        "ios_deployment_target": "15.0", "mingw": "14.2.0",
        "llvm_mingw": "21.1.0", "msvc": "2022",
    }
    docs = {"catalog": catalog, "lock": lock, "toolchain": toolchain}
    docs.update(overrides)
    return docs


class RecipeValidationTest(unittest.TestCase):
    def setUp(self):
        self.r = recipe()
        self.d = documents()

    def errors(self, r=None, d=None, target="linux-x64"):
        d = d or self.d
        return cb.validate_recipe(r or self.r, d["lock"], d["catalog"],
                                  d["toolchain"], target)

    def test_valid_fixture_has_no_errors(self):
        self.assertEqual(self.errors(), [])

    def test_missing_pin_is_an_error(self):
        self.r.pop("pin")
        self.assertTrue(any("pin" in e for e in self.errors()))

    def test_short_pin_is_an_error(self):
        self.r["pin"] = "d44bfa1"
        self.assertTrue(any("40" in e for e in self.errors()))

    def test_non_hex_pin_is_an_error(self):
        self.r["pin"] = "z" * 40
        self.assertTrue(any("pin" in e for e in self.errors()))

    def test_lock_mismatch_is_an_error(self):
        self.d["lock"]["cores"]["potator"] = OTHER
        self.assertTrue(any("lock" in e.lower() for e in self.errors()))

    def test_missing_lock_entry_is_an_error(self):
        self.d["lock"]["cores"].clear()
        self.assertTrue(any("lock" in e.lower() for e in self.errors()))

    def test_unknown_core_is_an_error(self):
        self.r["id"] = "not-in-catalog"
        self.assertTrue(any("catalog" in e.lower() for e in self.errors()))

    def test_held_core_is_never_shippable(self):
        self.r["id"] = "citra_hold"
        self.d["catalog"]["citra_hold"] = dict(
            self.d["catalog"]["potator"], id="citra_hold",
            blocked_reason="legal hold")
        self.assertTrue(any("hold" in e.lower() for e in self.errors()))

    def test_licence_gated_core_is_not_a_build_target(self):
        self.d["catalog"]["potator"]["gated_reason"] = "not for distribution"
        self.d["catalog"]["potator"]["delivery"] = {
            p: "absent" for p in cb.PLATFORMS}
        self.assertTrue(any("shippable" in e.lower() for e in self.errors()))

    def test_wrong_output_suffix_is_an_error(self):
        self.r["outputs"]["linux-x64"] = "potator_libretro.dylib"
        self.assertTrue(any("linux-x64" in e for e in self.errors()))

    def test_android_without_ndk_pin_is_an_error(self):
        self.d["toolchain"].pop("ndk")
        self.assertTrue(any("ndk" in e.lower()
                            for e in self.errors(target="android-arm64")))

    def test_ios_without_deployment_target_is_an_error(self):
        self.d["toolchain"].pop("ios_deployment_target")
        self.assertTrue(any("deployment" in e.lower()
                            for e in self.errors(target="ios-arm64")))

    def test_submodules_must_be_explicit(self):
        self.r["submodules"] = "whenever"
        self.assertTrue(any("submodule" in e.lower() for e in self.errors()))

    def test_unsafe_source_dir_is_rejected(self):
        self.r["source_dir"] = "../outside"
        self.assertTrue(any("source_dir" in e for e in self.errors()))

    def test_license_files_are_required(self):
        self.r["license_files"] = []
        self.assertTrue(any("licen" in e.lower() for e in self.errors()))


class CoverageTest(unittest.TestCase):
    def setUp(self):
        self.catalog = cb.load_json(cb.CATALOG)
        self.lock = cb.load_json(cb.LOCK)
        self.toolchain = cb.load_json(cb.TOOLCHAIN)
        self.recipes = cb.load_recipes(cb.RECIPES)

    def test_every_shippable_core_has_one_recipe_and_one_lock_entry(self):
        shippable = {cid for cid, m in self.catalog.items() if cb.is_shippable(m)}
        self.assertEqual(len(shippable), 18)
        self.assertEqual(set(self.recipes), shippable)
        self.assertEqual(set(self.lock["cores"]), shippable)
        self.assertEqual(self.recipes.keys() & {"citra_hold", "switch_hold"}, set())
        errors = []
        for cid, rec in self.recipes.items():
            errors += cb.validate_recipe(rec, self.lock, self.catalog,
                                         self.toolchain, "linux-x64")
        self.assertEqual(errors, [])

    def test_coverage_reports_a_deleted_recipe(self):
        self.assertEqual(cb.validate_coverage(self.recipes, self.lock, self.catalog,
                                              self.toolchain), [])
        missing = dict(self.recipes)
        missing.pop("gw")
        errors = cb.validate_coverage(missing, self.lock, self.catalog, self.toolchain)
        self.assertTrue(any("gw" in e for e in errors))

    def test_held_cores_cannot_get_recipes_or_lock_entries(self):
        for cid in ("citra_hold", "switch_hold"):
            self.assertNotIn(cid, self.recipes)
            self.assertNotIn(cid, self.lock["cores"])
        bad = dict(self.recipes, citra_hold=recipe(id="citra_hold"))
        self.assertTrue(any("hold" in e.lower() for e in
                            cb.validate_coverage(bad, self.lock, self.catalog,
                                                 self.toolchain)))

    def test_known_pins_are_the_recorded_build_commits(self):
        recorded = {
            "dualvu": "d44bfa1814b729d4a3ed3c6c3a945432d5ee5bbe",
            "gw": "91d599b951e7bfe7e040347f58667cba20074adc",
            "potator": "227c5f6f3ce74d32e9002ce24c1420288559a860",
            "dreamarc": "eddf2635867f0f16f64bebd3185db151c99c551c",
            "lrps2": "cac1c32c7d4c2ad00edd6f4ba756340cefb39dd3",
            "portcomp": "2e6fd06ed6c77db467dea5fb3f67abd93457da20",
            "powercube": "fad480aced85403350597c5914540a97f6f53549",
        }
        for cid, sha in recorded.items():
            self.assertEqual(self.recipes[cid]["pin"], sha, cid)
            self.assertEqual(self.lock["cores"][cid], sha, cid)

    def test_android_targets_do_not_imply_published_assets(self):
        declared = ["dreamarc", "dualscreen", "dualvu", "geometry1", "lrps2",
                    "portcomp", "powercube", "rcp64", "twinsh"]
        for cid in declared:
            self.assertIn("android-arm64", self.recipes[cid]["platforms"], cid)
            self.assertNotIn("android-arm64",
                             self.recipes[cid]["pinned_targets"], cid)
        for cid in ("potator", "gw"):
            self.assertIn("android-arm64", self.recipes[cid]["pinned_targets"])

    def test_recipes_name_existing_build_functions(self):
        script = cb.BUILD_SCRIPT.read_text(encoding="utf-8")
        for cid in self.recipes:
            self.assertIn(f"build_{cid}()", script, cid)

    def test_recipe_source_dirs_match_the_existing_build_script(self):
        script = cb.BUILD_SCRIPT.read_text(encoding="utf-8")
        for cid, rec in self.recipes.items():
            self.assertIn(rec["source_dir"], script, cid)

    def test_recipes_carry_no_private_notes(self):
        forbidden = re.compile(
            r"(/home/|/Users/|LP-\d{3}|ezcore-workspace|\bworkspace\b|"
            r"\bagent\b|\bHLE\b|\bROMs?\b|\bBIOS\b|pin_origin|\bnotes\b|"
            r"\bprivate\b|\b2026-\d{2}-\d{2}\b)", re.I)
        for cid, rec in self.recipes.items():
            hits = forbidden.findall(json.dumps(rec))
            self.assertEqual(hits, [], cid)


class PinEnforcementTest(unittest.TestCase):
    def test_checkout_head_must_equal_pin(self):
        calls = []

        def fake_run(cmd, **kw):
            calls.append(cmd)
            return type("R", (), {"returncode": 0, "stdout": PIN + "\n",
                                  "stderr": ""})()

        cb.verify_checkout_pin(Path("/tmp/src"), PIN, run=fake_run)
        with self.assertRaises(cb.PinError):
            cb.verify_checkout_pin(Path("/tmp/src"), OTHER, run=fake_run)
        self.assertTrue(any(c[:3] == ["git", "rev-parse", "HEAD"] for c in calls))

    def test_clone_fetches_pin_not_a_floating_default_branch(self):
        calls = []

        def fake_run(cmd, **kw):
            calls.append(cmd)
            head = PIN if cmd[:3] == ["git", "rev-parse", "HEAD"] else ""
            return type("R", (), {"returncode": 0, "stdout": head,
                                  "stderr": ""})()

        cb.fetch_source("https://example.invalid/core.git", Path("/tmp/src"),
                        PIN, run=fake_run)
        joined = [" ".join(c) for c in calls]
        self.assertTrue(any("fetch origin " + PIN in c for c in joined), joined)
        self.assertTrue(any("checkout" in c and "--detach" in c and PIN in c
                            for c in joined), joined)
        self.assertFalse(any("clone" in c and "--branch" in c for c in joined))

    def test_wrong_checked_out_commit_is_refused(self):
        def fake_run(cmd, **kw):
            return type("R", (), {"returncode": 0, "stdout": OTHER + "\n",
                                  "stderr": ""})()

        with self.assertRaises(cb.PinError):
            cb.fetch_source("https://example.invalid/core.git",
                            Path("/tmp/src"), PIN, run=fake_run)

    def test_cache_key_covers_recipe_pin_and_toolchain(self):
        r = recipe()
        t = documents()["toolchain"]
        key = cb.cache_key(r, t, "linux-x64")
        self.assertNotEqual(key, cb.cache_key(dict(r, pin=OTHER), t, "linux-x64"))
        self.assertNotEqual(key, cb.cache_key(r, dict(t, ndk="99"), "android-arm64"))
        changed = dict(r, build=dict(r["build"], target="other"))
        self.assertNotEqual(key, cb.cache_key(changed, t, "linux-x64"))


class DriverArgumentTest(unittest.TestCase):
    def parse(self, argv):
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            return cb.parse_args(argv)

    def quiet(self, argv):
        with redirect_stdout(io.StringIO()) as out:
            rc = cb.main(argv)
        return rc, out.getvalue()

    def test_core_and_all_are_mutually_exclusive(self):
        with self.assertRaises(SystemExit):
            self.parse(["--platform", "linux", "--core", "gw", "--all"])
        with self.assertRaises(SystemExit):
            self.parse(["--core", "gw"])

    def test_platform_and_target_defaults(self):
        args = self.parse(["--platform", "android", "--all"])
        self.assertEqual(args.platform, "android")
        self.assertEqual(args.arch, "arm64-v8a")
        self.assertEqual(args.target, "android-arm64")
        self.assertEqual(self.parse(["--platform", "ios", "--core", "gw"]).target,
                         "ios-arm64")
        with self.assertRaises(SystemExit):
            self.parse(["--platform", "plan9", "--all"])
        with self.assertRaises(SystemExit):
            self.parse(["--platform", "linux", "--arch", "arm64", "--all"])

    def test_validate_recipes_passes_on_committed_data(self):
        rc, out = self.quiet(["--validate-recipes"])
        self.assertEqual(rc, 0, out)
        self.assertIn("PASS", out)

    def test_validate_catalog_passes_on_committed_data(self):
        rc, out = self.quiet(["--validate-catalog", "--platform", "linux"])
        self.assertEqual(rc, 0, out)
        self.assertIn("PASS", out)

    def test_dry_run_all_lists_every_core_and_writes_nothing(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        out_dir = Path(tmp.name) / "dist"
        rc, text = self.quiet(["--platform", "linux", "--all", "--dry-run",
                               "--out", str(out_dir)])
        self.assertEqual(rc, 0, text)
        self.assertIn("18 core(s)", text)
        self.assertIn("potator", text)
        self.assertIn("227c5f6f3ce74d32e9002ce24c1420288559a860", text)
        self.assertFalse(out_dir.exists())

    def test_dry_run_can_plan_one_named_core(self):
        rc, out = self.quiet(["--platform", "linux", "--core", "potator",
                              "--dry-run"])
        self.assertEqual(rc, 0, out)
        self.assertIn("potator", out)
        self.assertIn("dry-run", out)

    def test_unknown_held_and_undeclared_cores_are_refused(self):
        for cid, reason in (("no-such-core", "no-such-core"),
                            ("citra_hold", "hold"), ("gw", "ios-arm64")):
            platform = "ios" if cid == "gw" else "linux"
            rc, out = self.quiet(["--platform", platform, "--core", cid,
                                  "--dry-run"])
            self.assertEqual(rc, 2, out)
            self.assertIn(reason, out.lower())

    def test_a_build_choice_is_required(self):
        rc, out = self.quiet(["--platform", "linux", "--dry-run"])
        self.assertEqual(rc, 2)
        self.assertIn("--core", out)

    def test_emit_catalog_writes_a_checked_entry(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = Path(tmp.name) / "entry.json"
        rc, out = self.quiet(["--platform", "linux", "--core", "potator",
                              "--emit-catalog", str(path)])
        self.assertEqual(rc, 0, out)
        entry = json.loads(path.read_text())
        self.assertEqual(entry["id"], "potator")
        self.assertEqual(len(entry["source"]["commit"]), 40)
        self.assertEqual(entry["name"], cb.load_json(cb.CATALOG)["potator"]["name"])

    def test_build_command_delegates_to_existing_build_script(self):
        cmd = cb.build_command("potator", "linux")
        self.assertEqual(cmd[0], "bash")
        self.assertTrue(cmd[1].endswith("scripts/build_core.sh"), cmd)
        self.assertEqual(cmd[2], "potator")
        env = cb.build_env("linux", "x64", Path("out"))
        self.assertEqual(env["EZCORE_PLATFORM"], "linux")
        self.assertEqual(env["EZCORE_ARCH"], "x64")
        self.assertEqual(env["EZCORE_OUT_DIR"], "out")


class PackagingTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        (self.root / "lib.so").write_bytes(b"fake core bytes\n")
        (self.root / "LICENSE").write_text("Upstream licence text\n")
        self.r = recipe()
        self.d = documents()

    def test_package_writes_zip_manifest_source_and_index(self):
        entry = cb.package(self.r, self.d["catalog"], "linux-x64",
                           self.root / "lib.so", self.root / "dist",
                           license_file=self.root / "LICENSE",
                           toolchain=self.d["toolchain"])
        self.assertEqual(entry["id"], "potator")
        self.assertEqual(entry["target"], "linux-x64")
        self.assertEqual(len(entry["sha256"]), 64)
        zip_path = self.root / "dist" / "linux" / "potator-1.0.5-linux.zip"
        self.assertTrue(zip_path.is_file())
        with zipfile.ZipFile(zip_path) as z:
            names = set(z.namelist())
            self.assertEqual(names, {"potator_libretro.so", "manifest.json",
                                     "LICENSE.txt", "SOURCE.txt"})
            self.assertEqual(z.read("potator_libretro.so"), b"fake core bytes\n")
            source = z.read("SOURCE.txt").decode()
            self.assertIn(self.r["upstream"], source)
            self.assertIn(PIN, source)
            self.assertIn("patches:", source)
            self.assertNotIn("workspace", source)
            manifest = json.loads(z.read("manifest.json"))
            self.assertEqual(manifest["id"], "potator")
        index = json.loads((self.root / "dist" / "linux" / "index.json").read_text())
        self.assertEqual(index["potator"]["sha256"], entry["sha256"])
        self.assertEqual(index["potator"]["size"], len(b"fake core bytes\n"))

    def test_catalog_entry_uses_catalog_metadata_and_pinned_source(self):
        entry = cb.catalog_entry(self.r, self.d["catalog"], "linux-x64",
                                 artifact_sha="d" * 64)
        self.assertEqual(entry["name"], "Potator")
        self.assertEqual(entry["version"], "1.0.5")
        self.assertEqual(entry["artifacts"]["linux-x64"], "d" * 64)
        self.assertEqual(entry["source"]["commit"], PIN)
        self.assertEqual(cb.validate_catalog_entry(entry, self.d["catalog"]["potator"],
                                                    self.r, self.d["lock"]), [])

    def test_catalog_entry_rejects_a_tampered_pin(self):
        entry = cb.catalog_entry(self.r, self.d["catalog"], "linux-x64")
        entry["source"]["commit"] = OTHER
        self.assertTrue(any("commit" in e for e in
                            cb.validate_catalog_entry(entry, self.d["catalog"]["potator"],
                                                      self.r, self.d["lock"])))

    def test_build_delegates_to_build_core_sh_then_packages(self):
        src = self.root / "src" / "potator"
        src.mkdir(parents=True)
        (src / "LICENSE").write_text("Upstream licence text\n")
        built = self.root / "out" / "potator" / "potator_libretro.so"
        built.parent.mkdir(parents=True)
        built.write_bytes(b"fake core bytes\n")
        calls = []

        def fake_run(cmd, **kw):
            calls.append(cmd)
            return type("R", (), {"returncode": 0, "stdout": PIN + "\n",
                                  "stderr": ""})()

        entry = cb.build_one(self.r, self.d["lock"], self.d["catalog"],
                             self.d["toolchain"], "linux-x64",
                             app_root=ROOT, src_root=self.root / "src",
                             out_dir=self.root / "out",
                             cache_dir=self.root / "cache", run=fake_run)
        self.assertTrue(any("build_core.sh" in " ".join(c) for c in calls), calls)
        self.assertTrue(any(c[:3] == ["git", "rev-parse", "HEAD"] for c in calls))
        self.assertEqual(entry["library_sha256"],
                         cb.sha256_bytes(b"fake core bytes\n"))
        self.assertTrue((self.root / "out" / "linux" /
                         "potator-1.0.5-linux.zip").is_file())

    def test_post_build_pin_mismatch_is_refused(self):
        src = self.root / "src" / "potator"
        src.mkdir(parents=True)
        (src / "LICENSE").write_text("Upstream licence text\n")
        numbers = {"checks": 0}
        calls = []

        def fake_run(cmd, **kw):
            calls.append(cmd)
            head = PIN
            if cmd[:3] == ["git", "rev-parse", "HEAD"]:
                numbers["checks"] += 1
                if numbers["checks"] > 1:
                    head = OTHER
            return type("R", (), {"returncode": 0, "stdout": head + "\n",
                                  "stderr": ""})()

        with self.assertRaises(cb.PinError):
            cb.build_one(self.r, self.d["lock"], self.d["catalog"],
                         self.d["toolchain"], "linux-x64", app_root=ROOT,
                         src_root=self.root / "src", out_dir=self.root / "out",
                         cache_dir=self.root / "cache", run=fake_run)
        self.assertTrue(any("build_core.sh" in " ".join(c) for c in calls))

    def test_cache_skips_an_unchanged_core(self):
        cache = self.root / "cache"
        cache.mkdir()
        key = cb.cache_key(self.r, self.d["toolchain"], "linux-x64")
        record = {"id": "potator", "file": str(self.root / "lib.so"),
                  "sha256": "e" * 64}
        cb.write_json(cache / f"potator-linux-x64-{key[:16]}.json", record)

        def refused(*args, **kwargs):
            self.fail("a cached core must not call the build script")

        result = cb.build_one(self.r, self.d["lock"], self.d["catalog"],
                              self.d["toolchain"], "linux-x64", app_root=ROOT,
                              src_root=self.root / "src", out_dir=self.root / "out",
                              cache_dir=cache, run=refused)
        self.assertEqual(result, record)


if __name__ == "__main__":
    unittest.main()

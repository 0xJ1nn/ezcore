#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception
"""Checks for the upstream sources named by the core build script."""
from __future__ import annotations

import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "build_core.sh"


def script_text() -> str:
    return SCRIPT.read_text(encoding="utf-8")


def clone_urls(text: str) -> list[str]:
    return re.findall(r"^\s*clone\s+(\S+)", text, re.MULTILINE)


def function_body(text: str, name: str) -> str:
    start = re.search(rf"^{re.escape(name)}\(\)\s*\{{", text, re.MULTILINE)
    if start is None:
        return ""
    depth = 0
    for index in range(start.end() - 1, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start.start():index + 1]
    return ""


class BuildCoreRecipeTest(unittest.TestCase):
    """Offline checks that run with every Flutter test pass."""

    def test_recipe_sources_are_public_git_urls(self):
        urls = clone_urls(script_text())
        self.assertTrue(urls, "no build sources found")
        for url in urls:
            with self.subTest(url=url):
                self.assertTrue(url.startswith("https://github.com/"),
                                f"unexpected source host: {url}")
                self.assertTrue(url.endswith(".git"),
                                f"source is not a git repository: {url}")
                owner_repo = url[len("https://github.com/"):-len(".git")]
                self.assertEqual(len(owner_repo.split("/")), 2,
                                 f"unexpected repository path: {url}")

    def test_dead_nintendo_ds_source_is_absent(self):
        urls = clone_urls(script_text())
        self.assertFalse([url for url in urls if "melonDS-libretro" in url],
                         "the retired source repository is named in a recipe")

    def test_nintendo_ds_recipe_is_pinned(self):
        text = script_text()
        pin = re.search(r"^DUALSCREEN_SHA=([0-9a-f]{40})$", text, re.MULTILINE)
        self.assertIsNotNone(pin, "the dual-screen source has no commit pin")
        body = function_body(text, "build_dualscreen")
        self.assertIn("https://github.com/libretro/melonDS.git", body)
        self.assertIn('fetch --depth 1 origin "$DUALSCREEN_SHA"', body)
        self.assertIn(f'--detach "$DUALSCREEN_SHA"', body)

    def test_held_cores_have_no_source(self):
        text = script_text()
        held = sorted(p.name for p in (ROOT / "cores").glob("*_hold"))
        self.assertTrue(held, "no held cores found")
        for core_id in held:
            with self.subTest(core=core_id):
                body = function_body(text, f"build_{core_id}")
                self.assertIn("hold ", body)
                self.assertNotIn("clone ", body)
                self.assertNotIn("core_make ", body)
        urls = clone_urls(text)
        self.assertFalse([url for url in urls if "_hold" in url],
                         "a held core has a build source")


class BuildCoreRecipeResolutionTest(unittest.TestCase):
    """Resolves every recipe source against its upstream git service."""

    def test_every_recipe_source_resolves(self):
        urls = sorted(set(clone_urls(script_text())))
        self.assertTrue(urls, "no build sources found")
        for url in urls:
            with self.subTest(url=url):
                try:
                    proc = subprocess.run(
                        ["git", "ls-remote", "--exit-code", url, "HEAD"],
                        capture_output=True, text=True, timeout=30,
                    )
                except FileNotFoundError:
                    self.skipTest("git is not available")
                except subprocess.TimeoutExpired:
                    self.fail(f"source did not resolve in 30 seconds: {url}")
                self.assertEqual(proc.returncode, 0,
                                 f"{url}: {proc.stderr.strip()}")
                self.assertRegex(proc.stdout, r"^[0-9a-f]{40}\tHEAD$",
                                 f"{url}: no HEAD revision advertised")


if __name__ == "__main__":
    unittest.main(verbosity=2)

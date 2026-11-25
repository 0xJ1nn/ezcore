#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

"""Validate and drive pinned builds of the cores shipped with the app.

Recipes in ``cores/<id>/recipe.json`` record build facts; the catalog and
``toolchain.json`` remain the source of truth for product metadata and tool
versions. The driver never reimplements a compiler invocation: it checks the
recipe, checks out the pinned upstream commit, and calls ``build_core.sh``.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORES = ROOT / "cores"
RECIPES = CORES
LOCK = CORES / "lock.json"
CATALOG = CORES / "catalog.json"
TOOLCHAIN = ROOT / "toolchain.json"
BUILD_SCRIPT = ROOT / "scripts" / "build_core.sh"

PLATFORMS = ("macos", "ios", "android", "linux", "windows")
TARGETS = ("macos-arm64", "ios-arm64", "android-arm64", "linux-x64", "windows-x64")
DEFAULT_ARCH = {"macos": "arm64", "ios": "arm64", "android": "arm64-v8a",
                "linux": "x64", "windows": "x64"}
MAKE_PLATFORM = {"macos-arm64": "", "ios-arm64": "platform=ios-arm64",
                 "android-arm64": "platform=unix", "linux-x64": "platform=unix",
                 "windows-x64": "platform=windows"}
SUFFIX = {"macos-arm64": "dylib", "ios-arm64": "dylib", "android-arm64": "so",
          "linux-x64": "so", "windows-x64": "dll"}
SHA_RE = re.compile(r"^[0-9a-f]{40}$")


class CorebuildError(Exception):
    """Invalid data or a failed build step."""


class RecipeError(CorebuildError):
    """A recipe, lock entry or catalog entry is invalid."""


class PinError(CorebuildError):
    """A source tree is not at its pinned commit."""


class BuildError(CorebuildError):
    """A build step failed on this host."""


def load_json(path: Path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CorebuildError(f"cannot read {path}: {exc}") from exc


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8")


def canonical(data) -> bytes:
    return json.dumps(data, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True).encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def recipe_hash(recipe: dict) -> str:
    return sha256_bytes(canonical(recipe))


def cache_key(recipe: dict, toolchain: dict, target: str) -> str:
    pins = {k: v for k, v in toolchain.items() if k != "notes"}
    return sha256_bytes(canonical({"recipe": recipe_hash(recipe),
                                   "pin": recipe.get("pin"),
                                   "toolchain": pins, "target": target}))


def is_shippable(entry: dict) -> bool:
    """A catalog core that can ship: not held, gated, or delivery-absent."""
    if not isinstance(entry, dict):
        return False
    if entry.get("blocked_reason") or entry.get("gated_reason"):
        return False
    delivery = entry.get("delivery") or {}
    return any(v != "absent" for v in delivery.values())


def _safe_relative(value, allow_empty: bool = False) -> bool:
    if allow_empty and value == "":
        return True
    return (isinstance(value, str) and bool(value)
            and not Path(value).is_absolute() and ".." not in Path(value).parts)


def validate_coverage(recipes: dict, lock: dict, catalog: dict,
                      toolchain: dict) -> list[str]:
    """One recipe and one lock entry for each shippable core, and no others."""
    errors: list[str] = []
    shippable = {cid for cid, m in catalog.items() if is_shippable(m)}
    for cid in sorted(shippable - set(recipes)):
        errors.append(f"{cid}: shippable core has no recipe")
    for cid in sorted(set(recipes) - shippable):
        reason = "on legal hold" if catalog.get(cid, {}).get("blocked_reason") \
            else "gated from distribution"
        errors.append(f"{cid}: recipe for a core {reason}")
    locked = set(lock.get("cores") or {})
    for cid in sorted(shippable - locked):
        errors.append(f"{cid}: shippable core has no lock entry")
    for cid in sorted(locked - shippable):
        reason = "on legal hold" if catalog.get(cid, {}).get("blocked_reason") \
            else "gated from distribution"
        errors.append(f"{cid}: lock entry for a core {reason}")
    if lock.get("schema") != 1:
        errors.append("lock.json: schema must be 1")
    for cid, rec in sorted(recipes.items()):
        target = "linux-x64" if "linux-x64" in (rec.get("platforms") or []) else None
        errors += validate_recipe(rec, lock, catalog, toolchain, target)
    return errors


def run_cmd(cmd, **kwargs):
    """Subprocess with captured text; callers inspect the return code."""
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def checked(run, cmd, **kwargs):
    result = run(cmd, **kwargs)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()[:400]
        raise BuildError(f"{' '.join(str(c) for c in cmd)}: {detail}")
    return result


def verify_checkout_pin(src: Path, pin: str, run=run_cmd) -> None:
    result = run(["git", "rev-parse", "HEAD"], cwd=str(src),
                 capture_output=True, text=True)
    if result.returncode != 0:
        raise PinError(f"cannot read HEAD in {src}: {result.stderr.strip()[:200]}")
    head = result.stdout.strip()
    if head != pin:
        raise PinError(f"{src}: HEAD {head or '(none)'} is not pinned commit {pin}")


def fetch_source(url: str, src: Path, pin: str, run=run_cmd) -> None:
    """Clone only when needed, then fetch and check out the exact commit."""
    src = Path(src)
    src.parent.mkdir(parents=True, exist_ok=True)
    if not (src / ".git").exists():
        checked(run, ["git", "clone", "--no-checkout", url, str(src)])
    checked(run, ["git", "fetch", "origin", pin], cwd=str(src))
    checked(run, ["git", "checkout", "-q", "--detach", pin], cwd=str(src))
    verify_checkout_pin(src, pin, run)


def target_key(platform: str, arch: str | None = None) -> str:
    want = DEFAULT_ARCH[platform]
    arch = arch or want
    if arch != want:
        raise CorebuildError(f"{platform}: only {want} is supported, got {arch!r}")
    return {"macos": "macos-arm64", "ios": "ios-arm64",
            "android": "android-arm64", "linux": "linux-x64",
            "windows": "windows-x64"}[platform]


def build_command(cid: str, platform: str, app_root: Path = ROOT) -> list[str]:
    """The only build entry point: the existing per-core shell build script."""
    return ["bash", str(Path(app_root) / "scripts" / "build_core.sh"), cid]


def build_env(platform: str, arch: str, out_dir: Path,
              jobs: int = 0) -> dict[str, str]:
    env = os.environ.copy()
    env.update({"EZCORE_PLATFORM": platform, "EZCORE_ARCH": arch,
                "EZCORE_OUT_DIR": str(out_dir)})
    if jobs > 0:
        env["JOBS_OVERRIDE"] = str(jobs)
    return env


def catalog_entry(recipe: dict, catalog: dict, target: str,
                  artifact_sha: str | None = None) -> dict:
    """Product metadata comes from the catalog; only source facts come here."""
    entry = copy.deepcopy(catalog[recipe["id"]])
    if artifact_sha:
        entry.setdefault("artifacts", {})[target] = artifact_sha
    entry["source"] = {
        "upstream": recipe["upstream"], "commit": recipe["pin"],
        "patches": [p["path"] for p in recipe.get("patches") or []],
        "recipe_sha256": recipe_hash(recipe),
    }
    return entry


def validate_catalog_entry(candidate: dict, actual: dict, recipe: dict | None = None,
                           lock: dict | None = None) -> list[str]:
    errors = []
    keys = ("id", "name", "version", "license", "license_url", "homepage",
            "upstream", "systems", "extensions", "bios_required", "bios_files",
            "blocked_reason")
    for key in keys:
        if key in actual and candidate.get(key) != actual.get(key):
            errors.append(f"catalog {key}: {candidate.get(key)!r} != {actual.get(key)!r}")
    for surface in ("delivery", "execution"):
        for platform in PLATFORMS:
            want = (actual.get(surface) or {}).get(platform)
            got = (candidate.get(surface) or {}).get(platform)
            if want != got:
                errors.append(f"catalog {surface}.{platform}: {got!r} != {want!r}")
    source = candidate.get("source")
    if source is not None:
        expected = None
        if recipe:
            expected = recipe.get("pin")
        elif isinstance(actual.get("source"), dict):
            expected = actual["source"].get("commit")
        elif lock:
            expected = (lock.get("cores") or {}).get(candidate.get("id"))
        if expected and source.get("commit") != expected:
            errors.append(f"catalog source.commit must be {expected}, "
                          f"got {source.get('commit')!r}")
        if source.get("upstream") and recipe and source["upstream"] != recipe["upstream"]:
            errors.append("catalog source.upstream disagrees with the recipe")
    return errors


def source_text(recipe: dict, toolchain: dict) -> str:
    lines = [f"core: {recipe['id']}",
             f"upstream: {recipe['upstream']}",
             f"commit: {recipe['pin']}"]
    patches = [p["path"] for p in recipe.get("patches") or []]
    lines.append("patches: " + (", ".join(patches) if patches else "none"))
    lines.append("toolchain: " + ", ".join(
        f"{k}={v}" for k, v in sorted(toolchain.items()) if k != "notes"))
    return "\n".join(lines) + "\n"


def package(recipe: dict, catalog: dict, target: str, built: Path,
            out_dir: Path, *, license_file: Path,
            toolchain: dict | None = None) -> dict:
    """Write one archive and update the per-platform index; no build here."""
    cid = recipe["id"]
    platform = target.split("-")[0]
    version = re.sub(r"[^A-Za-z0-9._+-]", "_", str(catalog[cid]["version"]))
    folder = Path(out_dir) / platform
    folder.mkdir(parents=True, exist_ok=True)
    zip_path = folder / f"{cid}-{version}-{platform}.zip"
    name = Path(recipe["outputs"][target]).name
    payload = {
        name: Path(built).read_bytes(),
        "manifest.json": (json.dumps(catalog_entry(recipe, catalog, target),
                                     indent=2, sort_keys=True) + "\n").encode(),
        "LICENSE.txt": Path(license_file).read_bytes(),
        "SOURCE.txt": source_text(recipe, toolchain or {}).encode(),
    }
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for filename in sorted(payload):
            info = zipfile.ZipInfo(filename, date_time=(1980, 1, 1, 0, 0, 0))
            info.external_attr = 0o644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, payload[filename])
    index_path = folder / "index.json"
    index = load_json(index_path) if index_path.is_file() else {}
    record = {
        "id": cid, "version": catalog[cid]["version"], "target": target,
        "file": zip_path.name, "size": len(payload[name]),
        "sha256": sha256_bytes(zip_path.read_bytes()),
        "library_sha256": sha256_bytes(payload[name]),
        "source_commit": recipe["pin"], "recipe_sha256": recipe_hash(recipe),
    }
    index[cid] = record
    write_json(index_path, index)
    return record


def build_one(recipe: dict, lock: dict, catalog: dict, toolchain: dict,
              target: str, *, app_root: Path, src_root: Path, out_dir: Path,
              cache_dir: Path | None = None, jobs: int = 0, run=run_cmd) -> dict:
    """Pin the source, call build_core.sh, verify the pin again, package."""
    problems = validate_recipe(recipe, lock, catalog, toolchain, target)
    if problems:
        raise RecipeError("; ".join(problems))
    key = cache_key(recipe, toolchain, target)
    cache = Path(cache_dir) if cache_dir else Path(
        os.environ.get("EZCORE_COREBUILD_CACHE",
                       str(Path.home() / ".cache" / "ezcore-corebuild")))
    cache_file = cache / f"{recipe['id']}-{target}-{key[:16]}.json"
    if cache_file.is_file():
        cached = load_json(cache_file)
        if Path(cached.get("file", "")).is_file():
            return cached
    src = Path(src_root) / recipe["source_dir"]
    fetch_source(recipe["upstream"], src, recipe["pin"], run=run)
    platform, arch = target.split("-")[0], args_arch(target)
    checked(run, build_command(recipe["id"], platform, app_root),
            env=build_env(platform, arch, out_dir, jobs), cwd=str(app_root))
    verify_checkout_pin(src, recipe["pin"], run)
    suffix = SUFFIX[target]
    staged = Path(out_dir) / recipe["id"] / f"{recipe['id']}_libretro.{suffix}"
    license_path = next((src / name for name in recipe["license_files"]
                         if (src / name).is_file()), None)
    if license_path is None:
        raise BuildError(f"{recipe['id']}: no upstream licence file found")
    record = package(recipe, catalog, target, staged, out_dir,
                     license_file=license_path, toolchain=toolchain)
    record["file"] = str(Path(out_dir) / platform / record["file"])
    write_json(cache_file, record)
    return record


def args_arch(target: str) -> str:
    return DEFAULT_ARCH[target.split("-")[0]]


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--platform", choices=PLATFORMS,
                        help="host platform: macos, ios, android, linux or windows")
    parser.add_argument("--arch", help="target architecture (only the default is supported)")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--core", help="build exactly one core id")
    group.add_argument("--all", action="store_true",
                       help="build every core with a published artifact for this target")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the plan; never clone, compile or write")
    parser.add_argument("--validate-recipes", action="store_true",
                        help="check recipes against the catalog, lock and toolchain")
    parser.add_argument("--validate-catalog", action="store_true",
                        help="check emitted catalog entries against the catalog")
    parser.add_argument("--emit-catalog", type=Path, metavar="FILE",
                        help="write one candidate catalog entry and stop")
    parser.add_argument("--out", type=Path, default=ROOT / "dist" / "cores")
    parser.add_argument("--recipes", type=Path, default=RECIPES)
    parser.add_argument("--lock", type=Path, default=LOCK)
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    parser.add_argument("--toolchain", type=Path, default=TOOLCHAIN)
    parser.add_argument("--jobs", type=int, default=0,
                        help="override the staged library's parallelism")
    args = parser.parse_args(argv)
    if not args.platform and not args.validate_recipes:
        parser.error("--platform is required unless --validate-recipes is given")
    args.target = None
    if args.platform:
        try:
            args.arch = args.arch or DEFAULT_ARCH[args.platform]
            args.target = target_key(args.platform, args.arch)
        except CorebuildError as exc:
            parser.error(str(exc))
    return args


def main(argv=None) -> int:
    args = parse_args(argv)
    try:
        recipes = load_recipes(args.recipes)
        catalog = load_json(args.catalog)
        lock = load_json(args.lock)
        toolchain = load_json(args.toolchain)
    except CorebuildError as exc:
        print(f"corebuild: {exc}")
        return 1

    errors = validate_coverage(recipes, lock, catalog, toolchain)
    if errors:
        print("corebuild: FAIL - recipe coverage")
        for error in errors:
            print(f"  {error}")
        return 1
    if args.validate_recipes:
        print(f"corebuild: PASS ({len(recipes)} recipes, "
              f"{len(lock['cores'])} pins, {len(catalog)} catalog entries)")
        return 0

    if args.validate_catalog:
        failures = []
        for cid, rec in sorted(recipes.items()):
            if args.target not in rec.get("platforms", []):
                continue
            entry = catalog_entry(rec, catalog, args.target)
            failures += [f"{cid}: {e}" for e in
                         validate_catalog_entry(entry, catalog[cid], rec, lock)]
        if failures:
            print("corebuild: FAIL - catalog")
            for failure in failures:
                print(f"  {failure}")
            return 1
        print(f"corebuild: catalog PASS ({args.target}, {len(recipes)} entries)")
        return 0

    if args.emit_catalog:
        if not args.core:
            print("corebuild: --emit-catalog needs --core")
            return 2
        rec = recipes.get(args.core)
        if not rec:
            print(f"corebuild: unknown core {args.core}")
            return 2
        if args.target not in rec.get("platforms", []):
            print(f"corebuild: REFUSED {args.core} has no {args.target} build")
            return 2
        entry = catalog_entry(rec, catalog, args.target)
        failures = validate_catalog_entry(entry, catalog[args.core], rec, lock)
        if failures:
            for failure in failures:
                print(f"  {failure}")
            return 1
        write_json(args.emit_catalog, entry)
        print(f"corebuild: wrote candidate catalog entry {args.emit_catalog}")
        return 0

    if not args.core and not args.all:
        print("corebuild: choose --core <id> or --all")
        return 2
    ids = [args.core] if args.core else [
        cid for cid, rec in sorted(recipes.items())
        if args.target in rec.get("pinned_targets", rec.get("platforms", []))]
    for cid in ids:
        if catalog.get(cid, {}).get("blocked_reason"):
            print(f"corebuild: REFUSED {cid} is on legal hold")
            return 2
        rec = recipes.get(cid)
        if not rec:
            print(f"corebuild: unknown core {cid}")
            return 2
        if args.target not in rec.get("platforms", []):
            print(f"corebuild: REFUSED {cid} has no {args.target} build")
            return 2
        problems = validate_recipe(rec, lock, catalog, toolchain, args.target)
        if problems:
            for problem in problems:
                print(f"corebuild: {cid}: {problem}")
            return 1
        if not rec.get("pin_verified", False):
            print(f"corebuild: WARNING {cid}: pin {rec['pin'][:12]} "
                  "has no verified artifact")
        version = re.sub(r"[^A-Za-z0-9._+-]", "_", str(catalog[cid]["version"]))
        archive = f"{cid}-{version}-{args.platform}.zip"
        if args.dry_run:
            print(f"corebuild: dry-run {cid} {args.target}: "
                  f"checkout {rec['upstream']} @ {rec['pin']} -> "
                  f"build_core.sh -> {Path(args.out) / args.platform / archive} "
                  f"[cache {cache_key(rec, toolchain, args.target)[:12]}]")
            continue
        try:
            entry = build_one(rec, lock, catalog, toolchain, args.target,
                              app_root=ROOT, src_root=ROOT / "native" / "src",
                              out_dir=args.out, jobs=args.jobs)
        except CorebuildError as exc:
            print(f"corebuild: {cid}: {exc}")
            return 1
        print(f"corebuild: {cid} {args.target} -> {entry['file']} "
              f"sha256={entry['sha256'][:16]}")
    verb = "dry-run" if args.dry_run else "built"
    print(f"corebuild: {verb} {len(ids)} core(s) for {args.target}")
    return 0


def load_recipes(directory: Path) -> dict[str, dict]:
    recipes: dict[str, dict] = {}
    if not Path(directory).is_dir():
        raise RecipeError(f"recipe directory not found: {directory}")
    for path in sorted(Path(directory).glob("*/recipe.json")):
        rec = load_json(path)
        if rec.get("schema") != 1 or not isinstance(rec.get("id"), str):
            raise RecipeError(f"{path}: expected schema 1 with an id")
        if rec["id"] != path.parent.name:
            raise RecipeError(f"{path}: id {rec['id']!r} does not match its folder")
        recipes[rec["id"]] = rec
    return recipes


def validate_recipe(recipe: dict, lock: dict, catalog: dict, toolchain: dict,
                    target: str | None = None) -> list[str]:
    """Return every reason this recipe must not be built, changing nothing."""
    errors: list[str] = []
    cid = recipe.get("id", "?")
    if recipe.get("schema") != 1:
        errors.append(f"{cid}: schema must be 1")
    if not isinstance(cid, str) or not cid:
        errors.append("recipe has no id")
        return errors
    entry = catalog.get(cid)
    if not isinstance(entry, dict):
        return errors + [f"{cid}: not in catalog.json"]
    if entry.get("blocked_reason"):
        return errors + [f"{cid}: on legal hold, never shippable"]
    if not is_shippable(entry):
        errors.append(f"{cid}: not a shippable catalog core")

    pin = recipe.get("pin")
    if not isinstance(pin, str) or not SHA_RE.fullmatch(pin):
        errors.append(f"{cid}: pin must be 40 lowercase hex characters")
    locked = (lock.get("cores") or {}).get(cid)
    if locked is None:
        errors.append(f"{cid}: no lock.json entry")
    elif locked != pin:
        errors.append(f"{cid}: recipe pin {pin} disagrees with lock.json {locked}")

    upstream = recipe.get("upstream", "")
    if not isinstance(upstream, str) or not upstream.startswith("https://"):
        errors.append(f"{cid}: upstream must be an https:// URL")
    if not _safe_relative(recipe.get("source_dir")):
        errors.append(f"{cid}: unsafe source_dir")
    if recipe.get("submodules") not in (False, True, "recursive"):
        errors.append(f"{cid}: submodules must be false, true or 'recursive'")

    build = recipe.get("build") or {}
    if build.get("system") not in ("make", "cmake"):
        errors.append(f"{cid}: build.system must be make or cmake")
    if not _safe_relative(build.get("dir", ""), allow_empty=True):
        errors.append(f"{cid}: unsafe build.dir")
    if not isinstance(build.get("jobs", 0), int) or build.get("jobs", 0) < 1:
        errors.append(f"{cid}: build.jobs must be a positive integer")
    args = build.get("args") or {}
    if not isinstance(args, dict) or not all(
            isinstance(v, list) and all(isinstance(x, str) for x in v)
            for v in args.values()):
        errors.append(f"{cid}: build.args values must be lists of strings")

    outputs, strip = recipe.get("outputs") or {}, recipe.get("strip") or {}
    if not isinstance(outputs, dict) or not outputs:
        errors.append(f"{cid}: no outputs declared")
    else:
        for key, name in outputs.items():
            if key not in TARGETS:
                errors.append(f"{cid}: unknown output target {key!r}")
            elif not isinstance(name, str) or not name.endswith("." + SUFFIX[key]):
                errors.append(f"{cid}: {key}: output {name!r} must end .{SUFFIX[key]}")
            if key not in strip:
                errors.append(f"{cid}: {key}: no strip rule")
    platforms = recipe.get("platforms")
    if (not isinstance(platforms, list) or not platforms
            or any(p not in TARGETS for p in platforms)):
        errors.append(f"{cid}: platforms must be a non-empty list of targets")
    elif target and target not in platforms:
        errors.append(f"{cid}: {target} is not a declared build target")
    pinned = recipe.get("pinned_targets")
    if pinned is not None and (not isinstance(pinned, list)
                               or any(p not in platforms for p in pinned)):
        errors.append(f"{cid}: pinned_targets must be a subset of platforms")

    patches = recipe.get("patches") or []
    if not isinstance(patches, list) or not all(
            isinstance(p, dict) and p.get("repo") is not None
            and _safe_relative(p.get("path")) for p in patches):
        errors.append(f"{cid}: patches need repo and safe relative paths")
    if not isinstance(recipe.get("license_files"), list) or not recipe["license_files"]:
        errors.append(f"{cid}: no license_files declared")

    if build.get("system") == "cmake" and not toolchain.get("cmake"):
        errors.append(f"{cid}: cmake recipe but toolchain.json has no cmake pin")
    if target and target.startswith("android-") and not toolchain.get("ndk"):
        errors.append(f"{cid}: android target but toolchain.json has no ndk pin")
    if target and target.startswith("ios-") and not toolchain.get("ios_deployment_target"):
        errors.append(f"{cid}: ios target but no ios_deployment_target pin")
    if target and target.startswith("windows-") and not toolchain.get("mingw"):
        errors.append(f"{cid}: windows target but toolchain.json has no mingw pin")
    return errors


if __name__ == "__main__":
    raise SystemExit(main())

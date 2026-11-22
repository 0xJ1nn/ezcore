# Core Authoring Guide

From clone to a catalog-verified, pinned core in ezCORE. A core that compiles
is not a core that plays — every step below is tied to a gate that `CI` runs.

> **Scope.** This guide covers one path: adding or rebuilding a libretro core
> package in this repository and getting it shippable. To build a core of your
> own and install it from a folder, see [`CUSTOM-CORES.md`](CUSTOM-CORES.md).
> It assumes the app shell builds (see `docs/BUILDING.md` for the full
> bootstrap). Cores implement the libretro `API` v1
> (see the [libretro core reference][libretro-api]); ezCORE does not extend it.
> The host-side `ABI` lives in `runtime/include/ezcore_runtime.h` and belongs to
> the application, not to cores.

[libretro-api]: https://docs.libretro.com/development/guidelines/core/

## 1. Build

### 1.1 Prerequisites

Install per-platform toolchains (see `docs/BUILDING.md` for full instructions):

| Platform | Essentials |
|---|---|
| macOS | Xcode version in `toolchain.json`, Homebrew, then `scripts/prereqs.sh` |
| Linux | `cmake ninja-build pkg-config libpng-dev libgtk-3-dev clang git curl unzip` + Flutter |
| Windows | MSYS2 (UCRT64) + Flutter |
| Android | Android Studio / command-line tools + the NDK in `toolchain.json` (`ANDROID_NDK_HOME`) |
| iOS | macOS + Xcode version in `toolchain.json` + CocoaPods |

### 1.2 Fetch headers (once)

Libretro cores compile against `libretro.h`. Vendor it before building the
runtime:

```bash
scripts/build_core.sh --fetch-headers
```

This clones `libretro-common` shallow and confirms
`runtime/external/libretro-common/include/libretro.h` exists.
`build_runtime.sh` refuses to run without it.

**Verified:** `scripts/build_core.sh` `fetch_headers()` and the `--fetch-headers`
case arm.

### 1.3 Set the platform

`build_core.sh` defaults to macOS arm64:

```bash
PLATFORM="${EZCORE_PLATFORM:-macos}"   # core_platform.sh, PLATFORM
```

Linux (and Windows, Android, iOS) builds **must** set `EZCORE_PLATFORM`:

```bash
EZCORE_PLATFORM=linux scripts/build_core.sh --tier-desktop
```

Platform variables resolved by `scripts/core_platform.sh` (sourced by
`build_core.sh`):

| `EZCORE_PLATFORM` | lib suffix | make platform | artifact key | staging dir |
|---|---|---|---|---|
| `macos` (default) | `.dylib` | (empty) | `macos-arm64` | `native/cores` |
| `linux` | `.so` | `platform=unix` | `linux-x64` | `native/cores-linux-x64` |
| `windows` | `.dll` | `platform=windows` | `windows-x64` | `native/cores-windows-x64` |
| `android` | `.so` | `platform=unix` | `android-arm64` | `native/cores-android-arm64-v8a` |
| `ios` | `.dylib` | `platform=ios-arm64` | `ios-arm64` | `native/cores-ios-arm64` |

Override env vars (documented in the header comments of `core_platform.sh` and
`build_core.sh`):

| Var | Default | Effect |
|---|---|---|
| `EZCORE_PLATFORM` | `macos` | Selects platform layer |
| `EZCORE_ARCH` | per platform | Overrides architecture |
| `EZCORE_OUT_DIR` | per platform table | Overrides staging root |
| `JOBS_OVERRIDE` | CPU count | Parallel make jobs |
| `EZCORE_NO_RESET` | `0` | Skip `core_reset` (iteration only; never for pins) |

Android requires `ANDROID_NDK_HOME` (enforced by `android_toolchain()` in
`core_platform.sh`); iOS requires `xcrun` / the iOS SDK (`ios_toolchain()` in
`core_platform.sh`).

### 1.4 Build a single core

```bash
scripts/build_core.sh nesbyte
```

This dispatches to `build_nesbyte()` (the `*` case maps `<id>` to
`build_<id>()`). The recipe clones upstream, runs `core_make` (flock-serialized
per source tree), and calls `stage()`.

`stage()` creates:

```
native/cores/<id>/<id>_libretro.<ext>   # stripped, macOS ad-hoc signed
native/cores/<id>/SHA256SUMS             # sha256 of the staged bytes
```

Strip policy preserves `dlopen` symbols — debug info is removed but dynamic
symbols are kept (`-x` on macOS, `-g` on Linux, `llvm-strip -g` on Android).
macOS ad-hoc signs at stage time; **pins describe the signed bytes, not
pre-sign bytes. Never re-sign a pinned artifact** (the signing comment in
`stage()`).

### 1.5 Build a tier

Pre-defined tiers match the platform matrix in `build_core.sh`:

| Flag | Cores (count) | Platforms |
|---|---|---|
| `--tier1` | pocketbit, advancebit, superfx, blastproc, realmode (5) | macOS (run-verified) |
| `--tier-desktop` | 17 cores | macOS, Linux, Windows |
| `--tier-android` | 10 cores | Android |
| `--tier-ios` | 9 cores | iOS (interpreter-only) |

**Verified:** `build_core.sh` `TIER1`, `TIER_ANDROID`, `TIER_IOS`,
`TIER_DESKTOP`, and the `case "$cmd"` dispatch.

`core_reset()` cleans stale objects on platform switches. A `.ezcore-build-ok`
marker records the last successful platform; a mismatch triggers
`git reset --hard` + `git clean -fdx`. Same-platform rebuilds stay incremental.
Set `EZCORE_NO_RESET=1` for single-core iteration only — never for pins or
releases (the `EZCORE_NO_RESET` guard in `core_reset()`).

Hold cores (`citra_hold`, `switch_hold`) refuse to build via
`hold()` which exits 4.

## 2. Package

### 2.1 Manifest schema

The reference shape is `cores/nesbyte/manifest.json`. The complete set of
recognized top-level fields is defined by `kKnownManifestFields` in
`lib/services/core_package_validator.dart`:

| Field | Type | Enforcer |
|---|---|---|
| `id` | string | validator: `[a-z0-9_]+`, must match dir; catalog: must match dir |
| `name` | string | catalog: required |
| `version` | string | catalog: required |
| `license` | string | catalog: required |
| `license_url` | string | — |
| `homepage` | string | — |
| `upstream` | string | — |
| `systems` | string[] | catalog: required |
| `extensions` | string[] | — |
| `cheats_supported` | bool | managed by `fill_manifest_data.py` |
| `cheat_families` | string[] | managed by `fill_manifest_data.py` |
| `bios_required` | bool | validator: warning if true without `bios_files` |
| `bios_files` | string[] | — |
| `bios_notes` | string | — |
| `delivery` | object | validator + `fill_manifest_data.py` |
| `artifacts` | object | validator: every value is `^[0-9a-f]{64}$` |
| `execution` | object | managed by `fill_manifest_data.py` |
| `provenance` | object | — |

Field structure in practice (verified: `cores/nesbyte/manifest.json`):

```json
{
  "delivery":   { "macos": "bundled", "linux": "bundled", "ios": "bundled" },
  "artifacts":  { "macos-arm64": "<64-char-hex>", "linux-x64": "<64-char-hex>" },
  "execution":  { "macos": "interpreter", "linux": "dynarec", "ios": "interpreter" },
  "provenance": { "built_from": "...", "upstream_license": "...", "relationship": "..." }
}
```

### 2.2 Validator rules

`lib/services/core_package_validator.dart` enforces (all verified against source):

- **id**: must match `^[a-z0-9_]+$` (`_idRegex`) and match the package directory
  name (both in `_validateManifest()`).
- **artifacts**: every pin must be a 64-char lowercase hex string matching
  `^[0-9a-f]{64}$` (`_pinRegex`, checked in `_validateManifest()`).
- **delivery**: each per-OS value must be one of `bundled`, `download`,
  `absent` (`_allowedDelivery`, checked in `_validateManifest()`) — the same vocabulary the app's manifest
  model and every real manifest use.
- **bios_required**: `true` without `bios_files` → non-fatal warning
  (`_validateManifest()`).
- **Unknown fields**: any top-level key not in `kKnownManifestFields` → error
  (`_validateManifest()`). Callers may extend via the `allowedFields` parameter
  of `validate()`.
- **Package size**: total bytes ≤ 512 MiB by default (`defaultMaxPackageBytes`,
  enforced in `_scanPackage()`); oversize → error there.
- **Manifest size**: `manifest.json` ≤ 1 MiB (`defaultMaxManifestBytes`,
  enforced in `validate()`); over cap → error there.
- **Symlinks**: any `Link` in the package tree → error (`_scanPackage()`).

Validation never throws for policy failures — problems are collected in
`errors` (hard fails; `ok == false`) and `warnings` (soft) on the returned
`PackageValidationReport`.

> ⚠️ **Delivery vocabulary.** The Dart validator accepts `bundled | download |
> absent` (`_allowedDelivery`) and rejects `on-demand` by design. The app's
> manifest model, `fill_manifest_data.py` `_delivery()`, every real manifest, and
> `build_catalog.py` `build_release()` all use `download`.
>
> ⚠️ **Extra manifest fields.** Real manifests carry `blocked_reason` (holds:
> citra_hold, switch_hold), `gated_reason` (license-gated: coinbox, superfx,
> blastproc, gambatte), `notes` (ten cores), `default_options` (rcp64), and
> `system_data` (portcomp, powercube). All are in `kKnownManifestFields`, so the
> validator accepts every manifest in this repository.

### 2.3 What a core must implement

The libretro `API` v1 — `retro_*` entry points, `RETRO_API_VERSION == 1`. A core
does not implement or call the `ezcore_*` host `API` in
`runtime/include/ezcore_runtime.h` (that is the application's surface). Using
the existing libretro contract is what makes a core usable by ezCORE,
RetroArch, and others. See `CONTRIBUTING.md`, "What a core must implement".

Save states are optional and either state is legitimate. A core that exports
`retro_serialize`, `retro_unserialize` and a nonzero `retro_serialize_size`
gets snapshots with no extra integration. A core that reports 0 from
`retro_serialize_size` is not broken: the session runs, the pause menu says
"No saves", and autosave and the restart/quit prompts stop promising a
snapshot. Record such a core's boot evidence without the state round trip (see
the note in `docs/MATRIX.md`) rather than treating it as a failure.

## 3. Declare

### 3.1 Policy maps: fill_manifest_data.py

`scripts/fill_manifest_data.py` is the single-writer for three policy
dimensions across `cores/*/manifest.json`. Add new cores to its maps, then run:

```bash
python3 scripts/fill_manifest_data.py          # write policy fields
python3 scripts/fill_manifest_data.py --check  # CI: fail on drift
```

**Verified:** the `fill_manifest_data.py` module docstring and `main()`.

| Dimension | Map | Values |
|---|---|---|
| `execution` | `EXECUTION` | `interpreter` \| `dynarec` per OS |
| `cheats_supported` / `cheat_families` | `CHEATS` | bool / string[] per core |
| `delivery` | `_delivery()` | per-OS: `bundled` \| `download` \| `absent` |

iOS interpreter enforcement: JIT-capable cores (dynarec) must not appear in the
iOS tier unless the recipe passes an explicit flag. `core_platform.sh`'s
`require_interpreter_ios()` refuses iOS builds without it. Several build
functions call it before `core_make` (e.g. `build_advancebit()`,
`build_dreamarc()`, `build_powercube()`).

### 3.2 Delivery vocabulary for distribution

Three values ship (the delivery comment in `fill_manifest_data.py`):

| Value | Meaning | ADR |
|---|---|---|
| `bundled` | Artifact ships inside the app bundle (desktop/Android) or as embedded frameworks (iOS) | — |
| `download` | Fetched on-demand from GitHub Releases; sha256-verified against the manifest pin before staging | hybrid core delivery |
| `absent` | Not distributed by ezCORE | — |

Cores in `_DOWNLOAD_DESKTOP` — the giants pointclick (~170 MB), dreamarc
(~39 MB) and powercube (~27 MB on linux-x64), plus potator and gw — ship as
`download` on macOS/Windows/Linux to keep the base package lightweight
(`_delivery()`). Android bundles its tier cores, pointclick included (no
download assets are published yet). iOS is never `download` — `build_catalog.py`
`main()` hard-fails if any iOS delivery is `download`.

`release.sh` ships only `bundled` cores into the app bundle (`bundled_ids()` and
`stage_bundled()`); `download` cores are fetched at first use by the Core Manager
and verified against the pin before staging.

The iOS rule is enforced in three places (belt-and-suspenders):
1. `build_core.sh` `TIER_IOS` includes only interpreter-safe cores
2. `fill_manifest_data.py` `_delivery()` never sets iOS to `download`
3. `build_catalog.py` `main()` rejects any manifest with `delivery.ios: download`

Only a core listed in `cores/published-sha256.txt` and pinned to the same
digest is offered as a download. Everything else in the `download` set is
reported on that platform as "not published yet", with the one route that
works today: install a core from a file.

### 3.3 Hold and gated cores

| Status | Manifest field | build_core.sh | Distribution |
|---|---|---|---|
| Hold (never built) | `blocked_reason` | `hold()` → exit 4 | Recipe retained as architecture slot only |
| Gated (license) | `gated_reason` | Builds; delivery=`absent` everywhere | Not shipped in any binary |
| Recipe-only | — | Built locally, not pinned | User-built only |

Hold cores (citra_hold, switch_hold) declare `blocked_reason`
explaining the IP/legal block. `pin_artifacts.py` `main()` refuses to pin any
core with `blocked_reason`.

Recipe-only cores (coinbox, superfx, blastproc — non-commercial upstream
licenses; gambatte — GPL-2.0-only incompatible with the GPL-3.0-only app
shell) have `delivery: absent` on every OS. They build but never ship
(`_delivery()` in `fill_manifest_data.py`).

> **License gate.** A GPL-2.0-only core cannot be `dlopen`'d into the
> GPL-3.0-only app bundle — a bundled plugin counts as a combined work. This is
> why gambatte is gated despite being functional (see gambatte's manifest
> `gated_reason`).

### 3.4 Catalog merge: build_catalog.py

`scripts/build_catalog.py` reads every `cores/*/manifest.json` and writes two
Flutter assets:

```
cores/catalog.json   # merged index (sorted ids, sort_keys) — loaded at startup
cores/release.json   # on-demand download map: repo, tag, asset filenames
```

It also reads `cores/published-sha256.txt`, which is the release's own
`SHA256SUMS.txt` with its tag on a `# vX.Y.Z` line. The map is built from
that file, so an asset the host does not serve is never offered and a pin
that disagrees with the served bytes fails the build instead of producing a
download that verifies and is then discarded on every device. Refresh the
file by copying the `SHA256SUMS.txt` attached to the release the build
downloads from.

**Verified:** the `build_catalog.py` module docstring and `build_release()`.

It enforces in `main()`:

- `REQUIRED = ("id", "name", "version", "license", "systems", "delivery")` —
  all must be present.
- id must match directory name, unless suffix is `_hold`.
- No duplicate ids.
- `delivery.ios` must never be `download`.
- Blocked cores (`blocked_reason`) must not carry artifacts.

Run after any manifest change — fresh checkouts regenerate the catalog from
manifests:

```bash
python3 scripts/build_catalog.py
```

## 4. Verify

The checks below run in `CI`. `scripts/release.sh` runs the data, native and
pin gates; `.githooks/pre-commit` runs the policy, license and banned-content
gates.

### 4.1 Pin check: pin_artifacts.py --check

```bash
python3 scripts/pin_artifacts.py macos-arm64 --out native/cores --check
```

For macOS, `--out` must be `native/cores` — the staging dir has no platform
suffix, but the script's default is `native/cores-{plat}`. For other platforms
the default matches the staging dir (the `OUT_DIR` default in
`core_platform.sh` and the `--out` default in `pin_artifacts.py` `main()`).

`--check` verifies staged bytes against committed pins — **both directions**
(the `--check` branch of `pin_artifacts.py` `main()`):

1. Every staged artifact's SHA-256 must match the pin in
   `manifest.json` `artifacts.<plat>`.
2. Every pinned manifest must have a staged artifact.
3. Every `delivery: bundled` core must be staged.

The SHA256SUMS sidecar is **regenerated from real bytes on every write** and
never trusted — a stale sidecar once hid signed cores whose bytes no longer
matched their pins (see the `pin_artifacts.py` module docstring and `main()`).

Write mode (after a successful build):

```bash
python3 scripts/pin_artifacts.py macos-arm64 --out native/cores
```

Pins the staged bytes into `manifest.json`, refreshes SHA256SUMS, and
regenerates `catalog.json` via `build_catalog.py` (`pin_artifacts.py` `main()`
write mode).

**Waivers:** cores listed in `native/pin-waivers/<plat>.txt` are exempted from
check #3 (e.g., a missing toolchain dep on a build host). Waiver files are
plain text, one id per line, `#` comments allowed (the waiver file read in
`pin_artifacts.py` `main()`).

### 4.2 Pre-commit gate

Install once per clone:

```bash
scripts/install-hooks.sh
```

This sets `git config core.hooksPath .githooks` (`install-hooks.sh`). Every
`git commit` then runs `.githooks/pre-commit`:

| Gate | File | What it checks |
|---|---|---|
| §79 scratch tooling | `.githooks/pre-commit` `scratch_hits` gate | rejects `_probe.*`, `screenshot_*`, `inject_*`, `capture_*`, `xdotool`, `ydotool`, `wtype` in staged files |
| Banned content | `scripts/banned_content_scan.sh` | ROM/BIOS/key extensions + exact filename match; `test/fixtures/` allowlist |
| License/delivery | `scripts/license_audit.py` | license compliance, delivery map consistency |
| Manifest policy | `scripts/fill_manifest_data.py --check` | execution/cheats/delivery drift (same gate `release.sh` runs) |

All gates are read-only — no git rewrites in the hook body. **Verified:**
`.githooks/pre-commit`.

### 4.3 ctest (runtime)

```bash
scripts/build_runtime.sh macos      # or: linux windows android ios
```

Builds the C runtime + synthetic test core via CMake/Ninja, then runs CTest on
macOS/Linux hosts:

```bash
(cd runtime/build-macos && ctest --output-on-failure)
```

Verified: the `build_runtime.sh` CMake build and ctest `case`. Requires
`--fetch-headers` first (the vendored-header check).
iOS/Android cross builds produce a library but skip host-side ctest (`CI` runners
handle those legs; the ctest `case` in `build_runtime.sh`).

### 4.4 Core matrix (Dart FFI)

```bash
flutter test test/core_matrix_test.dart
```

A Dart-driven, fork-isolated harness that `dlopen`s each staged core and
verifies it at least **IDENTIFIES** to the libretro `ABI` — a core that compiles
but fails `dlopen` or `ident` is a fail. Staged `.dylib`/`.so`/`.dll` files in
`native/cores/` are required.

Verified: `docs/CORE_SYSTEM.md`, "Adding a core (contributors)";
`docs/BUILDING.md`, "Verification Gates (`CI` Equivalent)"; `docs/MATRIX.md`.

> `test/core_matrix_test.dart` exists (2 tests) and is tracked on main; the
> docs' reference to it is correct.

### 4.5 API-doc gate

```bash
python3 scripts/check_api_docs.py
```

Verifies `docs/API.md` documents every function/macro in
`runtime/include/ezcore_runtime.h` — both directions (header→doc and
doc→header). Wired into the ctest suite.

Verified: the `check_api_docs.py` `check()` function and its module docstring.

### 4.6 Dart gates

```bash
flutter analyze lib/ test/
flutter test
```

Verified: `docs/BUILDING.md`, "Verification Gates (`CI` Equivalent)".

## 5. Submit

### 5.1 Commit

```bash
git commit -s    # DCO sign-off
```

DCO sign-off required (`CONTRIBUTING.md`, "Licensing of contributions"). The
pre-commit gate runs automatically — resolve all failures before opening a PR.

### 5.2 Pull request

A core PR must include (`docs/CORE_SYSTEM.md`, "Adding a core (contributors)";
`docs/BUILDING.md`, "Adding a New Core"):

1. **Manifest** — `cores/<id>/manifest.json` with valid id, pins, delivery,
   execution, provenance.
2. **Build recipe** — `build_<id>()` function.
3. **Pin evidence** — `pin_artifacts.py --check` passes for the staging dir.
4. **Catalog** — regenerated via `python3 scripts/build_catalog.py`.
5. **Policy maps** — `python3 scripts/fill_manifest_data.py` run; `--check` is
   clean.
6. **Test output** — ctest passes; `flutter test test/core_matrix_test.dart`
   at least IDENTIFIES.
7. **License audit** — `python3 scripts/license_audit.py` clean.

> **Note:** `docs/CORE_SYSTEM.md`, "Adding a core (contributors)", and
> `docs/BUILDING.md`, "Adding a New Core", both place `build_<id>()` in
> `scripts/build_core.sh`; all build functions live there. `core_platform.sh`
> is sourced for platform variables and helpers only. Add your recipe to
> `build_core.sh`.

### 5.3 Reviewer checklist

| Check | Command |
|---|---|
| Manifest valid (id, pins, delivery) | Visual review of `cores/<id>/manifest.json` |
| Pins match staged bytes | `python3 scripts/pin_artifacts.py <plat> --out <dir> --check` |
| No policy drift | `python3 scripts/fill_manifest_data.py --check` |
| Catalog fresh | `python3 scripts/build_catalog.py` succeeds |
| No banned content | `bash scripts/banned_content_scan.sh` clean |
| Core matrix | `flutter test test/core_matrix_test.dart` — at least IDENTIFIES |
| License clean | `python3 scripts/license_audit.py` clean |

---

## Command and rule index

### Commands

| Command | Source file | Symbol |
|---|---|---|
| `scripts/build_core.sh --fetch-headers` | `scripts/build_core.sh` | `fetch_headers()` |
| `scripts/build_core.sh <id>` | `scripts/build_core.sh` | `*` dispatch case |
| `scripts/build_core.sh --tier1` | `scripts/build_core.sh` | `TIER1` |
| `scripts/build_core.sh --tier-desktop` | `scripts/build_core.sh` | `TIER_DESKTOP` |
| `scripts/build_core.sh --tier-android` | `scripts/build_core.sh` | `TIER_ANDROID` |
| `scripts/build_core.sh --tier-ios` | `scripts/build_core.sh` | `TIER_IOS` |
| `EZCORE_PLATFORM=linux` | `scripts/core_platform.sh` | `PLATFORM` assignment |
| `EZCORE_PLATFORM=android` | `scripts/core_platform.sh` | `case "$PLATFORM"` (android) |
| `EZCORE_PLATFORM=ios` | `scripts/core_platform.sh` | `case "$PLATFORM"` (ios) |
| `scripts/build_runtime.sh <platform>` | `scripts/build_runtime.sh` | `PLATFORM` assignment |
| `ctest --output-on-failure` | `scripts/build_runtime.sh` | ctest `case` |
| `python3 scripts/pin_artifacts.py <plat> --out <dir>` | `scripts/pin_artifacts.py` | `main()` (`--out` default) |
| `python3 scripts/pin_artifacts.py ... --check` | `scripts/pin_artifacts.py` | `main()` (`--check`) |
| `python3 scripts/build_catalog.py` | `scripts/build_catalog.py` | `main()` |
| `python3 scripts/fill_manifest_data.py` | `scripts/fill_manifest_data.py` | `main()` |
| `python3 scripts/fill_manifest_data.py --check` | `scripts/fill_manifest_data.py` | `main()` (`--check`) |
| `python3 scripts/check_api_docs.py` | `scripts/check_api_docs.py` | `check()` |
| `bash scripts/banned_content_scan.sh` | `scripts/banned_content_scan.sh` | `PATTERN` / `BIOS_FILENAMES` |
| `python3 scripts/license_audit.py` | `scripts/release.sh` + `.githooks/pre-commit` | `license_audit.py` gate |
| `scripts/install-hooks.sh` | `scripts/install-hooks.sh` | `core.hooksPath` config |
| `git commit -s` (DCO) | `CONTRIBUTING.md` | "Licensing of contributions" |
| `flutter test test/core_matrix_test.dart` | `docs/BUILDING.md` | "Verification Gates (`CI` Equivalent)" |
| `flutter analyze lib/ test/` | `docs/BUILDING.md` | "Verification Gates (`CI` Equivalent)" |
| `flutter test` | `docs/BUILDING.md` | "Verification Gates (`CI` Equivalent)" |
| `scripts/release.sh <platform> --out dist/` | `scripts/release.sh` | usage header |

### Validator rules

| Rule | Enforcer file | Symbol |
|---|---|---|
| id regex `^[a-z0-9_]+$` | `lib/services/core_package_validator.dart` | `_idRegex` in `_validateManifest()` |
| id must match directory | `lib/services/core_package_validator.dart` | `_validateManifest()` |
| id must match directory (catalog) | `scripts/build_catalog.py` | `main()` |
| artifact pin regex `^[0-9a-f]{64}$` | `lib/services/core_package_validator.dart` | `_pinRegex` in `_validateManifest()` |
| delivery ∈ `{bundled, download, absent}` | `lib/services/core_package_validator.dart` | `_allowedDelivery` in `_validateManifest()` |
| delivery ios ≠ `download` (catalog) | `scripts/build_catalog.py` | `main()` |
| bios_required without bios_files → warning | `lib/services/core_package_validator.dart` | `_validateManifest()` |
| unknown top-level field → error | `lib/services/core_package_validator.dart` | `kKnownManifestFields` / `allowedFields` |
| package size ≤ 512 MiB | `lib/services/core_package_validator.dart` | `defaultMaxPackageBytes` / `_scanPackage()` |
| manifest.json ≤ 1 MiB | `lib/services/core_package_validator.dart` | `defaultMaxManifestBytes` / `validate()` |
| symlinks rejected | `lib/services/core_package_validator.dart` | `_scanPackage()` |
| iOS must never be dynarec | `scripts/core_platform.sh` | `require_interpreter_ios()` |
| blocked cores refuse to pin | `scripts/pin_artifacts.py` | `main()` (`blocked_reason` guard) |

### Files referenced

- `scripts/build_core.sh`, `scripts/core_platform.sh`, `scripts/build_runtime.sh`
- `scripts/pin_artifacts.py`, `scripts/build_catalog.py`, `scripts/fill_manifest_data.py`
- `scripts/release.sh`, `scripts/check_api_docs.py`, `scripts/banned_content_scan.sh`
- `scripts/install-hooks.sh`, `scripts/prereqs.sh`
- `lib/services/core_package_validator.dart`, `lib/services/retro_info_parser.dart`
- `.githooks/pre-commit`
- `cores/nesbyte/manifest.json` (reference), `cores/dreamarc/`, `cores/powercube/`, `cores/gambatte/`, `cores/coinbox/`, `cores/superfx/`, `cores/blastproc/` (delivery/gated fields via search)
- `test/services/core_package_validator_test.dart`
- `docs/CORE_SYSTEM.md`, `docs/BUILDING.md`, `docs/MATRIX.md` (searched)
- `CONTRIBUTING.md`

### Source notes

1. **Delivery vocabulary.** The validator enforces `bundled | download | absent`
   via `_allowedDelivery`; `on-demand` is rejected. The rest of the codebase
   uses `download`.
2. **Extra manifest fields.** `kKnownManifestFields` includes `blocked_reason`,
   `gated_reason`, `notes`, `default_options` and `system_data`; the validator
   accepts every manifest in this repository.
3. **`test/core_matrix_test.dart` reference.** The file exists and is tracked;
   the docs' reference to it is correct.
4. **Build recipe location.** `docs/CORE_SYSTEM.md`, "Adding a core
   (contributors)", and `docs/BUILDING.md`, "Adding a New Core", place
   `build_<id>()` in `scripts/build_core.sh`; all build functions are defined
   there. `core_platform.sh` only provides platform variables and helpers.

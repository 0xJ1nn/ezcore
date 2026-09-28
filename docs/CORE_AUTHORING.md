# Core Authoring Guide

From clone to a catalog-verified, pinned core in ezCORE. A core that compiles
is not a core that plays — every step below is tied to a gate that CI runs.

> **Scope.** This guide covers one path: adding or rebuilding a libretro core
> package and getting it shippable. It assumes the app shell builds (see
> `docs/BUILDING.md` for the full bootstrap). Cores implement the libretro API v1
> (see the [libretro core reference][libretro-api]); ezCORE does not extend it.
> The host-side ABI lives in `runtime/include/ezcore_runtime.h` and belongs to
> the application, not to cores.

[libretro-api]: https://docs.libretro.com/development/guidelines/core/

## 1. Build

### 1.1 Prerequisites

Install per-platform toolchains (see `docs/BUILDING.md` for full instructions):

| Platform | Essentials |
|---|---|
| macOS | Xcode 26+, Homebrew, then `scripts/prereqs.sh` |
| Linux | `cmake ninja-build pkg-config libpng-dev libgtk-3-dev clang git curl unzip` + Flutter |
| Windows | MSYS2 (UCRT64) + Flutter |
| Android | Android Studio / command-line tools + NDK r27c (`ANDROID_NDK_HOME`) |
| iOS | macOS + Xcode 15+ + CocoaPods |

### 1.2 Fetch headers (once)

Libretro cores compile against `libretro.h`. Vendor it before building the
runtime:

```bash
scripts/build_core.sh --fetch-headers
```

This clones `libretro-common` shallow and confirms
`runtime/external/libretro-common/include/libretro.h` exists.
`build_runtime.sh` refuses to run without it.

**Verified:** `scripts/build_core.sh` L37–42 (`fetch_headers`), L443 (case dispatch).

### 1.3 Set the platform

`build_core.sh` defaults to macOS arm64:

```bash
PLATFORM="${EZCORE_PLATFORM:-macos}"   # core_platform.sh L16
```

Linux (and Windows, Android, iOS) builds **must** set `EZCORE_PLATFORM`:

```bash
EZCORE_PLATFORM=linux scripts/build_core.sh --tier-desktop
```

Platform variables resolved by `scripts/core_platform.sh` (sourced at `build_core.sh`
L26):

| `EZCORE_PLATFORM` | lib suffix | make platform | artifact key | staging dir |
|---|---|---|---|---|
| `macos` (default) | `.dylib` | (empty) | `macos-arm64` | `native/cores` |
| `linux` | `.so` | `platform=unix` | `linux-x64` | `native/cores-linux-x64` |
| `windows` | `.dll` | `platform=windows` | `windows-x64` | `native/cores-windows-x64` |
| `android` | `.so` | `platform=unix` | `android-arm64` | `native/cores-android-arm64-v8a` |
| `ios` | `.dylib` | `platform=ios-arm64` | `ios-arm64` | `native/cores-ios-arm64` |

Override env vars (verified: `core_platform.sh` L4–13, `build_core.sh` L11–13):

| Var | Default | Effect |
|---|---|---|
| `EZCORE_PLATFORM` | `macos` | Selects platform layer |
| `EZCORE_ARCH` | per platform | Overrides architecture |
| `EZCORE_OUT_DIR` | per platform table | Overrides staging root |
| `JOBS_OVERRIDE` | CPU count | Parallel make jobs |
| `EZCORE_NO_RESET` | `0` | Skip `core_reset` (iteration only; never for pins) |

Android requires `ANDROID_NDK_HOME` (enforced: `core_platform.sh` L90); iOS
requires `xcrun` / the iOS SDK (`ios_toolchain`, `core_platform.sh` L107–114).

### 1.4 Build a single core

```bash
scripts/build_core.sh nesbyte
```

This dispatches to `build_nesbyte()` (verified: `build_core.sh` L448–449 — the
`*` case maps `<id>` to `build_<id>()`). The recipe clones upstream, runs
`core_make` (flock-serialized per source tree; verified: `build_core.sh`
L77–97), and calls `stage()`.

`stage()` (verified: L44–67) creates:

```
native/cores/<id>/<id>_libretro.<ext>   # stripped, macOS ad-hoc signed
native/cores/<id>/SHA256SUMS             # sha256 of the staged bytes
```

Strip policy preserves `dlopen` symbols — debug info is removed but dynamic
symbols are kept (`-x` on macOS, `-g` on Linux, `llvm-strip -g` on Android).
macOS ad-hoc signs at stage time; **pins describe the signed bytes, not
pre-sign bytes. Never re-sign a pinned artifact** (verified: L52–65, comment
L59–62).

### 1.5 Build a tier

Pre-defined tiers match the platform matrix in `build_core.sh`:

| Flag | Cores (count) | Platforms |
|---|---|---|
| `--tier1` | pocketbit, advancebit, superfx, blastproc, realmode (5) | macOS (run-verified) |
| `--tier-desktop` | 18 cores | macOS, Linux, Windows |
| `--tier-android` | 11 cores | Android |
| `--tier-ios` | 10 cores | iOS (interpreter-only) |

**Verified:** `build_core.sh` L426–435 (tier lists), L444–447 (case dispatch).

`core_reset()` (verified: L109–125) cleans stale objects on platform switches.
A `.ezcore-build-ok` marker records the last successful platform; a mismatch
triggers `git reset --hard` + `git clean -fdx`. Same-platform rebuilds stay
incremental. Set `EZCORE_NO_RESET=1` for single-core iteration only — never
for pins or releases (verified: L108, L110).

Hold cores (`citra_hold`, `switch_hold`, `ps2_hold`) refuse to build via
`hold()` which exits 4 (verified: L421–424).

## 2. Package

### 2.1 Manifest schema

The reference shape is `cores/nesbyte/manifest.json`. The complete set of
recognized top-level fields is defined in `lib/services/core_package_validator.dart`
L25–44 (`kKnownManifestFields`):

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

- **id**: must match `^[a-z0-9_]+$` (L150) and match the package directory name
  (L175–183).
- **artifacts**: every pin must be a 64-char lowercase hex string matching
  `^[0-9a-f]{64}$` (L151, L191–198).
- **delivery**: each per-OS value must be one of `bundled`, `download`,
  `absent` (L152–156, L209–217) — the same vocabulary the app's manifest
  model and every real manifest use.
- **bios_required**: `true` without `bios_files` → non-fatal warning (L222–227).
- **Unknown fields**: any top-level key not in `kKnownManifestFields` → error
  (L164–167). Callers may extend via the `allowedFields` parameter (L23–24).
- **Package size**: total bytes ≤ 512 MiB by default (`defaultMaxPackageBytes`,
  L70); oversize → error (L253–258).
- **Manifest size**: `manifest.json` ≤ 1 MiB (`defaultMaxManifestBytes`, L73);
  over cap → error (L121–125).
- **Symlinks**: any `Link` in the package tree → error (L241–243).

Validation never throws for policy failures — problems are collected in
`errors` (hard fails; `ok == false`) and `warnings` (soft) on the returned
`PackageValidationReport` (L60–67).

> ⚠️ **Verified gap: delivery vocabulary.** *(Resolved in the same PR as this
> document.)* The Dart validator originally allowed `{bundled, on-demand,
> absent}` — `on-demand` was a brief invention no consumer uses: the app's
> manifest model, `fill_manifest_data.py` (L124), every real manifest, and
> `build_catalog.py` (L68) all use `download`. The validator now accepts
> `bundled | download | absent` and rejects `on-demand` by design.
>
> ⚠️ **Verified gap: extra manifest fields.** *(Resolved in the same PR as
> this document.)* Real manifests carry `blocked_reason` (holds: citra_hold,
> switch_hold, ps2_hold), `gated_reason` (license-gated: coinbox, superfx,
> blastproc, gambatte), and `notes` (powercube). These are now in
> `kKnownManifestFields`, so the validator accepts every manifest in this
> repository.

### 2.3 What a core must implement

The libretro API v1 — `retro_*` entry points, `RETRO_API_VERSION == 1`. A core
does not implement or call the `ezcore_*` host API in
`runtime/include/ezcore_runtime.h` (that is the application's surface). Using
the existing libretro contract is what makes a core usable by ezCORE,
RetroArch, and others. Verified: `CONTRIBUTING.md` L39–42.

## 3. Declare

### 3.1 Policy maps: fill_manifest_data.py

`scripts/fill_manifest_data.py` is the single-writer for three policy
dimensions across `cores/*/manifest.json`. Add new cores to its maps, then run:

```bash
python3 scripts/fill_manifest_data.py          # write policy fields
python3 scripts/fill_manifest_data.py --check  # CI: fail on drift
```

**Verified:** `fill_manifest_data.py` L1–12, L133–134.

| Dimension | Map (file:line) | Values |
|---|---|---|
| `execution` | `EXECUTION` (L32–54) | `interpreter` \| `dynarec` per OS |
| `cheats_supported` / `cheat_families` | `CHEATS` (L58–60) | bool / string[] per core |
| `delivery` | `_delivery()` (L98–125) | per-OS: `bundled` \| `download` \| `absent` |

iOS interpreter enforcement: JIT-capable cores (dynarec) must not appear in the
iOS tier unless the recipe passes an explicit flag. `core_platform.sh`'s
`require_interpreter_ios()` refuses iOS builds without it (verified: L57–63).
Several build functions call it before `core_make` (e.g. `build_advancebit`
L167, `build_dreamarc` L329, `build_powercube` L406).

### 3.2 Delivery vocabulary for distribution

Three values ship (verified: `fill_manifest_data.py` L62–64):

| Value | Meaning | ADR |
|---|---|---|
| `bundled` | Artifact ships inside the app bundle (desktop/Android) or as embedded frameworks (iOS) | — |
| `download` | Fetched on-demand from GitHub Releases; sha256-verified against the manifest pin before staging | ADR-013 |
| `absent` | Not distributed by ezCORE | — |

Desktop giants (pointclick ~170 MB, dreamarc ~39 MB, powercube ~27 MB on
linux-x64) ship as `download` on macOS/Windows/Linux to keep the base package
lightweight (verified: `_DOWNLOAD_DESKTOP` L95, `_delivery()` L119–124).
Android bundles even the giants (no download assets published yet; L88).
iOS is never `download` — `build_catalog.py` hard-fails if any iOS delivery is
`download` (verified: L97–98).

`release.sh` ships only `bundled` cores into the app bundle; `download` cores
are fetched at first use by the Core Manager and verified against the pin
before staging (verified: `release.sh` `bundled_ids()` L43–51,
`stage_bundled()` L54–61).

The iOS rule is enforced in three places (belt-and-suspenders):
1. `build_core.sh` --tier-ios only includes interpreter-safe cores (L433)
2. `fill_manifest_data.py` never sets iOS to `download` (L89–90)
3. `build_catalog.py` L98 rejects any manifest with `ios: download`

### 3.3 Hold and gated cores

| Status | Manifest field | build_core.sh | Distribution |
|---|---|---|---|
| Hold (never built) | `blocked_reason` | `hold()` → exit 4 (L421) | Recipe retained as architecture slot only |
| Gated (license) | `gated_reason` | Builds; delivery=`absent` everywhere | Not shipped in any binary |
| Recipe-only | — | Built locally, not pinned | User-built only |

Hold cores (citra_hold, switch_hold, ps2_hold) declare `blocked_reason`
explaining the IP/legal block. `pin_artifacts.py` refuses to pin any core with
`blocked_reason` (verified: L89–90).

Recipe-only cores (coinbox, superfx, blastproc — non-commercial upstream
licenses; gambatte — GPL-2.0-only incompatible with the GPL-3.0-only app
shell) have `delivery: absent` on every OS. They build but never ship
(verified: `fill_manifest_data.py` L101–111).

> **License gate.** A GPL-2.0-only core cannot be `dlopen`'d into the
> GPL-3.0-only app bundle — a bundled plugin counts as a combined work. This is
> why gambatte is gated despite being functional (verified: gambatte manifest
> `gated_reason`, `fill_manifest_data.py` comment L91–94).

### 3.4 Catalog merge: build_catalog.py

`scripts/build_catalog.py` reads every `cores/*/manifest.json` and writes two
Flutter assets:

```
cores/catalog.json   # merged index (sorted ids, sort_keys) — loaded at startup
cores/release.json   # on-demand download map: repo, tag, asset filenames
```

**Verified:** `build_catalog.py` L27–28, L103–106.

It enforces (verified: L34, L90–100):

- `REQUIRED = ("id", "name", "version", "license", "systems", "delivery")` —
  all must be present (L90–92).
- id must match directory name, unless suffix is `_hold` (L93–94).
- No duplicate ids (L95–96).
- iOS delivery must never be `download` (L97–98).
- Blocked cores (`blocked_reason`) must not carry artifacts (L99–100).

Run after any manifest change — fresh checkouts regenerate the catalog from
manifests:

```bash
python3 scripts/build_catalog.py
```

## 4. Verify

Every command here is a gate in both `.githooks/pre-commit` and
`scripts/release.sh`.

### 4.1 Pin check: pin_artifacts.py --check

```bash
python3 scripts/pin_artifacts.py macos-arm64 --out native/cores --check
```

For macOS, `--out` must be `native/cores` — the staging dir has no platform
suffix, but the script's default is `native/cores-{plat}`. For other platforms
the default matches the staging dir (verified: `core_platform.sh` L47–53 vs
`pin_artifacts.py` L68–72).

`--check` verifies staged bytes against committed pins — **both directions**
(verified: `pin_artifacts.py` L57–155):

1. Every staged artifact's SHA-256 must match the pin in
   `manifest.json` `artifacts.<plat>` (L92–98).
2. Every pinned manifest must have a staged artifact (L111–123).
3. Every `delivery: bundled` core must be staged (L124–142).

The SHA256SUMS sidecar is **regenerated from real bytes on every write** and
never trusted — a stale sidecar once hid signed cores whose bytes no longer
matched their pins (verified: L8–9 comment, L100).

Write mode (after a successful build):

```bash
python3 scripts/pin_artifacts.py macos-arm64 --out native/cores
```

Pins the staged bytes into `manifest.json`, refreshes SHA256SUMS, and
regenerates `catalog.json` (verified: L100–107, L147–153).

**Waivers:** cores listed in `native/pin-waivers/<plat>.txt` are exempted from
check #3 (e.g., a missing toolchain dep on a build host). Waiver files are
plain text, one id per line, `#` comments allowed (verified: L130–139).

### 4.2 Pre-commit gate

Install once per clone:

```bash
scripts/install-hooks.sh
```

This sets `git config core.hooksPath .githooks` (verified: `install-hooks.sh`
L6). Every `git commit` then runs `.githooks/pre-commit`:

| Gate | File | What it checks |
|---|---|---|
| §79 scratch tooling | `.githooks/pre-commit` L12–28 | rejects `_probe.*`, `screenshot_*`, `inject_*`, `capture_*`, `xdotool`, `ydotool`, `wtype` in staged files |
| Banned content | `scripts/banned_content_scan.sh` | ROM/BIOS/key extensions + exact filename match; `test/fixtures/` allowlist |
| License/delivery | `scripts/license_audit.py` | license compliance, delivery map consistency |
| Manifest policy | `scripts/fill_manifest_data.py --check` | execution/cheats/delivery drift (same gate `release.sh` runs) |
| Design evidence | `scripts/check_design_evidence.py` | only when `design/` or the gate itself is staged |

All gates are read-only — no git rewrites in the hook body. **Verified:**
`.githooks/pre-commit` L1–92.

### 4.3 ctest (runtime)

```bash
scripts/build_runtime.sh macos      # or: linux windows android ios
```

Builds the C runtime + synthetic test core via CMake/Ninja, then runs CTest on
macOS/Linux hosts:

```bash
(cd runtime/build-macos && ctest --output-on-failure)
```

Verified: `build_runtime.sh` L59–69. Requires `--fetch-headers` first (L19–21).
iOS/Android cross builds produce a library but skip host-side ctest (CI runners
handle those legs; L62–68).

### 4.4 Core matrix (Dart FFI)

```bash
flutter test test/core_matrix_test.dart
```

A Dart-driven, fork-isolated harness that `dlopen`s each staged core and
verifies it at least **IDENTIFIES** to the libretro ABI — a core that compiles
but fails `dlopen` or `ident` is a fail. Staged `.dylib`/`.so`/`.dll` files in
`native/cores/` are required.

Verified: `docs/CORE_SYSTEM.md` L212, `docs/BUILDING.md` L135,
`docs/MATRIX.md` L13.

> **Checked and false:** an earlier draft reported
> `test/core_matrix_test.dart` as missing. It exists (2 tests) and is tracked
> on main; the draft's file search simply failed. The docs' reference to it
> is correct.

### 4.5 API-doc gate

```bash
python3 scripts/check_api_docs.py
```

Verifies `docs/API.md` documents every function/macro in
`runtime/include/ezcore_runtime.h` — both directions (header→doc and
doc→header). Wired into the ctest suite.

Verified: `scripts/check_api_docs.py` L1–30.

### 4.6 Dart gates

```bash
flutter analyze lib/ test/
flutter test
```

Verified: `docs/BUILDING.md` L128–129.

## 5. Submit

### 5.1 Commit

```bash
git commit -s    # DCO sign-off
```

DCO sign-off required (verified: `CONTRIBUTING.md` L80). The pre-commit gate
runs automatically — resolve all failures before opening a PR.

### 5.2 Pull request

A core PR must include (verified: `docs/CORE_SYSTEM.md` L205–216,
`docs/BUILDING.md` L138–149):

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

> **Note:** `docs/CORE_SYSTEM.md` L210 and `docs/BUILDING.md` L3 say to add
> `build_<id>()` to `scripts/core_platform.sh`, but all build functions live in
> `scripts/build_core.sh` (verified: L127–418). `core_platform.sh` is sourced
> for platform variables and helpers only. Add your recipe to `build_core.sh`.

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

## Verified against this checkout

Branch `docs/p1c-core-authoring`, worktree
`/home/jinultimate1995/Projects/ezcore/.worktrees/p1c-authoring`.

### Commands verified to exist in source

| Command | Source file | Line(s) |
|---|---|---|
| `scripts/build_core.sh --fetch-headers` | `scripts/build_core.sh` | L443 |
| `scripts/build_core.sh <id>` | `scripts/build_core.sh` | L448–449 |
| `scripts/build_core.sh --tier1` | `scripts/build_core.sh` | L444 |
| `scripts/build_core.sh --tier-desktop` | `scripts/build_core.sh` | L447 |
| `scripts/build_core.sh --tier-android` | `scripts/build_core.sh` | L445 |
| `scripts/build_core.sh --tier-ios` | `scripts/build_core.sh` | L446 |
| `EZCORE_PLATFORM=linux` | `scripts/core_platform.sh` | L4, L16 |
| `EZCORE_PLATFORM=android` | `scripts/core_platform.sh` | L4, L39 |
| `EZCORE_PLATFORM=ios` | `scripts/core_platform.sh` | L4, L43 |
| `scripts/build_runtime.sh <platform>` | `scripts/build_runtime.sh` | L2, L15 |
| `ctest --output-on-failure` | `scripts/build_runtime.sh` | L64 |
| `python3 scripts/pin_artifacts.py <plat> --out <dir>` | `scripts/pin_artifacts.py` | L56, L68–72 |
| `python3 scripts/pin_artifacts.py ... --check` | `scripts/pin_artifacts.py` | L58 |
| `python3 scripts/build_catalog.py` | `scripts/build_catalog.py` | L114 |
| `python3 scripts/fill_manifest_data.py` | `scripts/fill_manifest_data.py` | L133 |
| `python3 scripts/fill_manifest_data.py --check` | `scripts/fill_manifest_data.py` | L134 |
| `python3 scripts/check_api_docs.py` | `scripts/check_api_docs.py` | L30 |
| `bash scripts/banned_content_scan.sh` | `scripts/banned_content_scan.sh` | L1 |
| `python3 scripts/license_audit.py` | `scripts/release.sh` + `.githooks/pre-commit` | L68 / L42 |
| `scripts/install-hooks.sh` | `scripts/install-hooks.sh` | L6 |
| `git commit -s` (DCO) | `CONTRIBUTING.md` | L80 |
| `flutter test test/core_matrix_test.dart` | `docs/BUILDING.md` | L135 |
| `flutter analyze lib/ test/` | `docs/BUILDING.md` | L128 |
| `flutter test` | `docs/BUILDING.md` | L129 |
| `scripts/release.sh <platform> --out dist/` | `scripts/release.sh` | L2 |

### Validator rules verified

| Rule | Enforcer file | Line(s) |
|---|---|---|
| id regex `^[a-z0-9_]+$` | `lib/services/core_package_validator.dart` | L150 |
| id must match directory | `lib/services/core_package_validator.dart` | L175–183 |
| id must match directory (catalog) | `scripts/build_catalog.py` | L93–94 |
| artifact pin regex `^[0-9a-f]{64}$` | `lib/services/core_package_validator.dart` | L151, L191–198 |
| delivery ∈ `{bundled, download, absent}` | `lib/services/core_package_validator.dart` | L152–156 |
| delivery ios ≠ `download` (catalog) | `scripts/build_catalog.py` | L97–98 |
| bios_required without bios_files → warning | `lib/services/core_package_validator.dart` | L222–227 |
| unknown top-level field → error | `lib/services/core_package_validator.dart` | L164–167 |
| package size ≤ 512 MiB | `lib/services/core_package_validator.dart` | L70, L253–258 |
| manifest.json ≤ 1 MiB | `lib/services/core_package_validator.dart` | L73, L121–125 |
| symlinks rejected | `lib/services/core_package_validator.dart` | L241–243 |
| iOS must never be dynarec | `scripts/core_platform.sh` | L57–63 (`require_interpreter_ios`) |
| blocked cores refuse to pin | `scripts/pin_artifacts.py` | L89–90 |

### Files read

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

### Verified gaps (discrepancies in the source, not guesses)

1. **Delivery vocabulary mismatch.** *(Resolved in this PR.)* The Dart
   validator originally allowed `on-demand`; the rest of the codebase uses
   `download`. The validator now enforces `bundled | download | absent`.
2. **Extra manifest fields not in `kKnownManifestFields`.** *(Resolved in
   this PR.)* `blocked_reason`, `gated_reason`, and `notes` are now known
   fields; the validator accepts every manifest in this repository.
3. **`test/core_matrix_test.dart` "missing".** *(Withdrawn — false.)* The
   file exists and is tracked; the draft's search failed, not the repo.
4. **Build recipe location.** `docs/CORE_SYSTEM.md` L210 and `docs/BUILDING.md`
   L3 said to add `build_<id>()` to `scripts/core_platform.sh`, but all build
   functions are defined in `scripts/build_core.sh` (L127–418);
   `core_platform.sh` only provides platform variables and helpers. Both old
   docs are corrected in the same PR as this document.

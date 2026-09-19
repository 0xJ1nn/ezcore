# Changelog

All notable changes to ezCORE are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] — 2026-09-19

**First legal-clean release.** Rebuilt without the non-commercial cores.

### Removed

- **FinalBurn Neo, Snes9x, Genesis Plus GX** — removed from all binary
  distributions (non-commercial licenses). They remain in-tree as build
  recipes only. v0.1.0 was a free distribution under those licenses'
  free-use terms and is unaffected.

### Fixed

- `fill_manifest_data.py` now treats `snes9x` + `genesis_plus_gx` the same
  as `fbneo` (absent from all OS delivery maps) — the script previously
  expected `bundled` because they were still in the tier lists, causing
  manifest drift.
- Stale NC core dylibs left in `build/macos/.../cores/` from v0.1.0 were
  not cleaned by `release.sh` (it only adds, never removes). Manually
  removed; future `release.sh` runs should `rm -rf` the cores dir before
  staging.

### Verification

- macOS arm64: 15 cores bundled, ad-hoc signed + sandboxed, app launches
  to Library empty-state. SHA256SUMS verified by re-download.
- Android arm64: 8 cores bundled, arm64-v8a only. SHA256SUMS verified.

[0.1.1]: https://github.com/JinUltimate1995/ezcore/releases/tag/v0.1.1

## [0.1.0] — 2026-09-19 (original public release)

### Removed (from the codebase, not the release)

- **Snes9x and Genesis Plus GX are no longer distributed in any binary.**
  Their upstream licenses are non-commercial and ezCORE ships one artifact
  for everyone (free or paid), so they stay in-tree as build recipes only —
  compile your own if you want them. v0.1.0, already published, was a free
  distribution under those licenses' free-use terms and is unaffected.
- `roms/` — a stray commit had added failed Internet Archive downloads of
  commercial games under their commercial filenames (plus copies of the two
  homebrew fixtures, which already live in the gitignored `native/test-roms/`).
  `roms/` is now gitignored.

### Added

- `scripts/legal_audit.py` — machine check for the licensing rules
  (non-commercial cores never bundled, holds stay empty, bundled cores are
  attributed and pinned). Wired into `scripts/release.sh` and the new
  pre-commit hook.
- `.githooks/pre-commit` + `scripts/install-hooks.sh` — commits are blocked
  when the banned-content scan or the legal audit fails.

## [0.1.0] — 2026-09-19

**First public release.** Early build — expect rough edges; see the notice
at the top of [`README.md`](README.md).

### Added

- **Orbit console UI** — Library (CoverFlow + game dock, grid view, search,
  keyboard browse), Systems (core browser with add/remove and per-core
  license info), Time Capsule (local save-snapshot vault with
  resume-and-load), Player (pause, quick-save, fast-forward, screenshot →
  cover, touch pad + haptics, live cheats, slot save/load, reset, "Take a
  breather" autosave overlay), Settings (six local-preference tabs).
- **ezCore Runtime (C11, ABI v1)** — session lifecycle, frame loop, AV
  buffers, input, save states, SRAM handoff, cheats; POSIX/Win32 dynload
  seam with sha256 verification before load; `fork()`-isolated native boot
  tests with a synthetic core (no ROMs needed).
- **Modular core system** — 18 built libretro cores with per-core
  manifests (license, pins, execution policy, BIOS policy); merged
  `cores/catalog.json` asset; sha256 pins verified at staging and release.
- **Platform builds** — macOS arm64 (app + 18 cores built, 17 bundled);
  Android arm64 (APK, release keystore signing); Windows/Linux shells in the
  CI matrix (no binaries yet).
- **Docs** — INSTALL, BUILDING, ARCHITECTURE (as-built), CORE_SYSTEM,
  MATRIX, RELEASE_PLAN, RELEASING, THIRD_PARTY_NOTICES, TRADEMARKS, DMCA,
  SECURITY, SUPPORT, CONTRIBUTING.
- **Repo infrastructure** — CI workflow (5-OS matrix), full-matrix workflow,
  release workflow with checksums + notes files, issue/PR templates,
  CODEOWNERS, dependabot.

### Fixed

- BIOS presence gate could never match files for cores whose manifest
  entries carried annotations (`beetle_pce`, `beetle_saturn`, `melonds`,
  `flycast`, `fbneo`) — the player's boot gate always reported "BIOS
  missing". Entries are now bare filenames (notes moved to `bios_notes`),
  with defensive normalization at parse time; blanket boot gates on
  CD/NeoGeo-only firmware were relaxed to warnings for HuCard/arcade
  titles.
- `release.sh` copied every staged core into every bundle, contradicting
  FBNeo's own "held pending review" policy; releases now bundle exactly the
  cores whose manifest `delivery` promises `bundled` for the target OS.
- Analyzer: unused SHA-256 field removed; harness print lints scoped so
  `flutter analyze` is clean project-wide.

### Known limitations (0.1.0)

- macOS arm64 is the only platform with a locally built, run-verified app;
  ad-hoc signed (not notarized).
- Android: builds + installs; on-device boot verification pending a device
  lab.
- Windows/Linux: no binaries yet — build from source for now.
- iOS: not distributed (no Apple identity yet).
- Core verification: 3 cores boot-and-render verified (SameBoy, Gambatte,
  mGBA); the rest load and identify — render verification in progress.
- FBNeo held from shipping (compatibility review).
- macOS sandbox: typed-path import of arbitrary folders stays limited to
  what the system picker / security-scoped bookmarks allow.

[0.1.0]: https://github.com/JinUltimate1995/ezcore/releases/tag/v0.1.0

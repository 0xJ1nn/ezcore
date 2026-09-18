# Changelog

All notable changes to ezCORE are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

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
- Windows/Linux: no binaries (CI paused on Actions billing).
- iOS: not distributed (no Apple identity yet).
- Core verification: 3 cores boot-and-render verified (SameBoy, Gambatte,
  mGBA); the rest load and identify — render verification in progress.
- FBNeo held from shipping (compatibility review).
- macOS sandbox: typed-path import of arbitrary folders stays limited to
  what the system picker / security-scoped bookmarks allow.

[0.1.0]: https://github.com/JinUltimate1995/ezcore/releases/tag/v0.1.0

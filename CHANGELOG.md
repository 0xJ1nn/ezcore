# Changelog

All notable changes to ezCORE are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **A real page for every game.** Its own art fills the background; Resume
  (or Play) is the big action, with Play from start beside it. Every save is a
  card with a readable name — Automatic, Quick save, Saved 14:22 — that you can
  load or delete. Choose the core, manage cheats, see the file, favourite it or
  remove it from your library (the file itself is never deleted).
- **See where you are.** Games and cores lift on hover, and keyboard or
  controller focus shows a bright ring. The Resume card shows the game's art,
  and moving between Library, Cores and Settings fades instead of cutting.
- **Cores can ship their own controls.** A core package may include on-screen
  layouts (and device shells) for its systems; they are checked as strictly as
  everything else in a package and used for that core's games. Your own edited
  layout still wins, and Reset returns to the core's design.
- **Settings in plain words.** One "Settings" heading instead of slogans and a
  "local preferences" badge; every section titled for what it is; jargon
  ("frames stepped per tick", "emulated PCM", "native sink") replaced with
  what it means for you. "Time capsule" is now simply Saves.
- **A clear Cores screen.** Cores are listed by the systems they play, each
  with a plain status (Ready, needs BIOS files, Download to install, Not
  available on this device) and a Verified/Unverified label. Details and
  actions sit beside the list on wide screens and open as a page on phones;
  "Install core from file" is a labelled button. Show games opens the library
  filtered to that system. Fixes the phone overflow on the old screen.
- **Saved core settings are applied when a game starts.** Per-core and per-game
  option overrides are stored, resolved (a per-game value wins over a per-core
  value), and handed to the core after it loads but before the game does,
  because many cores read their options only while loading a game. A setting
  the core no longer declares is reported, not fatal. There is no settings
  screen for core options yet; this is the plumbing it will use.
- **Cores can ship recommended settings.** A core manifest may declare
  `default_options`: starting values for the core's own settings, validated as
  plain strings and always overridden by your own choices. The N64 core uses it
  to start on its software renderer, which is the only way it can draw until
  GPU support lands.
- **Crash protection (experimental, off by default).** Settings > Emulation >
  Crash protection runs each game's core in a separate helper process
  (`ezcore_core_host`). If the core crashes or stops responding, only that game
  ends, with a plain message; the app, your library and your saves are
  untouched. Linux verified; Windows packaged but not yet run; macOS and Android
  not wired yet; iOS cannot support it (Apple forbids helper processes).
### Changed

- **A simpler home.** Three destinations — Library, Cores, Settings — on every
  screen size. Library opens on **Resume**: one tap back into the game you
  played last, from where you left off, whatever system it is. Below it,
  Continue playing, filters named by system (never by core), and every game.
  Removed: the decorative clock/Wi-Fi/"P1" bar, slogans, the duplicate system
  menu, and the cover-flow carousel and its settings. Saves live with each game
  and in Settings.
- **Real on-screen controls.** Each system family gets a proper layout in
  portrait and landscape — d-pad, face buttons in the system's own style
  (Nintendo letters, PlayStation symbols, Genesis A/B/C), shoulders and
  Start/Select — and handhelds get a device shell; the Nintendo DS shows its
  two screens as a clamshell with a hinge, side by side in landscape.
  Multi-touch, slide between buttons, diagonals on the d-pad. On by default on
  phones and tablets, off on desktop; toggle from the pause menu.
- **Make the controls yours.** Pause menu → Edit controls: drag any button,
  resize it, hide the ones you never use (Menu always stays), set opacity, save
  — per system and orientation — or reset to default.
- **Controllers, properly.** Remap any button in Settings > Controllers
  (press the button you want; reset to default any time). Hold **Select +
  Start** in a game for the pause menu. A controller now drives every menu:
  d-pad moves, A chooses, B goes back.

### Fixed

- About showed version 0.1.0 in a 0.2.0 build. The version now comes from one
  place, with a test that fails if it drifts from the build.
- After leaving a game, Settings stopped hearing controller events on Android
  and iOS: each screen made its own controller service, and closing the
  player's cleared the channel for everyone. There is now one shared service.
- **A real pause menu.** Resume, save and load state, cheats, show/hide
  controls, fast-forward, screenshot, reset and quit — from the Menu button,
  Esc, or the system Back gesture (which no longer drops you out of a game).

### Fixed

- **Core settings now reach the core.** The runtime stored the options a core
  declared and let the host change them, but never answered the two requests a
  core uses to read them (`GET_VARIABLE`, `GET_VARIABLE_UPDATE`), so every core
  silently ran on its built-in defaults. Covered by a new `core_variables`
  native test that checks the value from the core's side, not the runtime's.
- **Held input can no longer latch.** Pressing reset no longer leaves a button
  held down, loading a game no longer carries held buttons across the boundary,
  and unplugging a controller mid-press no longer leaves that direction stuck for
  the rest of the session — on Windows and on Linux.
- **The second player's controller now reaches port 1.** The input path
  hardcoded port 0, so no controller could address a second port. It now carries
  the port, defaults to 0 so existing behaviour is unchanged, and pausing
  releases every port.
- **Stick and trigger calibration.** The Windows deadzone swallowed more than a
  third of full stick deflection, and analog triggers registered as pressed at
  30 of 255 — so a trigger resting from ordinary drift read as fully pulled. Both
  are now proportionate to full scale. On Linux, stick range is read from the
  kernel's real axis range (`EVIOCGABS`) instead of being seeded from whatever
  the stick happened to report first, which could permanently latch a direction
  after a single spike at connect.
- **A control held across a pause or app switch now re-sends on resume.** The
  host releases held buttons when paused, but the input poller only emits on
  transitions, so a still-held control went silent until it was released and
  re-pressed. The poller now re-syncs with the host.
- **Linux mouse movement is no longer discarded.** Relative-axis (`EV_REL`)
  events were read and thrown away, so no mouse or trackball could ever reach a
  core. They are now decoded and surfaced.

### Added

- The crash-containment spike's exit-code contract now has automated coverage: a
  test core that faults on demand proves that a real segmentation fault is
  classified as a crash. This validates the contract only — **the app still
  terminates with a crashing core**, and process isolation is not implemented.

### Changed

- **The RENDERS verification level now proves save/restore fidelity.** The boot
  harness previously printed the post-restore pixel sum without checking it, so a
  core whose restore corrupted the framebuffer still counted as verified. The
  sum is now compared against the pre-restore value within a documented 2%
  tolerance, and a lossy restore fails. This is a loose smoke gate, not
  pixel-exactness: a core swapping two equally-weighted sprites can still pass.
  Existing verification levels are unchanged; the maintainer should re-run the
  boot matrix to confirm no cell regressed.
- Corrected the documented kernel capability count, which had gone stale in six
  files. The kernel answers 13 of the 93 environment commands the vendored
  libretro header defines, not the 7 of 92 previously claimed. The counting
  command is now printed in the documentation so the figure can be recomputed
  rather than trusted.
- Documented the verification levels against what the harness actually asserts,
  and recorded per-file licence provenance for the local test fixtures: one of
  the three is CC0, one is a third-party copyrighted suite, and one has no
  declared licence.

### Changed

- Reworked desktop and phone Library browsing into a responsive cover-flow
  experience with nearby covers, centered paging, and Classic, Gentle, and Flat
  motion styles. Tablet layouts keep the focused Continue/Recently added hub.
- Replaced the Systems catalog vector drawings with consistent, project-generated
  product renders. Added system-family artwork fallbacks for future cores and
  improved the core browser across portrait, landscape, and compact layouts.
- Hardened pinned screenshot covers so replacing bytes at an existing path
  evicts stale Flutter image-cache state and remounts the cover with the new
  revision.

### Fixed

- Cores that do not export the optional libretro `retro_cheat_reset` or
  `retro_cheat_set` symbols now load normally; unsupported cheat calls fail
  safely instead of being treated as a core-load error.
- **Orbit design evidence can no longer drift or regress silently.**
  `design/ezcore-orbit/verify_brand.py` captured the `details` and `pause`
  screens with no settle wait, so those screenshots raced the overlay's `.3s`
  fade-in and could commit a semi-transparent overlay with the library legible
  through it. Capture is now deterministic — `reduced_motion='reduce'` (which
  the prototype already honours), pinned Chromium colour/raster flags, and an
  explicit wait for every animation to finish before each screenshot, and
  every capture passes Playwright's `animations='disabled'`, which
  fast-forwards transitions that start after the wait — a transition tail was
  flipping `responsive-768.png` between two byte states across runs. The run
  also asserts the overlay still has a working `backdrop-filter` and a scrim
  opaque enough to obscure content without it, and now records each state's
  `height`/`scrollHeight`, which it previously never captured.

### Added

- **`scripts/check_design_evidence.py`** — dependency-free (standard library
  only) gate over the committed evidence, wired into the pre-commit hook. It
  fails when a capture is missing, blank, implausibly sized, from a different
  run than the rest, out of step with `report.json`, when `report.json` records
  fewer than the expected 36 states, or when the overlay backdrop check is
  absent. It runs only when a commit actually touches the evidence directory.
  Escape hatch: `EZCORE_SKIP_DESIGN_EVIDENCE=1`.

  This is the blind spot that let 18 committed PNGs change height (android
  +4px, ios +4px, windows +21px) while `report.json` stayed byte-identical:
  height was never recorded, so nothing could cross-check the files. The report
  now records each capture's own `captureWidth`/`captureHeight`, read back from
  the PNG header, which is what makes the cross-check possible at all.

  Determinism is demonstrated rather than asserted: two back-to-back runs
  produce 57 of 57 byte-identical PNGs with zero differing pixels. The two
  sources of real pixel drift were a live clock in the shell header and a toast
  that self-hides on a 3s timer; neither is a CSS animation, so waiting on
  `getAnimations()` never saw them. The clock is frozen for the run and
  transient toasts are dismissed before each capture.

### Verification

- Replacement-stack checks: `flutter analyze` clean; `flutter test --no-pub`
  **441 passed / 15 skipped / 0 failed**; Linux CTest **3/3**; Linux debug and
  Android debug builds passed.
- Manifest, license, artwork provenance/WebP decode, banned-content, and
  whitespace gates passed. Device boot and unlisted platform execution remain
  unverified.

## [0.2.0] — 2026-09-23

**Hybrid on-demand cores, ROM import hardening, license-wording scrub.**

### Added

- **On-demand core downloads (hybrid delivery — ADR-013).** The three
  desktop giants — `pointclick` (~170 MB staged), `dreamarc` (~39 MB),
  `powercube` (~27 MB) — are now `delivery: download` on desktop instead
  of living inside the package. The Core Manager fetches them from this
  repository's GitHub Releases (`cores/release.json` = repo + tag + asset
  names, generated by `build_catalog.py`), streams them to a `.part`
  file, verifies every byte against the manifest's sha256 pin, and only
  then stages + registers them. All other cores stay `bundled`; iOS never
  downloads (App Review 2.5.2/4.7) and Android keeps its bundled tier.
- **Per-core ROM validation** — playable extensions come from the real
  manifests; system files with the same or similar extensions are
  rejected before import (`rom_validation_deep_test`, driven from the
  committed catalog).
- **"ezCORE ROMs" folder dialogue** — the app asks before creating its
  managed ROMs folder on device.

### Changed

- **License-wording scrub (repo-wide)** — "legal"-type phrasing replaced
  with license/compliance wording; the `legal_audit` gate was renamed
  `license_audit`.
- **`license_audit` treats `download` as distribution** — the
  non-commercial and GPL-2.0-only bans, notices rule, and pin rule cover
  on-demand cores exactly like bundled ones (gate gap this feature would
  otherwise have opened).
- **`fill_manifest_data.py --check` runs in the pre-commit hook** next to
  `banned_content_scan` and `license_audit` — manifest/policy drift
  cannot be committed.
- Fresh core re-pins for `pointclick`/`portcomp`/`powercube` on the
  current host toolchain (GLIBC_2.43), clearing the 7 stale-artifact test
  failures; `gambatte` removed from all ship tiers (GPL-2.0-only cannot
  combine with this GPL-3.0-only app).

### Verification

- `flutter analyze` clean; `flutter test` **354 passed / 15 skipped /
  0 failed** (14 new hybrid-download tests, written failing-first);
  `fill_manifest_data --check`, `license_audit`, `pin_artifacts --check`,
  `banned_content_scan` green.
- Hybrid path proven by unit tests: URL construction, verify-or-discard
  on hash mismatch, no partial files after transport failure, staging
  keeps verified downloads, iOS refusal.
- **Not verified on this host:** macOS/Windows/iOS builds — not built
  here, not claimed.

[0.2.0]: https://github.com/JinUltimate1995/ezcore/releases/tag/v0.2.0

## [0.1.1] — 2026-09-19

**Rebuilt without the non-commercial cores** (license audit applied).

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

- `scripts/license_audit.py` — machine check for the licensing rules
  (non-commercial cores never bundled, holds stay empty, bundled cores are
  attributed and pinned). Wired into `scripts/release.sh` and the new
  pre-commit hook.
- `.githooks/pre-commit` + `scripts/install-hooks.sh` — commits are blocked
  when the banned-content scan or the license audit fails.

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

# ezCORE Known Issues

> Snapshot date: 2026-09-25
> This file records observed problems separately from the roadmap. Historical
> release checkpoints remain in [`../docs/IMPLEMENTATION_STATUS.md`](../docs/IMPLEMENTATION_STATUS.md).

## Open issues

### EZC-001 — Resolved: analyzer gate is clean

- **Description:** The earlier unused-import warning and timeout were observed
  while the theme files were still changing. The completed replacement stack
  now passes `flutter analyze` with no issues.
- **Affected platform:** Flutter targets (source-level gate).
- **Affected core/system:** None; presentation/test files only.
- **Verification:** `flutter analyze` — **No issues found** (`18.3s`).
- **Status:** Resolved for the current checkout; CI/device coverage remains
  separate.

### EZC-002 — Resolved: full Flutter suite is green

- **Description:** The earlier full run reported 373 passed, 15 skipped, and
  10 failed while the theme files were changing. The completed replacement
  stack now passes the complete suite.
- **Affected platform:** Flutter widget-test host; theme/layout code paths.
- **Affected core/system:** None.
- **Verification:** `flutter test --no-pub` — **441 passed, 15 skipped, 0
  failed**.
- **Status:** Resolved for the current checkout; skipped integration cases
  remain explicitly unverified rather than silently counted as gameplay.

### EZC-003 — App-level external-file acceptance is not re-verified

- **Description:** The historical macOS integration checkpoint reported that
  typed external paths could fail under the app sandbox before import/player
  acceptance. The repository now contains picker/bookmark seams, but the
  complete sandboxed import → play → save/load → reopen path has not been
  rerun in this audit.
- **Affected platform:** macOS app sandbox.
- **Affected core/system:** Any user-imported content.
- **Reproduction:** Run `integration_test/player_flow_test.dart` on a macOS
  build with the documented checkout define and a permitted file path.
- **Severity:** Medium/High for the user flow; not proven as a current
  regression.
- **Workaround:** Use the system picker and grant security-scoped access; do
  not bypass sandbox entitlements.
- **Status:** Needs re-verification.
- **Follow-up:** Platform acceptance task after the coordinated theme-track
  stabilization and integration review.

### EZC-004 — Native execution is not crash-isolated in the app

- **Description:** The Dart worker isolate owns a session, but native core code
  still runs in the application process. The C runtime also uses a
  process-global active-session pointer.
- **Affected platform:** All platforms.
- **Affected core/system:** Any native core; particularly GL-dependent cores.
- **Reproduction:** Load/run a core that crashes or exercise concurrent session
  ownership; do not use this as a routine test because a native crash can
  terminate the app/test process.
- **Severity:** Medium/High.
- **Workaround:** One owner per runtime process and fork-isolated native tests.
- **Status:** Known limitation; architectural follow-up required.

### EZC-005 — Battery-save content round trips are not fully verified

- **Description:** The player gives each game a separate SRAM directory and
  the runtime passes save/system directories to cores, but a save-exercising
  public-domain fixture and per-core round-trip evidence are incomplete.
- **Affected platform:** All platforms where a core uses SRAM.
- **Affected core/system:** Core-specific.
- **Reproduction:** Load permitted homebrew, make a persistent change, close,
  reopen with the same game directory, and compare the expected state.
- **Severity:** Medium.
- **Workaround:** Keep per-game directories; do not share one SRAM folder
  between games.
- **Status:** Open verification gap.

### EZC-006 — GL/default-renderer cores lack frame evidence

- **Description:** Several desktop cores identify or load but require a GL
  context or core options not supplied by the current runtime path.
- **Affected platform:** Desktop, especially Linux/macOS as listed in the
  canonical matrix.
- **Affected core/system:** Geometry1, RCP64, DualScreen, PortComp, DreamArc,
  and PowerCube may require renderer/core-option work.
- **Reproduction:** Attempt content boot without a suitable GL context or
  software-renderer configuration.
- **Severity:** Medium.
- **Workaround:** Use cores/paths already marked RENDERS in the matrix; do not
  infer gameplay from I/B status.
- **Status:** Blocked on renderer/options architecture and fixtures.

### EZC-007 — Platform and device verification is uneven

- **Description:** macOS has the strongest current run evidence. Linux app
  launch/build evidence exists, while Windows/iOS/Android execution and
  physical-controller/audio behavior require their own verification runs.
- **Affected platform:** Linux, Windows, Android, iOS, and hardware input.
- **Affected core/system:** Platform shell and device integrations.
- **Reproduction:** Follow the commands in `docs/BUILDING.md` and record the
  exact host/device and result.
- **Severity:** Medium.
- **Workaround:** Treat source presence and artifact inspection as
  implementation evidence only, not runtime compatibility.
- **Status:** Open platform verification queue.

### EZC-008 — Resolved: tablet portrait is an explicit fifth layout

- **Description:** The earlier responsive policy mapped every portrait viewport
  to the phone family. The replacement stack now distinguishes a tablet-sized
  portrait viewport at the shared `bpCompact` breakpoint.
- **Affected platform:** Flutter UI on tablets and large phones.
- **Affected core/system:** None.
- **Verification:** `Layout.ofSize(const Size(834, 1194), Orientation.portrait)`
  returns `OrbitLayout.tabletPortrait`; the shell test verifies the rail and
  Continue/Recently Added hub. An 834×700 Linux capture is stored at
  `docs/images/library-tablet.png`.
- **Status:** Resolved for the current five-family contract. Desktop and
  phone layouts use cover flow; both tablet orientations retain the hub.
- **Follow-up:** Revisit breakpoints only through a dedicated responsive design
  task with new evidence.

### EZC-009 — Resolved: PR diff whitespace is clean

- **Description:** The earlier design commits carried one extra blank line at
  EOF in each of two files. The focused cleanup removed both without changing
  behavior.
- **Affected platform:** Repository quality gate.
- **Affected core/system:** None; theme/UI files.
- **Verification:** `git diff main...HEAD --check` is clean after the fix
  commit.
- **Status:** Resolved for the replacement stack.

### EZC-010 — Desktop/tablet Favorites chip does not apply its filter

- **Description:** In the theme redesign, the library strip's Favorites chip
  calls `_setFilter('Favorites')`, which sets `tab = 'all'`. The shared
  `filtered` predicate explicitly ignores `filter == 'Favorites'`, so desktop
  and tablet users can see the chip become inactive without the collection
  being filtered. The phone-portrait tab path is separate.
- **Affected platform:** Flutter desktop/tablet library layouts.
- **Affected core/system:** None.
- **Reproduction:** Open a library with at least one favorite and one
  non-favorite game, then activate the Favorites chip in the desktop/tablet
  strip.
- **Severity:** Medium — a visible navigation control does not apply its
  promised filter.
- **Workaround:** Use the phone-portrait Favorites tab, or filter through a
  different surface until the theme owner reconciles the two paths.
- **Verification:** `test/library_layouts_test.dart` now covers the desktop
  Favorites chip and confirms the non-favorite disappears from the collection.
- **Status:** Resolved; the chip now uses the shared `favorites` tab value.
- **Follow-up:** Keep the tab/filter vocabulary aligned if the strip gains new
  controls.

### EZC-011 — Tablet “Recently added” row renders the filtered collection

- **Description:** The theme redesign defines a `recentlyAdded` getter, but the
  tablet hub's `Recently added` section passes `games` (the current filtered
  list) to `_tileRow` instead of `recentlyAdded`. The section heading therefore
  does not necessarily describe its contents.
- **Affected platform:** Flutter tablet layout.
- **Affected core/system:** None.
- **Reproduction:** Open a tablet-sized library with a non-empty library and a
  system/search filter, then inspect the “Recently added” row.
- **Severity:** Medium — visible library metadata is misleading.
- **Workaround:** Clear filters or use the desktop/phone collection until the
  data path is reconciled.
- **Verification:** `test/library_layouts_test.dart` now applies a tablet
  search and verifies that the Recently added row remains an import-order
  snapshot rather than duplicating the filtered collection.
- **Status:** Resolved; the section now renders `recentlyAdded`.
- **Follow-up:** Keep the section contract explicit if its source data changes.

### EZC-012 — Theme helper splits paths only on `/`

- **Description:** The new `_systemNote` helper uses
  `g.filePath.split('/')`, which does not extract the filename from a native
  Windows path. A Windows library tile can therefore display a full path in
  its footnote.
- **Affected platform:** Windows Flutter UI.
- **Affected core/system:** None.
- **Reproduction:** Display a game whose `filePath` uses `\\` separators in a
  tablet/portrait tile.
- **Severity:** Low/Medium.
- **Workaround:** None needed for core execution; presentation is misleading.
- **Verification:** `test/library_layouts_test.dart` now supplies a native
  Windows path and verifies that only `windows-demo.gcm` is displayed.
- **Status:** Resolved; display parsing normalizes both path separators without
  changing the persisted `GameEntry` format.
- **Follow-up:** Reuse the same display-only parsing if another tile exposes a
  path.

### EZC-013 — Resolved: design slice is formatted

- **Description:** The installed Dart formatter initially wanted to reformat
  most of the design slice. The slice was formatted deliberately, without a
  repository-wide rewrite; the focused check is now clean.
- **Affected platform:** Flutter source formatting gate.
- **Affected core/system:** None; design-owned Dart files.
- **Verification:** `dart format --output=none --set-exit-if-changed` on the
  design slice reports `0 changed`.
- **Status:** Resolved for the replacement stack.

### EZC-014 — Resolved: Linux backdrop wash

- **Description:** A real Linux debug run exposed a renderer-specific pale
  wash from very large stroked planet circles. The scene now uses sampled
  orbital paths and viewport-local gradients, and the actual Linux build was
  visually checked after the fix.
- **Affected platform:** Linux desktop renderer.
- **Affected core/system:** None; background presentation only.
- **Verification:** Linux debug build launched and captured successfully; the
  full Flutter suite and analyzer remain green.
- **Status:** Resolved for the replacement stack.

## Known limitations that are not defects

- No ROMs, BIOS, firmware, keys, or proprietary content are distributed.
- Cloud sync, accounts, telemetry, achievements, netplay, shaders, mods,
  theme packages, and a marketplace are not current features.
- Local save states are opaque core bytes; ezCORE does not guarantee that a
  state from one core version loads in another.
- The roadmap is a plan, not evidence of implementation.

## Technical debt (not fixed in passing)

- **Broken relative links in the AI agent profile files** (observed 2026-09-26,
  pre-existing). `.github/copilot-instructions.md`, `.cursor/rules/ezcore.mdc`,
  `.codex/instructions.md`, `.windsurf/rules/ezcore.md`, and
  `.continue/rules/ezcore.md` link `project.md`, `README.md`, `CHANGELOG.md`,
  `docs/ARCHITECTURE.md`, and `docs/MATRIX.md` as if those files were siblings,
  but the files live in nested directories, so the targets do not resolve. The
  platform-program links added on 2026-09-26 are depth-correct; the older links
  were left alone rather than folded into a documentation task. Fix is a
  one-pass rewrite of the link prefixes per file. Suggested gate: a repository
  link checker in `scripts/` alongside the existing content, license, and
  artwork gates, so this class of rot is caught mechanically.
- **`runtime/src/runtime.c` exports internal dynload symbols.**
  `ez_dyn_open`, `ez_dyn_sym`, and `ez_dyn_close` are declared internal to
  `dynload.h` but appear as exported `T` symbols in the built runtime library
  (ABI hygiene, low severity). Fix belongs in the P8 renderer/runtime task, not
  in a documentation change.


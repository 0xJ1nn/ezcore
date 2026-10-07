# ezCORE Current Task

## Active task record

- **Milestone:** Phase 0 — project control and public communication
- **Task:** Responsive Orbit/cover-flow replacement stack closeout
- **Status:** Complete — replacement PRs #29 and #30, plus topology integration
  PR #31, are merged into `main`; local gates and independent review are green
- **Date:** 2026-09-25
- **Merged pull requests:**
  - [#29](https://github.com/0xJ1nn/ezcore/pull/29) — artwork,
    provenance, compact-shell evidence, and base repair
  - [#30](https://github.com/0xJ1nn/ezcore/pull/30) — signed cover-flow
    hardening on the stacked base
  - [#31](https://github.com/0xJ1nn/ezcore/pull/31) — child-delta
    integration into `main` after the stacked merge topology was resolved
- **Base commits:** `a3b3ee7`, `d82b4cd`, `4017681`
- **Child implementation/evidence commits:** `93a7f29`, `8e0311e`, `da89f77`, `588dff9`

## Objective

Deliver the responsive Orbit shell as two clean, reviewable, DCO-signed
replacement branches. The base branch establishes the reviewed core-artwork
surface and compact evidence; the child branch hardens Library cover flow
without changing the runtime/core boundary.

## Scope

### In scope

- Five responsive layout families: desktop, tablet landscape, tablet portrait,
  phone landscape, and phone portrait.
- Desktop and phone cover flow with keyboard, pointer, wheel, reduced-motion,
  grid round-trip, and accessibility coverage.
- Continue/Recently Added tablet hub behavior, including empty filtered views.
- Compact shell padding, rail hit targets, carousel/index synchronization,
  screenshot-cover refresh, and stale-search clearing.
- Project-generated WebP artwork, exact provenance/file/pin verification, and
  release decode documentation.
- Sanitized Linux screenshots, README/roadmap alignment, and project-state
  memory.

### Out of scope

- Runtime ABI, native execution, core behavior, or dependency changes.
- ROMs, BIOS/firmware, keys, commercial artwork, or proprietary game content.
- New platform claims or device/gameplay claims beyond the evidence recorded in
  [`../docs/MATRIX.md`](../docs/MATRIX.md).

## Acceptance criteria

- [x] Tablet landscape and tablet portrait retain the focused
  Continue/Recently Added hub.
- [x] Desktop and phone cover flow show neighboring covers and preserve the
  selected game through grid round trips, removal, and collection changes.
- [x] Compact phone/landscape shells and short rail targets have regression
  coverage.
- [x] Mouse-wheel input over the shelf does not also scroll the enclosing dock.
- [x] Screenshot pinning invalidates both the service lookup and mounted cover
  image cache.
- [x] Invalid persisted layout and cover-flow preferences fail safely.
- [x] Core artwork has a maintainer-reviewed ChatGPT Images/Codex provenance
  statement, exact flat WebP file-set gate, SHA-256 pins, and decode test.
- [x] Public screenshots match the current Linux shell and use only temporary
  public-domain/local fixture data outside the repository.
- [x] README, roadmap, changelog, and `.ezcore/` state describe the current
  five-layout evidence rather than the superseded PR candidate.

## Verification

- `flutter analyze`: **No issues found** (`18.3s`).
- `flutter test --no-pub`: **441 passed, 15 skipped, 0 failed**.
- `ctest --test-dir runtime/build-linux --output-on-failure`: **3/3 passed**.
- `flutter build linux --debug`: **passed**.
- `flutter build apk --debug`: **passed**; device boot remains unverified.
- `python3 scripts/fill_manifest_data.py --check`: **passed**.
- `python3 scripts/license_audit.py`: **passed**.
- `python3 scripts/verify_core_art.py`: **passed**.
- `bash scripts/banned_content_scan.sh`: **passed**.
- Focused Dart format checks: repaired files report no changes. The existing
  `player_screen.dart` formatting debt is outside this slice and was not
  reformatted wholesale.
- Linux captures were visually reviewed for desktop Library, Systems, Capsule,
  Settings, and an 834×700 tablet hub. Capture data stayed outside the repo.

## Completion record

The base branch now closes the artwork provenance set boundary, verifies every
flat WebP file, documents the release decode gate, aligns compact Library
padding with the shell, and adds real compact-shell/Vault/artwork regression
coverage. The child branch adds the cover-flow state machine and responsive
hardening, including the five-layout contract and the tablet hub guarantee.
Follow-up review also added a revision-keyed mounted-cover rebuild and a
same-path screenshot-cache regression test.

The old pushed PR candidates were superseded rather than rewritten. The
replacement stack was reviewed in order: #29 merged the artwork/evidence base,
#30 merged the child into the stacked base, and #31 replayed only the child
delta onto `main`. The old #27/#28 candidates are closed.

## Next logical task

M0 closeout is complete. The next task is **P1a of the platform program**
recorded in [`../ROADMAP.md`](../ROADMAP.md) and governed by
[`../docs/PLATFORM.md`](../docs/PLATFORM.md):

1. **P1a — documentation truth.** Correct `docs/API.md` and
   `docs/ARCHITECTURE.md` against the source, and add the header-symbol
   documentation coverage test. Defect list: `docs/PLATFORM.md` §8.
2. **P1b — core options and capability surface** in `env_cb`, additively.
3. **P1c — core authoring documentation** for third-party core authors.

The previous "M1 capability-contract research" item is absorbed into P1b.
**Do not expand the responsive shell scope. Do not start platform items P2–P9
before their stated gate.** P6, P8, and P9 must not start before P1 lands and
the blocked cores in [`../docs/MATRIX.md`](../docs/MATRIX.md) reach `RENDERS`.

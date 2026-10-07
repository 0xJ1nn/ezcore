# ezCORE PR / Commit Log

> Chronological development memory for meaningful, reviewed changes.
> Entries below are based on the current git history and changelog. The
> current merged replacement stack is recorded here; local-only guidance is
> intentionally omitted.

## Replacement stack — 2026-09-25 — responsive Orbit/cover-flow stack (merged)

- **Objective:** Replace the superseded Orbit PR candidates with two clean,
  DCO-signed branches: reviewed core artwork/evidence first, then Library
  cover-flow hardening.
- **Base branch:** `feat/core-artwork-responsive-v2` at `4017681` on top of
  `a3b3ee7` and `d82b4cd`. It adds exact flat-WebP provenance enforcement,
  release/decode documentation, shared compact padding, short-shell/Vault
  coverage, and the artwork cache-cap regression.
- **Child branch:** `feat/library-coverflow-hardening-v2` on top of `8e0311e`
  and `93a7f29`. It hardens the cover-flow lifecycle, filters, input, reduced
  motion, compact phone layouts, rail targets, screenshot-cover refresh,
  tablet hub behavior, and the public evidence checkpoint.
- **Documentation/evidence:** README, roadmap, changelog, `.ezcore/` state,
  and sanitized Linux captures now describe five layout families. Captures use
  temporary SameBoy/local save data outside the repository. Follow-up review
  added a revision-keyed same-path screenshot-cover cache regression.
- **Verification:** `flutter analyze` clean; `flutter test --no-pub` **441
  passed / 15 skipped / 0 failed**; Linux CTest **3/3**; Linux debug build
  passed; Android debug APK build passed; manifest, license, artwork,
  provenance, banned-content, and whitespace gates passed.
- **Result:** PR [#29](https://github.com/0xJ1nn/ezcore/pull/29) merged
  the artwork/evidence base into `main`; PR
  [#30](https://github.com/0xJ1nn/ezcore/pull/30) merged the reviewed
  child into the stacked base; PR
  [#31](https://github.com/0xJ1nn/ezcore/pull/31) replayed only the
  child delta into `main`. Independent review found no blocking defect. Old
  PRs #27 and #28 were closed as superseded after the replacement PRs opened.

## Historical PR candidate — 2026-09-24 — Orbit redesign and public front door

- **Objective:** Integrate the completed studio-plate Orbit redesign with the
  evidence-backed README, authoritative roadmap, architecture notes, and
  project-state memory.
- **Design commits:** `0f68fa0` (`feat(ui): match the studio-plate redesign
  across all four layouts`) and `7136f11` (palette provenance correction).
- **Documentation/state scope:** `README.md`, `ROADMAP.md`, selected `docs/`
  cross-references, agent reconnaissance pointers, and `.ezcore/` state memory.
  The local editorial guide remains ignored and is not part of the PR.
- **Verification:** `flutter analyze` — no issues (`61.0s`);
  `flutter test --no-pub` — 396 passed, 15 skipped, 0 failed; Linux CTest —
  3/3 passed; Linux debug build — passed; Android debug APK build — passed;
  focused Dart format check — 0 changed; README/local Markdown links —
  passed.
- **UI fixes:** Favorites chip filtering, global Recently added semantics,
  Windows filename display, a renderer-safe animated ORBIT backdrop, and real
  Linux captures using temporary SameBoy/local test data.
- **Result:** PR candidate ready for maintainer review and merge. No
  platform/device claims beyond the canonical matrix are implied.

## 2026-09-23 — `1b3b15d` / #22

- **Objective:** Introduce hybrid core delivery (ADR-013): bundle ordinary
  cores and explicitly download large desktop giants.
- **Modules affected:** Core manifests/catalog, release metadata, downloader,
  staging/discovery, licensing/pre-commit checks, release packaging.
- **Tests/evidence recorded by the project:** Flutter gates reported
  `354 passed / 15 skipped / 0 failed`; policy, license, pin, and banned-content
  checks were green. Cross-platform builds were not verified on the authoring
  host.
- **Result:** Delivered and released as v0.2.0 scope.
- **Follow-up:** Verify each platform's release asset and runtime behavior;
  do not treat a download unit test as a device acceptance test.

## 2026-09-23 — `9fc2871` / #21

- **Objective:** Close manifest/policy drift for Gambatte delivery and run the
  manifest policy gate in the pre-commit hook.
- **Modules affected:** `scripts/fill_manifest_data.py`, `.githooks/pre-commit`.
- **Tests/evidence recorded:** Policy check and related manifest tests.
- **Result:** Delivered.
- **Follow-up:** Keep policy checks green when adding or changing a core.

## 2026-09-23 — `6c9af64` / #24

- **Objective:** Publish v0.2.0 release notes and attached package/checksum
  information with honest platform limitations.
- **Modules affected:** Release notes, checksums, release documentation.
- **Tests/evidence recorded:** Release metadata review; not a new emulator
  implementation.
- **Result:** Documentation/release checkpoint.
- **Follow-up:** Refresh the canonical matrix when a platform artifact is
  actually built and exercised.

## 2026-09-23 — `3cd42d5` / #23

- **Objective:** Establish the smallest-step versioning rule and immutable
  published-tag policy.
- **Modules affected:** `project.md`, versioning/release documentation.
- **Tests/evidence recorded:** Documentation review.
- **Result:** Delivered.
- **Follow-up:** Any future version bump must update all release surfaces
  together.

## 2026-09-23 — `15f7f9b` / #13

- **Objective:** Harden ROM import with catalog-driven extension matching,
  content plausibility checks, and duplicate handling.
- **Modules affected:** Content importer, ROM validator, import UI, tests.
- **Tests/evidence recorded:** Catalog sweep and importer regression tests.
- **Result:** Delivered.
- **Follow-up:** Keep validation conservative for new formats; do not reject
  legitimate headerless media without evidence.

## 2026-09-23 — `c99e85e` / #18

- **Objective:** Make license/provenance wording consistent across the
  repository and keep the license audit gate explicit.
- **Modules affected:** Documentation, audit scripts, notices.
- **Tests/evidence recorded:** License audit and documentation review.
- **Result:** Delivered.
- **Follow-up:** Review provenance before any external core or asset is added.

## Superseded handoff — 2026-09-23

- **Objective:** Establish the root roadmap and `.ezcore/` state memory from
  the current repository audit.
- **Modules affected:** Documentation and state files only.
- **Tests:** The latest combined read-only evidence includes one analyzer
  warning followed by an inconclusive timeout, a first full Flutter run with
  373 passed, 15 skipped, and 10 failed, targeted theme reruns passing while
  edits were still active, and Linux CTest 3/3.
- **Result:** Documentation task complete; combined code baseline remains open.
- **Follow-up:** Theme-track stabilization and integration review in
  `CURRENT_TASK.md`.

## Superseded handoff — 2026-09-23 (README rebuild)

- **Objective:** Replace the stale product-heavy README with a brand-forward,
  exciting, evidence-backed project front door.
- **Modules affected:** `README.md` and roadmap/state memory.
- **Research:** GitHub README guidance plus public patterns from RetroArch,
  mGBA, RetroPie, Zed, and Bun; no external text or assets copied.
- **Validation:** Local README links and README whitespace checks passed. No
  code tests were run because the active theme track remains independently
  unverified.
- **Result:** README now covers current capabilities, boundaries, downloads,
  source builds, core evidence, contribution rules, licensing, and optional
  GitHub Sponsors support.
- **Follow-up:** Theme-track stabilization and integration review, then the
  capability-contract milestone.

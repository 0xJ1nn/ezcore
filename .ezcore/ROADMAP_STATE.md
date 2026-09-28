# ezCORE Roadmap State

> Snapshot date: 2026-09-25
> Canonical roadmap: [`../ROADMAP.md`](../ROADMAP.md)
> Release evidence: [`../docs/MATRIX.md`](../docs/MATRIX.md)

## Current milestone

**M0 — Project control and baseline** — `[x] Complete`

The replacement stack now has a long-term roadmap, state memory, a rebuilt
public README, real Linux UI captures, and the completed Orbit redesign merged
into `main`. PR #29 carried the artwork/provenance and compact-shell evidence
repair; PR #30 carried the cover-flow lifecycle, input, accessibility, and
responsive hardening; PR #31 replayed the reviewed child delta into `main`
after the stacked topology was resolved. Independent review found no blocking
defect. Platform/device limits remain explicitly recorded.

**Completed communication slice:** README rebuilt with the ezCORE mission,
current capabilities, dated progress stats, a Now → Next roadmap, technical
boundaries, build instructions, contribution guidance, and optional GitHub
Sponsorship support.

**Completed UI slice:** the Orbit shell now has desktop, tablet landscape,
tablet portrait, phone-landscape, and phone-portrait layouts. Desktop and phone
use the cover flow; both tablet orientations retain the focused
Continue/Recently Added hub. Shared library state, reduced-motion behavior,
compact-shell protections, and permanent layout/backdrop tests are included.

## Why the next task is first

The latest checks on 2026-09-25 observed:

- `flutter analyze`: **No issues found** (`18.3s`).
- `flutter test --no-pub`: **441 passed, 15 skipped, 0 failed**.
- `ctest --test-dir runtime/build-linux --output-on-failure`: **3/3 passed**.
- `flutter build linux --debug`: **passed**.
- `flutter build apk --debug`: **passed**; device boot remains unverified.
- Focused formatter checks: **0 changed** for the repaired files; the existing
  `player_screen.dart` formatting debt is outside this slice.
- Manifest, license, artwork provenance, WebP decode, banned-content, and
  whitespace gates: **passed**.
- Linux debug captures: desktop Library/Systems/Capsule/Settings and an
  834×700 tablet hub were visually reviewed; temporary ROM/save data stayed
  outside the repository.

The M0 code and evidence baseline is merged and independently reviewed. The next
milestone is capability-contract research; no additional responsive-shell work
is required for this closeout.

## Milestone order

> The authoritative delivery order for platform work is the **Platform program**
> in [`../ROADMAP.md`](../ROADMAP.md) (P1 … P9), governed by
> [`../docs/PLATFORM.md`](../docs/PLATFORM.md). The table below remains the
> long-range product-surface order. Where they overlap, the platform program
> wins on sequencing.

| Order | Milestone | Status | Gate |
|---:|---|---|---|
| 0 | Project control and baseline | [x] Complete | Reviewed replacement stack merged into `main` with recorded platform limits |
| 1 | Runtime and core contract (= platform program **P1**) | [~] Partially implemented | Capabilities, lifecycle, media, and config are explicit |
| 2 | Controller profiles (= **P3**, **P4**) | [ ] Planned | Hierarchical profiles and portable packages |
| 3 | Library and metadata | [~] Partially implemented | Provider-independent durable library model |
| 4 | BIOS/firmware | [~] Partially implemented | Complete manager and validation UX |
| 5 | Saves and portability (**P4**) | [~] Partially implemented | Migration, backup, and import/export tests |
| 6 | Themes and graphics (**P2**, **P4**) | [ ] Planned | Installable theme/graphics packages |
| 7 | Shaders and mods | [?] Needs research | Safe renderer and mod package designs |
| 8 | Capture, diagnostics, achievements | [~] Partially implemented | Shared service seams without provider coupling |
| 9 | Netplay and ecosystem (**P5**, **P7**) | [ ] Planned | Reviewed local-first package and transport designs |

## Platform contract (2026-09-26)

A platform audit on 2026-09-26 produced the binding contract at
[`../docs/PLATFORM.md`](../docs/PLATFORM.md) and ADR-014 … ADR-017 in
[`../docs/DECISIONS.md`](../docs/DECISIONS.md). Verified findings that now
govern sequencing:

- Cores are **libretro** plugins; the `ezcore_*` header is host-facing. The
  claim in `docs/ARCHITECTURE.md:44-46` that cores speak the runtime ABI is
  false and is corrected in platform program P1a.
- The kernel implements **7 of the 92** `RETRO_ENVIRONMENT_*` commands
  (`runtime/src/runtime.c:71-114`). This, not the UI, is the binding constraint
  on the product, and it is why several catalog cores are built but not
  frame-verified.
- Cores run **in-process**; `lib/emu/emulation_worker.dart:11-12` states that a
  native crash can terminate the app. Containment is ADR-015 / P6.
- **P6, P8, P9 are gated behind P1.** Expensive cross-platform layers built on
  an unfinished kernel contract get built twice.

## Current reality

- **Implemented foundation:** Flutter UI, C11 ABI v1, runtime lifecycle/AV/input/
  cheats/opaque states, worker-based player, local state, core catalog and
  pin verification, hybrid core delivery, import validation, BIOS presence
  guidance, local save vault, and platform input/audio seams.
- **Not implemented as a complete product:** capability discovery, full
  configuration hierarchy, metadata providers, controller profiles, theme or
  graphics packages, shaders, mods, achievements, netplay, recording/replay,
  centralized diagnostics, cloud sync, and most multi-disc/community workflows.
- **Verification is uneven:** macOS has the strongest evidence; Linux/Windows
  and mobile artifacts have different evidence; most cores identify or build
  but do not have verified gameplay. See the canonical matrix, not this
  summary, for per-platform claims.

## Next logical task

**P1a — documentation truth** (platform program, `ROADMAP.md`). Correct
`docs/API.md` and `docs/ARCHITECTURE.md` against the source, and add the
header-symbol documentation coverage test so the drift cannot recur. The full
defect list is [`../docs/PLATFORM.md`](../docs/PLATFORM.md) §8. Documentation
and one test only — no runtime, no UI, no feature work.

Then **P1b — core options and capability surface**, then **P1c — core authoring
documentation**.

`M1 capability-contract research` is absorbed into P1b: the smallest capability
object and the configuration hierarchy are both part of finishing what the
kernel can offer a core. Structured diagnostics (former M1-03) is tracked under
P5.

## State-file maintenance rule

After each completed task, update:

1. [`CURRENT_TASK.md`](CURRENT_TASK.md) with the result and tests.
2. [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) with newly observed failures.
3. [`CORE_MATRIX.md`](CORE_MATRIX.md) when verification evidence changes.
4. [`ARCHITECTURE_STATE.md`](ARCHITECTURE_STATE.md) when implemented boundaries
   change.
5. The root [`ROADMAP.md`](../ROADMAP.md) status and next queue.

This file is development memory, not a substitute for code or tests.

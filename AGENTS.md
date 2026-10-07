# AGENTS.md — AI & Developer Instructions

> **Canonical engineering rules:** [`project.md`](project.md) is the single source
> of truth for how ezCORE is developed. Read it before every meaningful task.
>
> This file provides the quick-reference pointers AI agents and contributors
> need at the start of a session. When anything here conflicts with
> `project.md`, `project.md` wins.

---

## Priority of authority

1. Explicit human instruction (the maintainer says so)
2. Project architecture and safety rules (what keeps the project intact)
3. Canonical ezCORE engineering policy ([`project.md`](project.md))
4. Task-specific instructions
5. Agent preferences

**An AI profile may never override explicit human instructions.**

---

## First thing every session — RECONNAISSANCE

Before changing any code for a non-trivial task, **STOP** and inspect:

- [`project.md`](project.md) — engineering governance (this is the rulebook)
- [`docs/PLATFORM.md`](docs/PLATFORM.md) — **what ezCORE is, the core/runtime/UI
  boundary, and the platform invariants that may not be broken**
- [`README.md`](README.md) — what the project is
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — how the code is laid out
- [`ROADMAP.md`](ROADMAP.md) — authoritative long-term roadmap (see **Platform
  program**) / [`docs/RELEASE_PLAN.md`](docs/RELEASE_PLAN.md) — release gates
- [`.ezcore/CURRENT_TASK.md`](.ezcore/CURRENT_TASK.md) and related state files — current task, evidence, and handoff
- `git status`, current branch, relevant source/tests

**The code is truth. Documentation can be stale. Read the code.**

---

## Platform invariants — read before touching the core boundary

ezCORE is a **modular platform**: one app, many replaceable emulator cores
(libretro plugins), from handheld to current-generation targets, added by third
parties without forking the app. ezCORE is developed with fast AI-assisted
iteration, so these fixed points are written down — a confident, well-formatted
change that violates one is a **rejected** change, not an improvement.

The full list with rationale is [`docs/PLATFORM.md`](docs/PLATFORM.md) §6. The
ones that catch agents most often:

1. **The core ABI is libretro.** A core exports `retro_*`
   (`runtime/src/runtime.c:216-225`). `runtime/include/ezcore_runtime.h`
   (`ezcore_*`) is the **host** API that Dart calls — a core never calls it.
   Never add an `ezcore_*` entry point that a core must implement. Do not design
   an ezCORE core SDK; it would orphan every existing core.
2. **Kernel growth is additive and soft-resolved.** New host functions are
   NULL-checked at every call (existing pattern: `runtime.c:456-469`).
   `runtime/test/test_core_player.c` must pass **unmodified**; if a change
   requires editing those tests to pass, the change is wrong.
3. **The kernel's missing capability surface is the binding constraint, not the
   UI.** `env_cb` implements 22 of the 93 `RETRO_ENVIRONMENT_*` commands
   (`runtime/src/runtime.c:197`). Finishing it unlocks far more than new UI
   work. Re-derive the count before quoting it:
   `grep -oE '^#\s*define\s+RETRO_ENVIRONMENT_[A-Z0-9_]+' runtime/external/libretro-common/include/libretro.h | awk '{print $2}' | sort -u | wc -l`
   for the denominator (anchor on the `#define`: a plain substring grep also
   matches doc-comment references, which inflated an earlier count to 96), and
   `grep -oE 'case RETRO_ENVIRONMENT_[A-Z0-9_]+' runtime/src/runtime.c | sort -u | wc -l`
   for the numerator.
4. **No core-name branching in the Flutter layer.** Per-core quirks belong in
   `runtime/src/` with a comment naming the cause (one exists today:
   `runtime.c:272-287`). `if (coreId == ...)` in UI is forbidden.
5. **Capability before content.** Do not add a console or system to the catalog
   until the kernel can run and verify it.
6. **Package data never executes code.** Control layouts, skins, cheats, and
   presets are JSON: schema-validated, size-capped, path-confined, no symlinks,
   no fetched URLs, unknown fields rejected.
7. **Untrusted native code is opt-in, labelled, and never auto-updated.**
   Running unknown native code cannot be made safe — say so, never imply
   otherwise. Never hand-roll cryptography.
8. **Local-first.** ezCORE must stay fully usable with no account and no
   network. A remote registry is additive, never required.
9. **Never knowingly break a save.**

**Before proposing a change to the core/runtime/UI boundary, state which
invariant it touches.** If it touches one, it needs an ADR in
[`docs/DECISIONS.md`](docs/DECISIONS.md) and explicit maintainer approval
(`project.md` §1, §65). Decisions of record: ADR-014 (libretro stays), ADR-015
(crash containment), ADR-016 (self-serve + Verified tiers), ADR-017 (Tier-2
engines are supervised, not embedded).


**The code is truth. Documentation can be stale. Read the code.**

---

## Scope & discipline rules (short form)

- **ONE task at a time.** One problem → one plan → one branch → one PR.
- **SCOPE LOCK.** Define what is and isn't in scope before starting.
- **NO unrelated refactoring.** Fix what was asked. Don't touch other systems.
- **Investigate first, code second.** Read-only pass before editing.
- **Smallest safe change.** No speculative abstractions, no premature optimization.
- **Existing functionality is sacred.** Don't change working interfaces without understanding who depends on them.
- **Core isolation.** Cores never touch Flutter. Runtime owns execution. The ABI is the boundary.
- **Respect the platform gates.** Platform program items P5–P9 must not start
  before their stated predecessor in [`ROADMAP.md`](ROADMAP.md). Large
  expensive layers built on an unfinished kernel contract get built twice.

---

## Testing discipline

- New code ships with a failing-first test (`flutter test` / `ctest`).
- A bug that can be reproduced gets a regression test.
- **Test before AND after implementation.** Run relevant suites, `flutter analyze`, `flutter test`.
- If a test fails, **explain WHY** — don't just edit tests until they pass.
- Per-core boot tests **fork()** so a native crash can't kill the harness.

---

## Git workflow

- `main` is the known-good branch. Never develop directly on it.
- Use feature/fix branches: `feat/<thing>`, `fix/<bug>`, `test/<area>`, `docs/<what>`.
- Commits are logical and well-named: `fix: prevent save-state corruption during shutdown`
- Every meaningful change uses a **Pull Request**, even for a solo maintainer.
- PR merge requires: scope correct, tests pass, diff clean, **maintainer approves**.

---

## Release discipline

- Version follows [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`
- [`CHANGELOG.md`](CHANGELOG.md) records user-facing changes
- [`docs/MATRIX.md`](docs/MATRIX.md) records what's actually verified per platform
- Don't release directly from an unreviewed branch
- What you couldn't verify, **don't claim works** — say "not verified"

---

## What AI must NOT do silently

- Make major architectural, product, UX, compatibility, licensing, dependency, or scope decisions
- Invent a new core ABI, or add a core-facing `ezcore_*` function
- Weaken a platform invariant in [`docs/PLATFORM.md`](docs/PLATFORM.md) §6
- Start a platform program item (P2–P9) before its stated gate in [`ROADMAP.md`](ROADMAP.md)
- Add a console, core, or system to the catalog before the kernel can run and verify it
- Branch on core identity in the Flutter layer
- Execute untrusted native code, or imply that running it is made safe
- Hand-roll cryptography
- Make ezCORE require an account or a network connection
- Add a package format that can execute code, fetch URLs, or escape its directory
- Copy external code without license/provenance checks
- Change generated files (change the source instead)
- Execute destructive commands (`rm`, `git reset --hard`, force push) without explaining first
- Rewrite files, configs, or lockfiles unrelated to the task
- Remove copyright notices or modify licenses
- Override human instructions
- Commit scratch agent tooling — screenshot drivers, input injectors, capture helpers, probe scripts go in /tmp only, are wiped when the task ends, and are never committed; only real permanent tests live in `test/` (project.md §79)
- Push AI-generated doc clutter — session notes, status/summary/plan files — without explicit maintainer approval; verify every push file-by-file (`git status --short`, `git diff --stat`, commit list) and list exact files pushed (project.md §80)

---

## Teaching rule

The maintainer is actively learning professional software engineering.
For every important technical decision:

1. **Explain the problem** in simple language
2. **Explain what the current system does**
3. **Explain the proposed change**
4. **Explain WHY** it's being proposed
5. **Explain what could break**
6. **Explain alternatives**
7. **Explain how we'll test it**
8. **Ask for direction** when the decision is significant

**The objective: improve ezCORE while making the maintainer progressively better at it.**

---

## Model honesty

- Never fabricate test results, build results, benchmarks, compatibility claims, or code you didn't inspect
- When uncertain, **say so** — "I found two plausible interpretations" rather than guessing
- Two AIs agreeing does **not** mean it's correct — evidence comes from tests and runtime behavior
- If an AI starts oscillating/patching repeatedly without converging, **STOP**, revert to known-good, and restart with investigation

---

## Cross-tool safety

One active implementer per branch. Don't let multiple agents (Hermes + OpenCode) edit the same files simultaneously.

---

> **Remember:** "How much reliable progress can we make today without damaging what already works?"

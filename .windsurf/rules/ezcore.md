# Windsurf Rules — ezCORE

- `../../docs/PLATFORM.md` — the platform contract: what ezCORE is, the
  core/runtime/UI boundary, the package format, the security model, and
  the **platform invariants that may not be broken**
> **Canonical engineering rules:** [`project.md`](project.md) is the single source
> of truth for how ezCORE is developed. Read it before every meaningful task.
>
> This file provides instructions for Windsurf Cascade in this repository.
>
> When anything here conflicts with `project.md`, `project.md` wins.

---

## Priority of authority

1. Explicit human instruction (the maintainer says so)
2. Project architecture and safety rules
3. Canonical ezCORE engineering policy ([`project.md`](project.md))
4. Task-specific instructions
5. Agent preferences

**An AI profile may never override explicit human instructions.**

---

## First thing every session — RECONNAISSANCE

Before changing any code for a non-trivial task, **STOP** and inspect:

- [`project.md`](project.md) — engineering governance (this is the rulebook)
- [`README.md`](README.md) — what the project is
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — how the code is laid out
- [`ROADMAP.md`](../../ROADMAP.md) — authoritative long-term roadmap / [`docs/RELEASE_PLAN.md`](../../docs/RELEASE_PLAN.md) — release gates
- `.ezcore/CURRENT_TASK.md` and related state files — current task, evidence, and handoff
- `git status`, current branch, relevant source/tests

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

One active implementer per branch. Don't let multiple agents (Hermes + OpenCode + Windsurf) edit the same files simultaneously.

---

> **Remember:** "How much reliable progress can we make today without damaging what already works?"

# ezCORE Package Platform — Master Prompt

> **Purpose.** This document is the standing brief for any agent, harness, or
> contributor working on ezCORE's core-package platform: the work that turns
> ezCORE from an emulator into an operating system for emulated games — where
> cores are installable like apps (`.apk` on Android, `.exe` on Windows), a
> crashing core never takes the system down, and the supported spectrum runs
> from 8-bit classics to current-generation consoles.
>
> The maintainer is the final authority. This prompt never overrides
> `project.md`, the platform contract (`docs/PLATFORM.md`), or explicit human
> instruction.

---

## 1. The vision, stated once

**ezCORE is an operating system for emulated games.**

- One application. Many independent emulator cores. Installing a core is an
  install, not a rebuild — like installing an app.
- **A crashing core is a contained crash.** The system survives; the user
  loses a session, not their library, saves, or settings.
- The spectrum is deliberate: **simple and old** (8-bit consoles — working
  today), **mid** (16-bit, disc, handheld-3D — capability now landed, games
  verifying), **futuristic** (current-generation consoles and PC-game engines
  — supervised, not embedded).
- Local-first, always. No account, no telemetry, no network requirement. The
  package system must work fully offline from a folder on disk.

## 2. The architecture truth (do not break these)

The binding contract is `docs/PLATFORM.md` §6. The ones that decide package
work:

1. **The core interface is libretro.** Cores export `retro_*`. The ezcore
   runtime ABI (`runtime/include/ezcore_runtime.h`) is host-facing only. No
   private core SDK, ever — that orphans every existing core.
2. **Kernel growth is additive and soft-resolved.** New capability is
   NULL-checked at every call. `test_core_player.c` passes unmodified.
3. **Package data never executes code.** Everything in a package that is not
   the core library itself is data: schema-validated, size-capped,
   path-confined, no symlinks, no fetched URLs, unknown fields rejected.
4. **Untrusted native code is opt-in, labelled, and never auto-updated.** A
   package install that adds native code requires explicit user consent in
   the UI, states the trust level plainly, and never updates silently.
5. **Never knowingly break a save.** Installing or upgrading a core must not
   destroy existing saves for that system.
6. **No core-name branching in the UI.** Per-core quirks live in the runtime.

## 3. The package format (v1)

A package is a directory (or a zip of one) with this shape:

```text
<core-id>/
  manifest.json          # the single source of truth — validated, versioned
  <core-id>.so|.dylib|.dll   # the core library (per-platform artifacts)
  info/
    <core-id>.info       # libretro metadata (parsed, never executed)
  options/               # (future) shipped default option presets — JSON only
  layouts/               # (future) control layouts — JSON only
  cheats/                # (future) cheat definitions — JSON only
```

**manifest.json** — schema as enforced today by
`lib/services/core_package_validator.dart`:

- `id`: `[a-z0-9_]+`, matching the directory name.
- `name`, `version`, `license`, `license_url`, `homepage`, `upstream`.
- `systems`, `extensions`: what it runs and what files it accepts.
- `delivery`: per-platform map — `bundled | download | absent` (the app's
  vocabulary; iOS is `bundled` or `absent` only, never `download` — App
  Review 2.5.2/4.7).
- `artifacts`: per-platform sha256 pins of the exact library bytes.
- `bios_required`, `bios_files`, `bios_notes`: the BIOS contract. **The
  project never ships or fetches BIOS/ROMs — the user supplies their own
  dumps from hardware they own, placed in the app's system directory.**
- `execution`, `cheats_supported`, `cheat_families`, `provenance`,
  `blocked_reason` / `gated_reason` (policy holds), `notes`.
- Unknown top-level fields are rejected (the schema is strict on purpose).

**The install contract:**

1. Parse (`.info` via `lib/services/retro_info_parser.dart`).
2. Validate (`lib/services/core_package_validator.dart` — 21 real manifests
   must validate; the test `every committed manifest in cores/ validates` is
   the standing mutation test).
3. Verify pins (sha256 of the actual library against the manifest pin).
4. Stage into the vault with the user's explicit consent (native code is
   opt-in).
5. Register into the catalog (merged via `scripts/build_catalog.py` rules).
6. Trust label: **ezCORE Verified** (reviewed) vs **Unverified** (labelled,
   opt-in, never auto-updated) — the P5 tiers.

**The signature slot (P7):** package *manifests* carry no signature in v1
  (the field is rejected as unknown — registry-level signing, `cores/registry.json`,
  arrives with P7). Installing unsigned packages is consent-gated and
  labelled Unverified. Never hand-roll crypto.

## 4. Crash containment (the "OS" promise)

Decided architecture (ADR-015): **crash isolation is process isolation.** The
long-term shape is each core session executing behind a supervised boundary
(forked/supervised process or equivalent), so a segfault in a core — which
cannot be caught in-process — becomes a session failure the UI reports, not
an app death. Until P6 lands, the runtime's own hardening (bounds-capped
storage, soft-resolved env handling, NULL-safe teardown) reduces but does not
eliminate blast radius — say so honestly when asked.

The watchpoints this work must respect: the emulation worker isolate owns the
session (`lib/emu/emulation_worker.dart`); frames/PCM travel the message
protocol; save data and the library live outside any core's reach.

## 5. The console spectrum ladder

| Tier | Class | Kernel requirements | State |
|---|---|---|---|
| T1 | 8-bit (GB/GBC/GBA/NES/2600) | env basics, input, saves | **Working** — boot-verified |
| T2 | 16-bit (SNES/Genesis), handheld-3D (DS), DOS | core options, controller info | Capability landed (P1b); per-system verification ongoing |
| T3 | Disc/3D (PS1/N64/Saturn/Dreamcast/Cube/PSP) | everything in T2 **+ GPU video path (P8)** + analog input (P3) | Blocked on P8 |
| T4 | Current-gen (PS2 needs T3 + stronger GPU path; Switch/3DS remain **legal holds**) | P8, crash containment (P6), supervision (P9) | PS2 = planned via LRPS2/PCSX2; Switch/3DS = holds |

**Current-generation truth:** PS3/PS5-class emulation means either licensed
compatibility layers (none exist) or supervised PC-engine work (P9). Switch
and 3DS stay under legal holds — never built, never shipped, and their holds
are enforced by manifest policy (`blocked_reason`) and the pre-commit hook.

## 6. The PS2 case (the concrete plan)

1. **License gate:** the libretro core is **LRPS2** (renamed from lr-pcsx2 at
   the PCSX2 team's request — respect that). Verify the LICENSE at the pinned
   commit reads GPL-2.0-**or-later** (compatible with the app's GPL-3.0-only
   via the or-later grant); GPL-2.0-only would be incompatible and cannot
   ship.
2. **GPU path (P8) first:** PS2's GS needs hardware rendering (or Play!'s
   software GS at painful speed). P8 is the real prerequisite.
3. **Input (P3):** DualShock analog mapping.
4. **BIOS:** **user-supplied only.** The core, the manifest, the docs, and
   the BIOS-placement UX all assume the user dumped their own BIOS from
   their own console. The repo contains no BIOS bytes, ever (enforced by
   `scripts/banned_content_scan.sh` and this document).
5. **Then:** recipe in `scripts/build_core.sh`, manifest with
   `gated_reason` cleared, T3/T4-tier kernel evidence, boot test with the
   user's own BIOS outside the repo.

## 7. Working rules (unchanged, restated because they decide merges)

- Issue first → branch → test → PR → maintainer's explicit go → merge. Never
  develop on main. Never merge without it (except a maintainer-delegated
  caretaker with verification recorded per PR).
- **No fabricated anything**: no invented flags (the `release.sh --static`
  lesson), no invented test results, no invented compatibility claims. Every
  number grep-reproducible.
- One task → one branch → one PR. Smallest safe change. No unrelated
  refactoring.
- Free models only for delegated agents. Never trust a child's self-report —
  re-run the gates; a child's own-file green is not a suite green; run the
  full suite before any merge.
- Nothing stupid written anywhere: the repo is public; docs are professional,
  honest about limits, and kind to the next reader.
- No ROMs/BIOS/keys/game files, ever, anywhere — including "just for testing".

## 8. The immediate work queue (in dependency order)

1. **P2 integration** — wire the parser + validator into discovery/install;
   the package format v1 lands as `docs/PACKAGE_FORMAT.md`; install-from-disk
   with consent; the catalog registers packages.
2. **P6-lite** — process isolation spike for the emulation session (the OS
   promise).
3. **P3** — analog input.
4. **P8** — GPU video path (unblocks T3; the PS2 gate).
5. **PS2 core** — per §6, after its prerequisites.
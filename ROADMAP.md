# ezCORE Living Roadmap

> **Status:** authoritative long-term roadmap for ezCORE.
> **Last audited:** 2026-09-25.
> **Current release:** `v0.2.0` (public, experimental).
> **Current repository state:** the replacement stack is open for review in
> stacked PRs [#29](https://github.com/JinUltimate1995/ezcore/pull/29) and
> [#30](https://github.com/JinUltimate1995/ezcore/pull/30): the base PR carries
> the artwork/compact-shell evidence repair, and the child PR adds the signed
> cover-flow hardening and public evidence refresh. Flutter, Linux native,
> provenance, Linux debug, and Android debug gates are green on this checkout;
> maintainer review, approval, and device/platform verification remain separate
> release gates.
>
> This roadmap describes direction, not permission to implement every item in
> one change. The code, tests, [`docs/MATRIX.md`](docs/MATRIX.md), and
> [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) are the evidence for what is
> real. Release-specific gates live in [`docs/RELEASE_PLAN.md`](docs/RELEASE_PLAN.md).

## Status key

- `[x] Complete` — implemented, integrated, tested to the stated scope, and
  documented. A complete item does **not** imply every platform or core is
  verified.
- `[~] Partially implemented` — a usable slice exists, but the full contract
  is not complete.
- `[~] Foundation only` — a seam or placeholder exists without the intended
  user-facing functionality.
- `[ ] Planned` — accepted direction, not implemented.
- `[!] Blocked` — work cannot proceed until a named dependency, policy, or
  research result changes.
- `[?] Needs research` — the design or technical evidence is not settled.

## Current milestone: M0 — Project control and baseline

**Goal:** make the repository's current state, evidence, and next task
understandable before adding another feature.

- [x] Complete — audit the implementation against the long-term product
  direction.
- [x] Complete — establish this authoritative roadmap.
- [x] Complete — create the `.ezcore/` state memory files.
- [x] Complete — rebuild the public README around the current product,
  evidence-backed capabilities, contribution paths, and sponsorship.
- [x] Complete — integrate the five-family Orbit redesign and its permanent
  layout/backdrop regression coverage.
- [~] In progress — maintainer review and sequential merge of the two signed
  replacement branches. The current checkout passes `flutter analyze`, the full
  Flutter suite (`441` passed, `15` skipped), Linux CTest (`3/3`), and
  Linux/Android debug builds; the final review covers the replacement diff and
  recorded platform limits.
- [ ] Planned — make CI/reproducible release verification a green, reviewed
  checkpoint again.

**Why this comes first:** the combined branch now has a usable, tested baseline
and sanitized visual previews, but the public claims and compatibility
boundaries still require maintainer review. Merge only after the final diff is
approved; then begin capability-contract work without letting roadmap edits
blur implementation evidence.

## Prioritized delivery phases

| Phase | Scope | Status | Exit condition |
|---|---|---|---|
| 0 | Project control, roadmap, state, test workflow | [~] Partially implemented | Clean, evidence-backed baseline and a focused next task |
| 1 | Runtime/core contract, capabilities, configuration, diagnostics | [~] Partially implemented | Core-independent lifecycle and capability seams are tested |
| 2 | Controller profiles and layouts | [ ] Planned | Global → system → core → game overrides work with portable packages |
| 3 | Library, metadata, artwork, collections, search | [~] Partially implemented | Provider-independent library model with durable local data |
| 4 | BIOS/firmware manager | [~] Partially implemented | Detection, validation, and user guidance are complete |
| 5 | Time Capsule and save portability | [~] Partially implemented | Backups, migration, thumbnails, and import/export are tested |
| 6 | Theme engine and packages | [ ] Planned | Orbit is one theme, not a hardcoded application dependency |
| 7 | Graphics packages and shaders | [ ] Planned | Renderer-independent hierarchy and packages exist |
| 8 | Mods and non-destructive overlays | [?] Needs research | Safe format, dependency rules, and sandbox policy are settled |
| 9 | Achievements, statistics, profiles, capture, diagnostics | [~] Partially implemented | Shared local services exist without hardcoded providers |
| 10 | Netplay and multiplayer | [ ] Planned | Transport-independent session layer exists |
| 11 | Platform UX | [~] Partially implemented | Responsive behavior is verified on each supported target |
| 12 | Additional cores | [~] Partially implemented | Every new core passes the shared checklist and evidence gates |

## Product roadmap

## Foundation

Architecture, runtime, abstractions, and testing.

- [x] Complete — C11 runtime with a versioned ABI v1 and libretro boundary
  (`runtime/include/ezcore_runtime.h`, `runtime/src/runtime.c`).
- [x] Complete — native lifecycle, video/audio buffers, input, cheats, and
  opaque save-state entry points, with Linux CTest coverage in the current
  checkout.
- [x] Complete — fork-isolated native boot/player tests using a deterministic
  synthetic core; per-core failures are not allowed to take down the harness.
- [~] Partially implemented — one worker isolate owns each current session,
  but native code remains in-process and the runtime has a process-global
  active-session pointer.
- [~] Foundation only — structured diagnostics, capability discovery, and
  richer media/options contracts are not yet first-class APIs.
- [ ] Planned — define a stable high-level core contract with explicit
  capability discovery and versioned compatibility rules.

## Core Infrastructure

Core API, lifecycle, capabilities, configuration, media, and input.

- [x] Complete — versioned manifests, merged catalog, license/provenance
  fields, execution policy, delivery policy, and SHA-256 artifact pins.
- [x] Complete — registry, discovery, staging, and verified local core
  resolution are isolated from Flutter widgets and have Dart tests.
- [~] Partially implemented — hybrid delivery is implemented: most cores are
  bundled and selected desktop giants can be downloaded and hash-verified.
- [~] Foundation only — the current manifest exposes feature fields, but not
  a complete runtime `CoreCapabilities` object or a full global/system/core/
  game configuration hierarchy.
- [ ] Planned — capability-aware lifecycle, media requirements, and portable
  configuration packages.

## Library

ROM scanning, metadata, artwork, collections, search, and statistics.

- [x] Complete — user-owned content import, manifest-based extension matching,
  ROM plausibility checks, SHA-256 deduplication, watched folders, favorites,
  search, and basic system filtering.
- [~] Partially implemented — local `GameEntry` data stores title, system,
  path, hash, selected core, last-played time, cheat count, and state count.
  Playtime, sessions, and a full statistics model do not exist yet.
- [~] Partially implemented — deterministic generative covers and screenshot
  pinning exist; there is no provider-independent metadata engine.
- [ ] Planned — provider adapters, local metadata cache, artwork sync,
  collections/playlists, duplicate management, and multi-disc games.

## Controllers

Universal controller framework, layouts, profiles, and sharing.

- [~] Partially implemented — physical controllers, touch controls,
  normalized button codes, and a fixed RetroPad mapping are wired.
- [ ] Planned — global → system → core → game profile hierarchy.
- [ ] Planned — custom button placement, analog sticks, triggers, gestures,
  hotkeys, rumble, orientation-specific layouts, and import/export packages.
- [ ] Planned — local controller community package format; no marketplace is
  implied.

## Themes

Theme engine, packages, and customization.

- [~] Partially implemented — Orbit's tokens and local appearance settings
  exist, but widgets and screens consume them directly.
- [ ] Planned — a theme abstraction that can control color, typography,
  spacing, cards, navigation, overlays, and optional sounds.
- [ ] Planned — versioned local theme packages with install, export, import,
  preview, and update behavior.

## Graphics

Artwork, overlays, bezels, visual packages, and UI assets.

- [~] Partially implemented — hardware art, generated covers, and screenshots
  are implemented as application features.
- [ ] Planned — graphics packages separate from themes, with manifests,
  versioning, overlays, bezels, icons, loading screens, and asset validation.
- [ ] Planned — user-selected graphics overrides without mutating game files.

## Shaders

Rendering and shader abstraction.

- [ ] Planned — a renderer-independent shader interface and global → system →
  core → game override rules.
- [ ] Planned — CRT/LCD/scanline/scaling presets, custom shader validation,
  and per-game selection.
- [ ] Planned — fallback behavior when a renderer or platform cannot run a
  requested shader.

## Saves

Time Capsule, save states, battery saves, and portability.

- [~] Partially implemented — the runtime serializes opaque state bytes and
  the local vault stores named slots with timestamps and sizes.
- [~] Partially implemented — per-game SRAM directories are handed to cores;
  content-level battery-save round trips are not yet verified for every core.
- [ ] Planned — thumbnails, save history, multiple-slot policies, automatic
  backup, restore, migration, and import/export packages.
- [ ] Planned — cloud providers; local save state remains the default.

## BIOS & Firmware

Detection, validation, requirements, and user-provided firmware.

- [x] Complete — manifests declare required files and the player reports exact
  missing filenames and the local system directory.
- [~] Partially implemented — file presence and boot gating exist; hashing,
  version/region identification, richer validation, and a dedicated manager
  are not complete.
- [ ] Planned — user-provided firmware catalog with provenance and safe
  import/export. No proprietary BIOS or keys are distributed.

## Mods

Game modifications, patches, assets, and profiles.

- [?] Needs research — settle a safe, non-executable package format,
  provenance policy, dependency/conflict rules, and non-destructive overlay
  semantics.
- [ ] Planned — texture/visual/audio replacements, translations, patches,
  widescreen layers, and per-game mod profiles.
- [ ] Planned — never modify the original ROM and never execute untrusted
  community code.

## Achievements

- [ ] Planned — provider-independent achievement model and local display.
- [ ] Planned — opt-in provider adapters such as RetroAchievements after the
  core contract is stable; no provider is hardcoded into the runtime.

## Netplay

- [ ] Planned — transport-independent session and lobby interfaces.
- [ ] Planned — local/LAN play, spectators, and eventual online transport
  only after the abstraction and privacy policy are reviewed.

## Capture

- [~] Partially implemented — screenshots can be written locally and used as
  cover art.
- [ ] Planned — a capture service independent of cores for screenshots, video,
  audio, clips, and replay capture.

## Diagnostics

- [~] Partially implemented — manifest validation, pin checks, build scripts,
  per-core matrix records, and user-facing error strings exist.
- [ ] Planned — structured diagnostics for core load, ROM validity, BIOS,
  renderer, controller, audio, video, save support, configuration, and known
  compatibility issues.

## Platform UX

- [~] Partially implemented — Flutter shells exist for macOS, Linux, Windows,
  Android, and iOS with responsive navigation and platform seams.
- [~] Partially implemented — macOS has the strongest run verification; other
  platform and device claims must follow [`docs/MATRIX.md`](docs/MATRIX.md).
- [ ] Planned — verified portrait, landscape, phone, tablet, desktop, TV, and
  handheld behavior for each supported feature.

## Core Expansion

- [~] Partially implemented — the repository contains active manifests/build
  recipes for multiple systems plus explicit held slots; only a subset is
  render-verified.
- [ ] Planned — add new cores only through the shared checklist: descriptor,
  lifecycle, capabilities, media, input, save/configuration policy, tests,
  provenance, and documentation.
- [ ] Planned — improve the shared abstraction when a new core exposes a
  weakness; do not add core-specific branches throughout the UI.

## Ecosystem

- [ ] Planned — local-first packages for themes, controllers, shaders,
  graphics, mods, profiles, metadata, settings, and saves.
- [ ] Planned — optional community sharing and updates after local package
  formats, versioning, import safety, and offline behavior are proven.
- [ ] Planned — ezCORE remains fully usable without an account, network, or
  marketplace.

## Next task queue

1. **M0-01 — Maintainer review and sequential merge:** review the two signed
   replacement branches, confirm the artwork provenance and five-layout claims,
   and merge the base branch before the cover-flow branch.
2. **M1-01 — Capability contract research:** specify the smallest capability
   object and lifecycle compatibility rules before changing the ABI.
3. **M1-02 — Configuration hierarchy:** define global/system/core/game
   precedence and migration behavior for the existing flat settings map.
4. **M1-03 — Structured diagnostics:** centralize existing errors without
   moving unrelated logic.
5. **M2-01 — Controller profile foundation:** model the override hierarchy
   before adding visual layout customization.

Each item must become a focused branch, failing-first test where applicable,
reviewable diff, and maintainer-approved PR before the next item begins.

## Evidence and change rules

- A roadmap status is updated only when source, tests, and documentation agree.
- Build, pin, boot, render, and gameplay verification are different claims.
- A core that merely compiles is not marked playable.
- ROMs, BIOS/firmware, keys, and unlicensed content never enter the repository.
- User data and save formats are treated as compatibility-sensitive.
- No roadmap item authorizes a broad rewrite or an online service by itself.

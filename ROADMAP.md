# ezCORE Living Roadmap

> **Status:** authoritative long-term roadmap for ezCORE.
> **Last audited:** 2026-09-25.
> **Current release:** `v0.2.0` (public, experimental).
> **Current repository state:** the responsive replacement stack is merged into
> `main`: PR [#29](https://github.com/JinUltimate1995/ezcore/pull/29) carried the
> artwork/compact-shell evidence repair, PR
> [#30](https://github.com/JinUltimate1995/ezcore/pull/30) carried the signed
> cover-flow hardening, and PR
> [#31](https://github.com/JinUltimate1995/ezcore/pull/31) integrated the
> reviewed child delta after the stacked topology was resolved. Flutter, Linux
> native, provenance, Linux debug, and Android debug gates are green; device
> and platform verification remain bounded by [`docs/MATRIX.md`](docs/MATRIX.md).
>
> This roadmap describes direction, not permission to implement every item in
> one change. The code, tests, [`docs/MATRIX.md`](docs/MATRIX.md), and
> [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) are the evidence for what is
> real. Release-specific gates live in [`docs/RELEASE_PLAN.md`](docs/RELEASE_PLAN.md).
>
> **Platform contract:** [`docs/PLATFORM.md`](docs/PLATFORM.md) defines what
> ezCORE is, how cores are delivered as packages, the security model, and the
> **platform invariants that may not be broken**. Decisions of record are
> ADR-014 … ADR-017 in [`docs/DECISIONS.md`](docs/DECISIONS.md). The *Platform
> program* below is the authoritative delivery order for making ezCORE a
> platform; the phase list that follows it remains the long-range product
> surface.



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
- [x] Complete — independently review and sequentially merge the signed
  replacement stack into `main`. The current checkout passes `flutter analyze`,
  the full Flutter suite (`441` passed, `15` skipped), Linux CTest (`3/3`), and
  Linux/Android debug builds; recorded platform limits remain explicit.
- [ ] Planned — make CI/reproducible release verification a green, reviewed
  checkpoint again.

**Why this comes first:** M0 is now complete: the combined branch has a usable,
tested baseline and sanitized visual previews, and its public claims and
compatibility boundaries are documented without expanding device claims. The
next task is capability-contract research, not another responsive-shell pass.

## Platform program — making ezCORE an emulator platform

**Goal:** one application that runs third-party and first-party cores as
replaceable, self-serve packages, from handheld systems to current-generation
targets, without forking the app to add a console.

**Binding contract:** [`docs/PLATFORM.md`](docs/PLATFORM.md). **Do not begin a
later item before its stated gate.**

The platform direction rests on one verified fact: ezCORE cores are already
**libretro** plugins (`runtime/src/runtime.c:216-225`), so the existing core
ecosystem is reachable by finishing the kernel rather than by writing new
cores. The kernel currently answers **22 of the 93** environment commands
(`env_cb` at `runtime/src/runtime.c:197`), which is the binding constraint on
the whole product.

> **How to re-check those two numbers** (the counts drift as the kernel grows,
> so verify before quoting them):
>
> ```bash
> # commands DEFINED by the vendored libretro header (93).
> # Anchor on the #define: a plain substring grep also matches doc-comment
> # references like \ref RETRO_ENVIRONMENT_GET_ASSET_DIRECTORY, which are not
> # real commands — that is what produced the earlier, wrong "96".
> grep -oE '^#\s*define\s+RETRO_ENVIRONMENT_[A-Z0-9_]+' \
>   runtime/external/libretro-common/include/libretro.h \
>   | awk '{print $2}' | sort -u | wc -l
> # commands the kernel actually answers (13)
> grep -oE 'case RETRO_ENVIRONMENT_[A-Z0-9_]+' \
>   runtime/src/runtime.c | sort -u | wc -l
> ```
>
> Both commands must be run against the **vendored** header
> (`runtime/external/libretro-common/include/libretro.h`). A per-core copy
> vendored under `native/src/<upstream>/` can be a different, older revision
> and will report a different total. The earlier figure in this file
> ("7 of 92") predates the vendored header and the P1b capability work
> (PRs #45/#48/#50), which added core options v2 + intl, input descriptors,
> controller info and memory maps.

| # | Item | Status | Exit condition | Gate |
|---|---|---|---|---|
| **P1** | Documentation truth + kernel core options and capability surface | [ ] Planned | `docs/API.md`/`ARCHITECTURE.md` match source; a test fails if a header symbol is undocumented; options, input descriptors, controller info and memory maps are implemented additively; the blocked cores advance in [`docs/MATRIX.md`](docs/MATRIX.md) | — (first) |
| **P2** | libretro `.info` support, core package format, package validator | [ ] Planned | A core ships as a complete validated package; existing `manifest.json` files validate unchanged | P1 |
| **P3** | Input device model — analog, mouse, lightgun, touch-to-core, multiple ports | [~] Partially implemented | Non-`RETRO_DEVICE_JOYPAD` devices reach cores; the Dart port-0 hardcode is gone | P1 |

> **P3 progress (2026-09-29, later).** A core's declared capabilities are
> now readable. `SET_CONTROLLER_INFO` was already stored and counted, but the
> per-port device types were unreachable through the ABI, so a frontend could
> learn that a core *has* ports and nothing about what they accept.
> `ezcore_get_controller_port_type_count` and
> `ezcore_get_controller_port_type` (with Dart wrappers) close that, so
> mouse and lightgun can be *offered* per port. `SET_MEMORY_MAPS` and
> `GET_MEMORY_MAPS` were already complete — a plan draft claimed both were
> missing, which was wrong.
>
> **P3 progress (2026-09-29).** The port-0 hardcode is gone: the worker button
> payload carries a port, defaults to 0, and pause releases all four
> (#68), and held input no longer survives a reset (#74) or a game load
> (#79). Stale state that used to latch a direction is flushed when a pad
> disconnects on both Windows (#75) and Linux (#76), and the poller can
> re-sync after the host drops its input (#80). Deadzone and trigger
> calibration were corrected on Windows (#77) and Linux sticks now
> calibrate from the kernel's real axis range via `EVIOCGABS` (#82); Linux
> mouse `EV_REL` deltas are decoded instead of discarded (#71).
> **Still not done, and not claimed:** true analog does not reach any core
> — `runtime/src/runtime.c` rejects every device that is not
> `RETRO_DEVICE_JOYPAD`, so P3's own exit condition is **not** met. Mouse
> and lightgun are decoded but unrouted. The `forgetHeld` seam is wired on
> Windows and Linux only.
| **P4** | Control layouts, skins, battery saves, cheat packaging | [ ] Planned | Touch layouts are data files a third party can ship with no ezCORE code; battery saves round-trip | P2, P3 |
| **P5** | ezCORE Verified list and trust tiers | [ ] Planned | Reviewed cores are labelled and updatable; unverified cores are opt-in and never auto-updated | P2, P6 |
| **P6** | Crash containment — one supervised process per core session | [~] Seam only; no transport | A deliberately crashing core does not terminate the app; library and saves survive | **P1** |

> **P6 progress (2026-09-29).** The exit-code contract is proven against a
> real SIGSEGV: `crash_core` faults on demand and `crash_signal_exit_code`
> asserts the child dies on signal 11 and is classified as 9 (#78). A
> `SupervisorSession` seam exists and `ContainmentMode` defaults to today's
> in-process path per ADR-015. **The app still dies with the core** —
> `supervisedProcess` throws `UnsupportedContainmentError` and no child
> process is ever spawned. Treat this as a spike, not as containment. The
> P6 exit condition is **not** met, and P6 remains gated on P1 regardless of
> how complete the seam looks.
| **P7** | Signature/trust hardening; make `cores/registry.json` real or remove it | [ ] Planned | Tampered packages and bad signatures are rejected by test | P5 |
| **P8** | GPU video path — `SET_HW_RENDER`, renderer abstraction, textures | [~] Context seam landed | GL-default cores render on a verified platform; the CPU path stays green | P1 |

> **P8 progress (2026-09-29).** ADR-018 is **Accepted — Option B**: the runtime
> owns its own EGL/GLES and Vulkan surfaces, and the design is platform-neutral.
> The render-context seam now exists and is verified on real hardware on the
> development host: a GLES **3.2** context on a pbuffer binds a
> `GL_FRAMEBUFFER_COMPLETE` FBO that survives a clear-and-readback, and a Vulkan
> instance, physical device, device and queue are negotiated against two live
> ICDs.
>
> `env_cb` now answers **`SET_HW_RENDER`, `GET_PREFERRED_HW_RENDER`,
`GET_HW_RENDER_INTERFACE` and `SET_PROC_ADDRESS_CALLBACK`** (coverage moves
13 -> **17 of 93**), and the core callback struct is chained rather than
overwritten so a core's own `context_reset` still runs. A synthetic core that
*requires* hardware rendering, in the shape of the six blocked ones, now
negotiates and runs against a real GLES3 context on this host.

**The six cores are still blocked, and nothing in `MATRIX.md` advances.**
Not because the negotiation is missing -- it is wired and tested -- but
because two links after it are not: the **Vulkan per-frame `set_image`
handoff** and the **Flutter external-texture presentation**. A core can
negotiate a context and render into its FBO; nothing presents that FBO to a
screen yet. Both are recorded here rather than left for someone to discover
from a black screen.

The Windows (WGL) and macOS (CGL) backends remain deliberate no-ops reporting
"unavailable", so a core falls back to software rather than crashing; the
portable Vulkan path is what carries GPU cores on those platforms.
| **P9** | Tier-2 engine supervision (current-generation console, PC-game stacks) | [?] Needs research | An external engine is launched, driven, and supervised with library/save continuity | P1, experimental |

**Sequencing rules for this program:**

- **P1 is the keystone.** Do not start P5, P6, P8, or P9 before P1 lands and
  the cores currently blocked in `MATRIX.md` reach `RENDERS`. Those four items
  are the most expensive and most cross-platform; built against an unfinished
  kernel contract, they get built twice.
- **Capability before content** ([`PLATFORM.md`](docs/PLATFORM.md) §6.6). Do not add
  a console or system to the catalog until the kernel can run and verify it.
- **Never trade the core contract for one core's convenience.** Per-core hacks
  belong in `runtime/src/` with a comment naming the cause; per-core hacks
  outside the kernel are forbidden. This is the failure mode that turns a
  platform into a pile of special cases.
- **iOS is a build-time target, not an install-time one.** iOS does not permit
  runtime loading of third-party native code. Self-serve core installation is
  not an iOS feature; do not let a plan imply otherwise.

## Prioritized delivery phases

| Phase | Scope | Status | Exit condition |
|---|---|---|---|
| 0 | Project control, roadmap, state, test workflow | [~] Partially implemented | Clean, evidence-backed baseline and a focused next task |
| 1 | Runtime/core contract, capabilities, configuration, diagnostics (= platform program **P1**) | [~] Partially implemented | Core-independent lifecycle and capability seams are tested |
| 2 | Controller profiles and layouts (**P3**, **P4**) | [ ] Planned | Global → system → core → game overrides work with portable packages |
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

Ordered by the platform program's gates. Each item must become a focused
branch, failing-first test where applicable, reviewable diff, and
maintainer-approved PR before the next item begins.

1. **P1a — Documentation truth:** correct `docs/API.md` (three documented
   `EZCORE_PIXEL_*` macros do not exist in the repository; 10 of 25 exported
   functions are undocumented; the thread-safety claim is wrong) and
   `docs/ARCHITECTURE.md` (rule 1 misstates the core ABI; the SRAM claim is
   unimplemented). Add the header-symbol coverage test. Full defect list in
   [`docs/PLATFORM.md`](docs/PLATFORM.md) §8. **No runtime or UI changes.**
2. **P1b — Core options and capability surface:** implement
   `GET_CORE_OPTIONS_VERSION`, `SET_CORE_OPTIONS_V2(_INTL)`, `SET_INPUT_DESCRIPTORS`,
   `SET_CONTROLLER_INFO`, `SET_MEMORY_MAPS` in `env_cb`, add the host-side
   option read/write surface, and land the global → system → core → game
   configuration resolver. Additive and soft-resolved only;
   `test_core_player` must pass unmodified.
3. **P1c — Core authoring documentation:** the "build, package, and declare a
   core" walkthrough third parties actually need, built on `P1a`/`P1b` and
   pointing at the libretro specification for the parts that are not ours.
4. **P2 — Packages:** libretro `.info` parsing, the package format, and the
   package validator.
5. **P3 — Input devices**; **P4 — control layouts, skins, battery saves**.
6. **M1-01 … M1-03 (earlier research items) — folded in.** Capability-contract
   research and structured diagnostics are now P1b and P5 respectively;
   configuration hierarchy is P1b. These are no longer separate tasks.
7. **M2-01 — Controller profile foundation** is covered by P3/P4.

**Held until their gate:** P5, P6, P7, P8, P9.

## Evidence and change rules

- A roadmap status is updated only when source, tests, and documentation agree.
- Build, pin, boot, render, and gameplay verification are different claims.
- A core that merely compiles is not marked playable.
- ROMs, BIOS/firmware, keys, and unlicensed content never enter the repository.
- User data and save formats are treated as compatibility-sensitive.
- No roadmap item authorizes a broad rewrite or an online service by itself.
- **The platform invariants in [`docs/PLATFORM.md`](docs/PLATFORM.md) §6 are
  binding on every task in this roadmap.** A change that breaks one is not a
  refactor; it requires an ADR and explicit maintainer approval.
- **The core ABI is libretro.** A new core-facing `ezcore_*` entry point is
  forbidden. Host-side growth is additive and soft-resolved only.
- **Read the platform contract before changing the core/runtime/UI boundary.**
  ezCORE is developed with fast AI-assisted iteration; the invariants exist
  because that speed is only safe when the fixed points are written down.

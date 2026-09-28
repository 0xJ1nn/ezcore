# ezCORE Platform Contract

> **Status:** accepted direction, 2026-09-26. Binding on all future work.
> **Canonical roadmap:** [`../ROADMAP.md`](../ROADMAP.md) — this file defines
> *what the platform is and what may never be broken*; the roadmap defines
> *what gets built and in what order*.
> **Product vision:** [`../IDEA.md`](../IDEA.md).
> **As-built implementation:** [`ARCHITECTURE.md`](ARCHITECTURE.md).
> **What is actually verified:** [`MATRIX.md`](MATRIX.md).
> **Why, per decision:** [`DECISIONS.md`](DECISIONS.md) (ADR-014 … ADR-017).

This is the document a maintainer, a contributor, or an AI agent reads before
touching the core/runtime/UI boundary. It exists because ezCORE is developed
with fast AI-assisted iteration, and fast iteration is only safe when the
things that must not change are written down somewhere a future session will
actually read.

---

## 1. What ezCORE is

**ezCORE is an operating system for emulated games, not a single emulator.**

One application. Many independent emulator cores. Each core is a replaceable
part; the platform supplies the library, the player, the controls, the
settings, the storage, and the safety rules. Adding a console must never
require forking the application.

The OS analogy is load-bearing, so it is worth being precise about which
layer is which:

| OS layer | ezCORE part | Directory |
|---|---|---|
| Shell / desktop | Orbit UI — library, systems, player, settings | `lib/screens`, `lib/widgets`, `lib/theme` |
| Userspace packages | core packages: control layouts, skins, cheat sets, presets | package data, validated (§4) |
| Package manager | discovery, validation, hashing, trust tiers, delivery | `lib/cores`, `lib/services`, `cores/` |
| System services | configuration resolver, controller profiles, save vault, diagnostics | `lib/state`, `lib/services` |
| Device drivers | video out, audio out, input in, haptics | Flutter textures, platform channels, `lib/emu` |
| **Kernel** | **ezCore Runtime — C11, session lifecycle, AV, input, options, capability** | **`runtime/`** |
| Processes | emulator cores | staged artifacts, `cores/<id>/manifest.json` |

The kernel is the part under change. Everything else must stay modular across
it.

---

## 2. The foundation is already correct — do not replace it

**Verified from source, 2026-09-26:**

- A core is a **libretro** plugin exporting `retro_*`
  (`runtime/src/runtime.c:216-225`). The runtime refuses anything where
  `retro_api_version() != 1` (`runtime.c:231-236`).
- `runtime/include/ezcore_runtime.h` (`ezcore_*`) is the **host-facing** API.
  Dart calls it. **A core never calls it.**
- The vendored `libretro.h` already defines every metadata structure the
  platform needs: `retro_core_option_value` (line 7209),
  `retro_core_option_v2_category` (7325), `retro_input_descriptor` (6736),
  `retro_controller_description` (4451), `retro_controller_info` (4476),
  subsystem ROM info (4531).

> **Correction on the record.** `ARCHITECTURE.md` rule 1 currently states
> "Every core speaks the runtime ABI (`runtime/include/ezcore_runtime.h`)".
> That is **false** and contradicts the code. Every core speaks **libretro**;
> `ezcore_runtime.h` is the surface the *host* uses to drive a core through the
> runtime. Fixing that sentence is part of P1.

**Consequences, which are the whole strategy:**

1. ezCORE is already ABI-compatible with the large existing libretro core
   ecosystem. We do **not** invent a new core SDK. Doing so would orphan every
   existing core and forfeit the ecosystem for no gain.
2. ezCORE should **host** emulators, not reimplement them. Writing a new
   NES/Game Boy/PS1 core from scratch when tested, freely licensed ones exist
   would be wasted effort. The value ezCORE adds is the shell: one library,
   correct per-console settings, real touch controls, crash safety, one app.
3. The largest single blocker is not architecture — it is that the kernel
   answers "no" to almost everything a core asks.

**The keystone gap (verified 2026-09-26; count re-verified 2026-09-28 — 92 is
the number of unique `RETRO_ENVIRONMENT_*` defines in the vendored
`libretro.h`, reproducible with one grep):** `env_cb` implements **7 of the 92**
`RETRO_ENVIRONMENT_*` commands; everything else hits `default: return false`
(`runtime/src/runtime.c:71-114`). Unimplemented: `GET_CORE_OPTIONS_V2*`,
`GET_VARIABLE*`, `SET_CORE_OPTIONS_V2*`, `SET_INPUT_DESCRIPTORS`,
`SET_CONTROLLER_INFO`, `SET_MEMORY_MAPS`, `GET_RUMBLE_INTERFACE`,
`SET_HW_RENDER`, `SET_GEOMETRY`, `SET_PERFORMANCE_LEVEL`, `GET_LANGUAGE`, and
more. This single fact is why `MATRIX.md` records PS2, N64, GameCube, Wii,
Dreamcast and PC-architecture cores as frame-unverified.

Related, same audit: input is **digital only** — `RETRO_DEVICE_JOYPAD` is the
only handled device (`runtime.c:181-190`); the Dart layer sends **port 0 only**
(`lib/emu/emulation_worker.dart:171-172`) although the runtime holds 4 ports;
there is no `RETRO_MEMORY_*` support, so battery saves are not round-tripped;
and cores run **in-process**, which the worker itself states
(`lib/emu/emulation_worker.dart:11-12`): *"This is NOT process isolation: a
native core crash can still terminate the application."*

---

## 3. Two classes of emulated system — an honest distinction

Not every target is a core. Pretending otherwise produces promises that cannot
be kept, so the platform names both classes.

**Tier 1 — Runtime cores (libretro).** Dynamically loaded
`.so` / `.dylib` / `.dll`. Covers handheld, 8/16-bit, 32-bit, arcade, and
console targets through PS2 / GameCube / Wii / Dreamcast, and unlocks the
existing core ecosystem. Delivered in-process today; containment in P6.
**This is the primary platform path.**

**Tier 2 — Engine integrations.** A current-generation console emulator, or a
Windows-PC-games stack, is a large standalone native program. It does not
expose `retro_*` and will not without upstream cooperation. ezCORE's honest
promise for Tier 2 (`ADR-017`): **supervise and drive it** — launch the
process, route display/input/audio through ezCORE, watch its lifecycle, and
keep library, save and controller continuity. This is deliberately *not*
claimed as in-process embedding.

**iOS boundary (permanent platform fact, not an ezCORE defect).** iOS does not
permit loading third-party native code at runtime. iOS therefore stays a
**build-time** target: cores are linked into the app. Self-serve core
installation is a desktop/mobile-non-iOS feature. Documented, not worked
around.

---

## 4. The package format — metadata is data, never code

A core package carries the emulator **and** its controls, skin, cheats, and
host-exposed functions. Because libretro already standardises most of the
metadata, the genuinely ezCORE-specific surface is small:

```
<core-id>/
├── <core-id>_libretro.<so|dylib|dll>   # native code — trust tier applies
├── <core-id>.info                      # libretro's own metadata standard
└── ezcore/
    ├── control/<system>.json           # touch layout   (ezCORE-specific)
    ├── skin/<theme>.json               # skin/theme tokens (ezCORE-specific)
    ├── cheats/<system>.json            # reuses the existing .cht format
    └── functions.json                  # shaders, netplay, rewind, region hooks
```

Only `control/`, `skin/`, and `functions.json` are new to the world. Core
identity, supported extensions, firmware, options, and input descriptors come
from standards that already exist — which is what makes "fully documented and
correct" an achievable goal rather than an aspiration.

**Adoption is deliberately compatible:** a v0.2.0 `cores/<id>/manifest.json`
is a valid v1 package. No forced migration, no break for existing cores.

---

## 5. Security model

ezCORE executes native code it did not necessarily write. That is the whole
product, and it is the whole risk. The model is three layers, and it does not
pretend to make unknown code safe.

**Layer 1 — Native code: two trust tiers, never blurred (`ADR-016`).**

- **ezCORE Verified** — reviewed by the project, listed in-app, labelled with
  a trust badge, updated by the project. Integrity protected by the existing
  SHA-256 manifest pins, verified before staging, and (P7) a real signature.
- **Unverified / bring-your-own** — third-party cores are permitted. They are
  opt-in with a plain-language warning, never on by default, never
  auto-updated, never labelled verified, and (once P6 lands) run in an isolated
  process.

**The honest limit:** running unknown native code cannot be made 100% safe. A
loaded `.so` has the same privileges as the app. No engineering removes that.
What engineering *can* do is: not run unknown code by default, isolate what is
run, and never let metadata execute anything. Anyone promising more is selling
something.

**Layer 2 — Data packages: fully enforceable, and the best safety-per-effort
in the platform.** Control layouts, skins, cheat sets, and presets are JSON and
**must never execute anything**. The validator enforces: JSON-schema validation;
size caps; path confinement (no `..`); no symlinks; no nested directories; no
network URLs fetched; unknown fields rejected rather than ignored. This reuses
the proven shape of the existing `scripts/verify_core_art.py` gate (flat files,
no symlinks, bidirectional set equality, per-file pins) rather than inventing a
new one.

**Layer 3 — Content and saves.** ROM plausibility checking already exists
(`lib/services/rom_validator.dart`). P4 adds save-state integrity and explicit
handling of untrusted save sources; P6 containment limits decoder exploits to
a killable process.

**Cryptography:** do not hand-roll. Keep the SHA-256 pins that already work,
use platform code signing where it is free, and make a real signature scheme
(Ed25519) its own task with an explicit dependency decision (`ADR-016`).
Hand-rolled crypto is worse than none.

---

## 6. Platform invariants — these may not be broken

Machine-checkable where possible. A change that violates one of these is not a
refactor; it is a rejected change, and needs an ADR plus explicit maintainer
approval to proceed.

1. **The core ABI is libretro.** Never add an `ezcore_*` entry point that a
   *core* is required to implement. `ezcore_runtime.h` may grow **additively**
   for host use only.
2. **Every capability addition is additive and soft-resolved.** New host
   functions are NULL-checked at every call, exactly like the existing optional
   save-state entry points (`runtime.c:456-469`). Existing behaviour must not
   change.
3. **The existing native test suite is the tripwire.** `test_core_player`
   (`runtime/test/test_core_player.c`, ~40 assertions) and `test_core_boot`
   must pass **unmodified** across a kernel change. If a kernel change requires
   editing those tests to pass, the change is wrong.
4. **Cores never depend on Flutter.** No Dart import, no UI coupling, no
   knowledge of Orbit. A core is a native artifact described by data.
5. **No core-name branching in the UI.** `runtime/src/` may carry core quirks —
   one exists today and is architecturally sanctioned
   (`runtime.c:272-287`, the Mesen init-order workaround). The Flutter layer
   must not branch on core identity except through verified manifest data
   (artwork, cheat families, blocked/gated reason).
6. **Capability before content.** Do not add a console, core, or system to the
   catalog until the kernel can actually run and verify it. An entry that
   cannot reach `RENDERS` in `MATRIX.md` is a promise the project cannot keep.
7. **Never trade the core contract for one core's convenience.** Per-core hacks
   in the kernel are a last resort with a comment naming the reason; per-core
   hacks outside the kernel are forbidden. This is the failure mode that turns a
   platform into a pile of special cases.
8. **Data packages never execute code.** No scripts, no eval, no plugins, no
   fetched URLs in any package file. Ever.
9. **Untrusted native code is opt-in, labelled, and never auto-updated.**
10. **Local-first, no mandatory network.** ezCORE is fully usable with no
    account, no server, and no network. A remote registry is additive.
11. **Never knowingly break a save.** Save formats and user data are
    compatibility-sensitive; version and migrate deliberately.
12. **No new ABI generation without an ADR.** `EZCORE_ABI_VERSION` moves only
    with a recorded, reviewed decision.
13. **Claims must match evidence.** Build, boot, identify, render, and play are
    different claims. What was not verified is stated as not verified.

---

## 7. Delivery program

Order and status live in [`../ROADMAP.md`](../ROADMAP.md) → *Platform
program*. Summary:

| # | Program item | Unlocks | Risk |
|---|---|---|---|
| P1 | Documentation truth + core options/capabilities in the kernel | PS2/N64/GC/Wii/Dreamcast, and every existing core | High |
| P2 | `.info` support, package format, validator | Cores become complete packages | Medium |
| P3 | Input device model (analog, mouse, lightgun, touch, ports) | Switch/PS5-class input, PC-style control | Medium |
| P4 | Control layouts, skins, battery saves, cheat packaging | Third-party controls with no ezCORE code | Medium |
| P5 | Verified list and trust tiers | Safe self-serve distribution | Medium |
| P6 | Crash containment (per-core process) | A bad core cannot kill the app | High |
| P7 | Signature/trust hardening, `registry.json` made real | Verifiable verified-list | Medium |
| P8 | GPU video path (`SET_HW_RENDER`, textures) | GL-class cores render | High |
| P9 | Tier-2 engine supervision | PS5-class and PC-game targets | Experimental |

**P1 is the keystone and the gate.** P6, P8, and P9 must not begin before P1
lands and the blocked cores reach `RENDERS` in `MATRIX.md`. Building the
expensive layers against an unfinished kernel contract means building them
twice.

---

## 8. Known documentation defects (tracked in P1)

Recorded so no one builds on a false statement. Fixing them **is** P1; they are
listed here rather than silently corrected in passing.

| File | Defect | Severity |
|---|---|---|
| `docs/ARCHITECTURE.md:44-46` | "Every core speaks the runtime ABI" — false; cores speak libretro | High — misleads every third-party author |
| `docs/ARCHITECTURE.md:23` | claims "SRAM handoff" as a runtime feature; `RETRO_MEMORY_*` is absent from the runtime | High — claims a feature that does not exist |
| `docs/API.md:42-46` | documents `EZCORE_PIXEL_XRGB8888`, `EZCORE_PIXEL_0RGB1555`, `EZCORE_PIXEL_RGB565` — **no such macro exists anywhere in the repository** | High — fabricated API |
| `docs/API.md` | documents 15 of the 25 exported functions; `ezcore_reset`, `ezcore_set_button`, `ezcore_clear_buttons`, `ezcore_frame_size`, `ezcore_frame_pixels_copy`, `ezcore_audio_drain_copy`, `ezcore_audio_pending`, `ezcore_sample_rate` are undocumented | Medium |
| `docs/API.md` | describes `ezcore_audio_drain` as thread-safe; it is an unsynchronised `memcpy`/`memmove` (`runtime.c:430-438`) | Medium — safety claim |
| `release.sh:18-20` | header documents `build_runtime.sh ios --static`; the script has no `--static` handling and would exit 2 (`build_runtime.sh:15,53-56`) | Medium |
| `cores/registry.json` | declares a signature from `scripts/sign_registry.py`; **that script does not exist**, and nothing reads this file | Medium |
| `runtime/src/runtime.c` | `ez_dyn_open` / `ez_dyn_sym` / `ez_dyn_close` are exported from the runtime library although declared internal to `dynload.h` | Low — ABI hygiene |

**Status (2026-09-28):** rows 1–7 corrected by P1a; the mechanical gate is
`scripts/check_api_docs.py`, wired into the runtime ctest suite. Row 8 is
deferred to P8 — hiding those exports is a build-surface change, not
documentation (`KNOWN_ISSUES.md`, technical debt). Two defects beyond the
table, found by the new gate: the thread-safety table and the "Typical usage"
prose also prescribed the unsynchronised pattern the runtime cannot honour.

**Durable fix (part of P1):** a test that enumerates the exported symbols in
`runtime/include/ezcore_runtime.h` and fails when one is undocumented, and a
check that documented macros exist in the source. Documentation rot is
mechanical; it should be caught mechanically, not by a human noticing.

---

## 9. Contributing to the platform

- Third parties and new emulators: [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
  and §4 here. Two supported doors — a self-serve local package folder, or a
  pull request reviewed into `cores/` — both validated by the same rules.
- Core-authoring walkthrough (how to build, package, and declare a core) is a
  **P1 deliverable**. Until it exists, this file plus the libretro API
  documentation are the authority.
- Changing anything in §6 requires an ADR in [`DECISIONS.md`](DECISIONS.md) and
  explicit maintainer approval, per `project.md` §1 and §65.

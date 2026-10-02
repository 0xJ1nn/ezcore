# Architecture Decision Records

> Every significant decision is logged here with context, options considered, and rationale.
>
> **Note (2026-09-19):** this log started as a planning document. Where a
> decision was later reversed, the ADR carries a **Superseded** status line —
> the current state of the project lives in [`ARCHITECTURE.md`](ARCHITECTURE.md)
> and [`RELEASE_PLAN.md`](RELEASE_PLAN.md).

---

## ADR-001: Runtime Language — C++

**Date:** 2026-09-16
**Status:** ~~Accepted~~ **Superseded** — the runtime shipped as **C11**
(`runtime/src/runtime.c`); no C++ migration happened, and the C ABI boundary
turned out to be all that mattered. See `ARCHITECTURE.md`.

### Context

ezCore needs a runtime layer between the Flutter UI and the libretro cores. The runtime owns session lifecycle, AV plumbing, input, saves, cheats, and cloud sync bridging. The choice of language affects performance, safety, cross-platform support, and long-term maintainability.

### Options Considered

| Option | Pros | Cons |
|---|---|---|
| **C** | Zero ABI friction, trivial FFI, already working | Manual memory management, no bounds checking, security surface |
| **Rust** | Memory safety, fearless concurrency, modern tooling | Learning curve, slower build times, smaller ecosystem |
| **C++** | Direct libretro compatibility, RAII, mature tooling, performance | Still memory-unsafe (but better than C), build complexity |

### Decision

**C++** for the runtime layer.

### Rationale

1. **Direct libretro compatibility** — cores are C/C++, no translation layer needed
2. **Performance** — zero overhead for frame/audio processing, no GC pauses
3. **Cross-platform** — one codebase compiles to Windows, macOS, Linux, Android, iOS
4. **Mature tooling** — CMake, Conan/vcpkg, established patterns for emulator development
5. **Memory control** — RAII, smart pointers, no GC pauses during emulation
6. **Community** — most emulator projects use C++, easier to find contributors

### Consequences

- Build system is more complex than C (CMake + Conan/vcpkg)
- Memory safety is better than C but not guaranteed (use sanitizers in CI)
- Need to manage platform-specific build configs carefully

---

## ADR-002: UI Framework — Flutter/Dart

**Date:** 2026-09-16
**Status:** Accepted

### Context

The UI layer needs to render 3D scenes, handle navigation, manage state, and provide a polished cross-platform experience.

### Options Considered

| Option | Pros | Cons |
|---|---|---|
| **Flutter/Dart** | Hot reload, declarative, cross-platform, growing 3D | 3D still experimental, larger binary |
| **Native (per-platform)** | Best performance, platform-native feel | 5x code, 5x maintenance |
| **React Native** | Large ecosystem, hot reload | Not ideal for 3D, performance concerns |
| **Qt/QML** | Mature, C++ synergy | Declarative but less modern, licensing |

### Decision

**Flutter/Dart** for the UI layer.

### Rationale

1. **Hot reload** — iterate on 3D UI in seconds
2. **Declarative** — complex 3D scenes are easier to compose
3. **Cross-platform** — one UI codebase for all platforms
4. **Impeller renderer** — Flutter's new renderer is performant enough for 3D
5. **Growing 3D support** — Flutter 3D, custom shaders, community packages

### Consequences

- 3D rendering may need custom shaders or platform channels for advanced effects
- Binary size larger than native
- Some platform-specific UI tweaks needed

---

## ADR-003: Modular Core Architecture

**Date:** 2026-09-16
**Status:** Accepted

### Context

ezCore needs to support 50+ emulation systems. Monolithic core integration would bloat the app, create IP risk, and make updates difficult.

### Decision

**Modular cores** — each core is a separate binary, downloaded at runtime, loaded via dlopen/dlsym.

### Rationale

1. **Licensing safety** — cores are separate binaries, not linked into ezCore
2. **Size** — users only download cores for systems they play
3. **Community** — third-party developers can build cores without touching ezCore
4. **Updates** — update cores independently of the main app
5. **Licensing** — each core can have its own license

### Consequences

- Core download system adds complexity
- Need manifest validation and sha256 verification
- Users need to manually download cores (or we provide a core store)

---

## ADR-004: Cloud Saves as Primary Feature

**Date:** 2026-09-16
**Status:** ~~Accepted~~ **Superseded** — cloud sync is deferred to v1.1
(backend, auth, conflict policy and privacy review are not v1 work); the
local Time Capsule vault is the v1 save story. See `RELEASE_PLAN.md`.

### Context

ezCore needs a primary selling point that differentiates it from existing emulators (RetroArch, OpenEmu, etc.).

### Decision

**Cloud saves** are the #1 feature. Everything else is secondary.

### Rationale

1. **Differentiation** — most emulators are local-only
2. **User value** — pick up where you left off on any device
3. **Lock-in** — users who invest in cloud saves are less likely to switch
4. **Monetization** — cloud saves are a natural Pro feature

### Consequences

- Need backend infrastructure (Firebase/Supabase)
- Need account system
- Need conflict resolution strategy
- Ongoing server costs

---

## ADR-005: Platform Holds — No Switch/3DS/PS2

**Date:** 2026-09-16
**Status:** Accepted

### Context

Some emulation systems carry active litigation risk from console manufacturers.

### Decision

**Never build or ship** cores for Switch, 3DS, or PS2.

### Rationale

1. **Nintendo litigation** — 2024 Yuzu settlement set precedent
2. **Proprietary firmware** — these systems require copyrighted firmware
3. **Risk/reward** — the risk far outweighs user demand
4. **Community reputation** — associating with litigation is bad for the project

### Consequences

- Some users will be disappointed
- Need clear communication about why these systems aren't supported
- May need to actively prevent community cores for these systems

---

## ADR-006: Vibe Coding via MD Files

**Date:** 2026-09-16
**Status:** Accepted

### Context

The user wants to drive development through MD files, with AI (me) reading specs and writing code.

### Decision

**All development is driven by MD files.** Specs before code. Documentation is part of the work.

### Rationale

1. **AI-friendly** — MD files are easy for AI to read and follow
2. **Human-readable** — user can review and steer without reading code
3. **Version-controlled** — MD files live in git, track changes
4. **Living documentation** — docs stay in sync with code

### Consequences

- Need to maintain MD files as code changes
- Need clear MD file hierarchy
- Need discipline to always update docs

---

## ADR-007: Privacy-First Architecture — Login Optional

**Date:** 2026-09-16
**Status:** Accepted

### Context

Emulation is a sensitive topic. Users are rightfully concerned about privacy — what they play, when they play, and whether their data is being collected. ezCore must be privacy-first by design, not as an afterthought.

### Decision

**Login is optional.** Users can use ezCore fully without creating an account. Cloud saves are an opt-in feature, not a requirement.

### Privacy Principles

1. **No usage analytics** — we don't track what games you play, when you play, or how long you play
2. **No telemetry** — no crash reports with usage data, no performance metrics
3. **Only save files in cloud** — if you opt into cloud sync, only your save state bytes are stored
4. **Local-first** — all data lives on your device first; cloud is a backup, not the source of truth
5. **Transparent** — clear privacy policy, open-source code, no hidden data collection

### Architecture

```
Guest Mode (default):
  - All saves stored locally
  - No account needed
  - No cloud sync
  - Full functionality (except cloud features)

Opt-In Cloud:
  - User creates account (email or OAuth)
  - Only save state bytes uploaded to Firebase Storage
  - Firestore stores: uid, pro status, last login (no usage data)
  - No analytics events logged
```

### What We Store

| Data | Stored? | Where |
|---|---|---|
| Save state bytes | ✅ (if opt-in) | Firebase Storage |
| User email | ✅ (if opt-in) | Firebase Auth |
| Pro status | ✅ (if opt-in) | Firestore |
| Last login | ✅ (if opt-in) | Firestore |
| Games played | ❌ | — |
| Play time | ❌ | — |
| IP address | ❌ | — |
| Device info | ❌ | — |
| Crash logs | ❌ | — |

### Rationale

1. **Trust** — emulation community is privacy-conscious; we earn trust by not collecting data
2. **Compliance** — less data = less liability (GDPR, CCPA compliance by design)
3. **Simplicity** — no analytics pipeline to build and maintain
4. **Differentiation** — "we don't track you" is a selling point

---

## ADR-008: Cheat Database — Agent-Tested

**Date:** 2026-09-16
**Status:** Accepted

### Context

Most emulators ship with community-sourced cheat databases that are untested — codes may be wrong, outdated, or game-specific. ezCore can differentiate by building a **tested, verified cheat database** using automated agents.

### Decision

Build our own cheat database using Hermes cron agents that:
1. **Harvest** cheats from community sources
2. **Validate** each cheat by loading it into the actual core and testing
3. **Curate** the database with confidence scores and categories

### Agent Architecture

```
Hermes Cron Agents (scheduled)
├── Agent 1: Cheat Harvester (weekly)
│   ├── Scrapes community cheat sources
│   ├── Deduplicates and normalizes codes
│   └── Outputs: raw_cheats.json
│
├── Agent 2: Cheat Validator (weekly)
│   ├── Loads each core via ezCore runtime
│   ├── Applies each cheat via ezcore_cheat_set
│   ├── Runs frames, checks if cheat took effect
│   └── Outputs: validated_cheats.json
│
└── Agent 3: Database Curator (weekly)
    ├── Merges validated cheats into master database
    ├── Categorizes (Gameplay, Items, Power-ups, etc.)
    ├── Assigns confidence scores
    └── Outputs: ezcore_cheats.db
```

### Unique Selling Point

"Every cheat in our database is tested and verified to work."

No other emulator does this. Users trust our database because we prove each code works.

### Rationale

1. **Quality** — tested cheats > untested cheats
2. **Trust** — users know our database is reliable
3. **Automation** — agents run on cron, minimal manual effort
4. **Community** — open-source database, community can contribute

---

## ADR-009: Metadata Source — OpenVGDB + No-Intro

**Date:** 2026-09-16
**Status:** Accepted

### Context

ezCore needs to identify ROMs and fetch metadata (title, box art, screenshots, genre, release year). Two main sources exist: ScreenScraper.fr (requires API key, rate-limited) and OpenVGDB (open-source, community-maintained).

### Decision

**OpenVGDB + No-Intro** for v1, with optional ScreenScraper.fr enhancement.

### Architecture

```
ROM dropped in folder
       ↓
1. Hash ROM header (SHA-256)
       ↓
2. Match against No-Intro DAT → game ID
       ↓
3. Look up metadata in OpenVGDB → title, box art, genre, year
       ↓
4. (Optional) User adds ScreenScraper API key → richer metadata
```

### Why This Approach

| Factor | OpenVGDB + No-Intro | ScreenScraper.fr |
|---|---|---|
| API key | Not required | Required |
| Rate limits | None | Yes |
| Cost | Free | Free (with limits) |
| Completeness | Good | Excellent |
| Open source | Yes | No |
| Works offline | Yes (after download) | No |

### Rationale

1. **Works out of the box** — no API key needed
2. **Open-source** — aligns with ezCore's values
3. **Offline capable** — download database once, works forever
4. **Extensible** — users can add ScreenScraper for richer data

---

## ADR-010: Payment Platform — Stripe + RevenueCat

**Date:** 2026-09-16
**Status:** ~~Accepted~~ **Superseded** — payments are not part of v1; no
payment code ships (the old roadmap's Firebase/Stripe scaffolding was
explicitly dropped). Revisit if/when a paid tier exists.

### Context

ezCore needs payment processing for Pro tier and in-app purchases. Desktop and mobile have different requirements.

### Decision

**Stripe for desktop, RevenueCat for mobile.**

### Architecture

```
Desktop (Windows/macOS/Linux):
  - Stripe checkout (web-based)
  - Payment methods: Card, Apple Pay, Google Pay
  - Stripe handles PCI compliance

Mobile (Android/iOS):
  - RevenueCat (unified IAP)
  - App Store / Play Store
  - RevenueCat handles receipt validation
```

### Why RevenueCat for Mobile

1. **Unified API** — one integration for App Store + Play Store
2. **Receipt validation** — server-side validation built in
3. **Subscription management** — cancel, renew, upgrade/downgrade
4. **Analytics** — subscription metrics without usage tracking

### Why Stripe for Desktop

1. **Best checkout experience** — customizable, fast
2. **PCI compliance** — Stripe handles everything
3. **Payment methods** — cards, Apple Pay, Google Pay, more
4. **No platform fees** — unlike App Store (15-30%)

### Rationale

1. **Platform-appropriate** — each platform gets the best tool
2. **Minimize fees** — Stripe on desktop avoids Apple/Google fees
3. **Unified Pro status** — one account, Pro on all devices

---

## ADR-011: First functional release uses the existing runtime seam

**Status:** Accepted for the current implementation brief.

Preserve the existing C ABI rather than rewriting it as part of UI integration.
Use one worker isolate as the owner of a native session, with bounded frame
requests and a separate platform PCM adapter. The isolate moves execution off
UI work; it does not sandbox native code. Verify manifest artifact hashes before
launch and keep local persistence as the default.

Current implementation uses software RGBA frame copies and a macOS audio adapter.
Release acceptance requires an actual app-level content/import/play/input/audio/
save/reopen run; contract tests and a successful build alone are insufficient.
Earlier monetization/cloud-first release priorities are not goals of this slice.

## ADR-012: Core repository policy — independent builds, full credit, first-party over time

**Status:** Accepted (2026-09-20).

Every emulator engine ships under an ezCORE-owned codename (NesByte, PocketBit,
AdvanceBit, …). The codename is ezCORE's brand; the upstream project's name is
never hidden and never used as the core's name. This is deliberate: no renamed
forks, no quiet re-licensing, no upstream confusion.

How each core is created, in priority order:

1. **Independent build (current standard).** Each core lives in its own
   repository (`ezcore-core-<codename>`) holding only ezCORE-owned scaffolding:
   a GPL-3.0 build recipe, CI, and documentation. The engine is fetched at build
   time from the pinned upstream repository as a git submodule. No upstream file
   is copied, renamed, or committed. Upstream is credited in every core README,
   in the repo description, and in `THIRD_PARTY_NOTICES.md`.
2. **Recipe-only for incompatible licences.** Where the upstream licence is
   non-commercial (Snes9x, Genesis Plus GX, FBNeo), the repository ships the
   build recipe and verifies it in CI, but **no binary is ever distributed**.
3. **First-party cores (long term).** Cores written fresh from scratch by
   ezCORE (ColorBit — Game Boy Color is the first reserved slot; see
   `ezcore-core-colorbit`). Public hardware documentation only; no upstream
   emulator source is copied or translated. Over time this replaces the
   upstream-build path one system at a time.

Non-negotiables for every core repository:

- Zero game content: no ROMs, BIOS, firmware, decryption keys, game art, or
  cheat databases — now or ever. Binaries are never committed; artifacts are
  sha256-pinned at build time only.
- No hold targets: Switch, 3DS, and PS2 stay excluded everywhere (ADR-005).
- Licence honesty: scaffolding is GPL-3.0 (matching ezCORE); the engine keeps
  its upstream licence, stated by name in the README. Upstream licences that
  are "GPL-2.0-or-later" are used under the "or later" terms, which make them
  compatible with the GPL-3.0 app. GPL-2.0-only and non-commercial upstreams
  are recipe-only.
- Brand separation: the ezCORE name, icon, and lockups are reserved trade
  marks (`TRADEMARKS.md`); forks must rename. Core codenames are ezCORE's.

## ADR-013: Hybrid core delivery — bundled by default, on-demand giants

**Status:** Accepted (2026-09-23). Supersedes the "no download
infrastructure" half of `RELEASE_PLAN.md` item 7 (2026-09-18).

### Context

Bundling every core inflates the package: three desktop giants dominate
the tarball while most sessions never load them (`pointclick`/ScummVM
~170 MB staged, `dreamarc`/flycast ~39 MB, `powercube`/dolphin ~27 MB on
linux-x64). The maintainer wants the main package lightweight, cores
**never compiled on user devices**, and iOS untouched (App Review
2.5.2/4.7 forbids runtime code downloads).

### Decision

- **Delivery keeps three states** — `bundled` (in the package),
  `download` (fetched on demand), `absent`. The three desktop giants are
  `download` on macOS/Windows/Linux (threshold: staged size ≥ ~25 MB —
  re-evaluate when staging a new giant). Every other core stays
  `bundled`. Android keeps its tier as bundled (no Android download
  assets are published yet); iOS never downloads and keeps its tier value.
- **Host: GitHub Releases of this repository**, uploaded manually
  (`gh release upload`) — GitHub is repository hosting only, zero
  compute/Actions. `cores/release.json`, generated by
  `scripts/build_catalog.py`, records repo slug, release tag (must equal
  the pubspec version), and the asset filename per platform/core
  (`<id>_libretro-<plat>.<ext>`).
- **Trust chain is unchanged.** Bytes stream to `<dest>.part`, are
  sha256-verified against the pin that already ships inside the trusted
  catalog, staged into the local vault with the same `.ezpin` sidecar as
  bundled cores, and only then registered. Any mismatch or HTTP failure
  deletes the partial file. The app never compiles cores and never
  executes unverified bytes.
- **`license_audit` treats `download` as distribution** — every
  bundled-only rule (non-commercial, GPL-2.0-only, notices, pins) covers
  downloads identically, closing the gate gap this feature would
  otherwise have opened.

### Alternatives considered

- One platform-bundle asset per OS: rejected — downloading 200+ MB to get
  one core defeats the slimming goal.
- Adding the `http` package: rejected — `dart:io` `HttpClient` with
  redirect following covers every platform the app runs on, no new
  dependency.
- Hosting outside GitHub (any compute/bucket service): rejected — the
  maintainer's rule is GitHub = repository + release hosting only.

### Consequences

- Packages shrink by the giants; first use of a giant core shows an
  explicit Download action in the Core Manager.
- Platforms whose release lacks an asset fail honestly ("not published
  for `<platform>` yet"); macOS/Windows giant assets await those
  platform builds (recorded as *not verified* on this host).

## ADR-014: The core ABI stays libretro — no ezCORE core SDK

**Status:** Accepted (2026-09-26). Platform contract:
[`PLATFORM.md`](PLATFORM.md) §2 and §6. Binding on all future core work.

### Context

ezCORE is a modular platform: the maintainer's direction is that third parties
can add cores, and that one application should cover everything from handheld
systems to current-generation targets. That raises the question of what
contract a core implements.

The code already answers it, and the documentation does not. A core is a
**libretro** plugin exporting `retro_*` symbols
(`runtime/src/runtime.c:216-225`), gated on `retro_api_version() == 1`
(`runtime.c:231-236`). `runtime/include/ezcore_runtime.h` — the `ezcore_*`
surface — is host-facing: Dart calls it to drive a core *through* the runtime,
and no core ever calls it. `docs/ARCHITECTURE.md:44-46` states the opposite
("Every core speaks the runtime ABI"), which is false and would actively mislead
every third-party author. Separately, the kernel implements **17 of the 93**
`RETRO_ENVIRONMENT_*` commands (`runtime/src/runtime.c:197`,
`default: return false`), counted against the vendored header
`runtime/external/libretro-common/include/libretro.h`, which is why
`MATRIX.md` records PS2/N64/GameCube/Wii/Dreamcast as frame-unverified.

### Decision

- **The core contract is libretro API v1, unchanged.** We do not design,
  publish, or require an ezCORE-specific core SDK.
- The host ABI (`ezcore_runtime.h`) may grow, but **additively only**, and only
  for host use. New capabilities are soft-resolved and NULL-checked, following
  the existing optional save-state pattern (`runtime.c:456-469`).
- Work the kernel's missing capability surface (core options, input
  descriptors, controller info, memory maps, hardware render) rather than
  replacing the ecosystem we already speak.
- Read existing standards for metadata — libretro `.info` files, `retro_
  core_option_value`, `retro_input_descriptor`, the existing `.cht` cheat
  format — instead of inventing parallel formats.
- `docs/ARCHITECTURE.md` and `docs/API.md` are corrected as program item P1.

### Consequences

- ezCORE is immediately compatible with the existing libretro core ecosystem;
  thousands of cores become reachable by finishing the kernel rather than by
  writing new cores.
- The project hosts emulators instead of reimplementing them. Reimplementing
  tested, freely licensed emulators is wasted effort.
- ezCORE-specific extension points are confined to **non-code metadata**
  (control layouts, skins, function hooks) that libretro does not standardise.
- The existing native tests (`test_core_player`, `test_core_boot`) are the
  regression tripwire: a kernel change that requires editing them to pass is
  rejected by contract.

### Alternatives considered

- **Design an ezCORE core SDK.** Rejected: it orphans every existing libretro
  core, gains nothing the ABI does not already express, and makes ezCORE a
  project of one rather than a platform.
- **Wrap libretro instead of using it.** Rejected: an indirection layer with no
  capability gain; it would be a second ABI to keep in sync.
- **Fix the documentation only, defer the kernel.** Rejected: the missing 89
  environment commands are the binding constraint on the product, not a
  documentation problem.

## ADR-015: A core crash must not terminate ezCORE

**Status:** Accepted (2026-09-26), sequenced behind P1. Platform contract:
[`PLATFORM.md`](PLATFORM.md) §5 and §6.

### Context

Cores are currently `dlopen`ed into the application process
(`runtime/src/dynload_posix.c:7-13`). The project already records the
consequence in its own code: `lib/emu/emulation_worker.dart:11-12` states
*"This is NOT process isolation: a native core crash can still terminate the
application."* A `dart:isolate` isolates Dart, not native code.

The platform's stated direction is that **third parties** add cores. That makes
crash containment a trust property, not a nicety: without it, one bad core
takes the library, the save vault, and the session with it, and produces no
diagnostic.

### Decision

- **A core crash must never take down the application.** The end state is one
  process per core session, supervised by ezCORE.
- On crash: the game session ends, the failure is recorded in diagnostics, the
  library and saved data survive, and the user may select another core.
- Ship **behind a setting, defaulting to today's in-process path**, so it can be
  adopted and validated incrementally rather than as a single large switch.
- Sequenced **after** P1. Containment is the most expensive and most
  cross-platform item; building it against an unfinished kernel contract means
  building it twice.
- Until it ships, the limitation is **stated in documentation and in-app** and
  never papered over.

### Alternatives considered

- **Keep cores in-process, document the risk.** Rejected: acceptable for
  first-party curated cores, not for a platform that invites unknown
  third-party native code.
- **Immediate hard cutover to per-core processes.** Rejected: highest risk of
  regressing the one core that currently renders; an opt-in path preserves a
  known-good fallback.
- **Static analysis or sandboxing instead of processes.** Rejected as a
  substitute: neither contains a runtime fault at execution time.

## ADR-016: Third-party cores are self-serve, with an ezCORE Verified tier

**Status:** Accepted (2026-09-26). Platform contract: [`PLATFORM.md`](PLATFORM.md)
§4, §5, §6.

### Context

The maintainer's direction is that a third party should be able to add a working
core — with touch layouts, skins, and cheats — **without the maintainer writing
code**, while ezCORE also keeps a curated list of its own cores. The trust
question was raised explicitly: prevent viruses, malware, and injection.

An emulator core is a native shared library. Once loaded it has the same
privileges as the application. This cannot be engineered away, and no plan that
implies otherwise is honest.

### Decision

Two doors, one validator:

- **Self-serve.** A local package folder, or an added download. Fully offline,
  no account, no server. Opt-in with a plain-language warning.
- **Reviewed.** A pull request into `cores/`, reviewed and pinned, for cores the
  project stands behind.

Two trust tiers, never blurred:

- **ezCORE Verified** — project-reviewed, listed in-app with a trust badge,
  project-updated, integrity-protected by SHA-256 manifest pins and (P7) a
  signature.
- **Unverified** — permitted, clearly labelled, opt-in, **never**
  auto-updated, and run contained once P6 lands.

Metadata that ships with a package is **data and never executes code**: JSON
schema validation, size caps, path confinement (no `..`), no symlinks, no
nested directories, no fetched URLs, unknown fields rejected. This reuses the
proven shape of the existing `scripts/verify_core_art.py` gate.

Cryptography is not hand-rolled. SHA-256 pins stand; a real signature scheme
(Ed25519) is a separate task with an explicit dependency decision; platform
code signing is used where it is free.

### Consequences

- ezCORE stays fully usable with no account and no network, consistent with the
  local-first policy in `MONETIZATION.md`.
- A third party can ship controls, skins and cheats without any ezCORE release.
- The project accepts a real, documented risk: unverified native code can be
  malicious. It is mitigated by default-deny, labelling, and containment — not
  eliminated, and never described as eliminated.
- Adding a core to the catalog no longer requires a maintainer code change
  (P2), which is the actual definition of the platform working.

### Alternatives considered

- **Pull-request-only intake.** Rejected as the sole path: onboarding stays
  gated on maintainer review bandwidth, which does not scale.
- **Signed remote registry only.** Rejected as the sole path: requires hosting,
  key rotation and an outage story before the first third party can onboard.
  Retained as an additive transport for the Verified tier.
- **Claim untrusted cores can be made safe in-process.** Rejected: not
  technically possible.

## ADR-017: Tier-2 targets are supervised, not embedded

**Status:** Accepted (2026-09-26), experimental scope. Platform contract:
[`PLATFORM.md`](PLATFORM.md) §3.

### Context

The product direction includes current-generation console targets and
Windows-PC-games emulation. Those targets are large standalone native programs.
They do not expose the libretro API and have no reason to, so they cannot be
`dlopen`ed as Tier-1 cores, and ezCORE cannot make them into cores without
upstream cooperation that cannot be assumed.

Claiming in-process embedding would be a promise the project cannot keep.

### Decision

- **Tier 1 — libretro cores** are the primary platform path and the focus of
  near-term work.
- **Tier 2 — engine integrations** are supervised: ezCORE launches the engine,
  routes display, input and audio through itself, watches the process lifecycle,
  and preserves library, save and controller continuity.
- Tier 2 is described as supervision and routing. It is **not** described as
  embedding, and `MATRIX.md` claims stay bounded accordingly.
- Tier 2 work is experimental and starts only after P1.

### Alternatives considered

- **Design an ezCORE engine ABI and link engines in-process.** Rejected: no
  external engine will implement it, and it would compete with the Tier-1 path
  we just decided to keep (ADR-014).
- **Deep-link / hand off to the external emulator.** Rejected as the whole
  answer: it forfeits library, save and controller continuity, which is most of
  the user value. Retained as a fallback.
- **Ignore these targets.** Rejected: the maintainer named them explicitly, and
  the supervision scope is deliverable and honest.

---

## ADR-018: The GPU video path — who owns the render context

**Status:** **Accepted — Option B** (2026-09-29, maintainer decision).
Context ownership is **the runtime's own EGL/GLES and Vulkan surfaces**, not
Flutter's engine context. Both GL and Vulkan are in scope, and the design must
be platform-neutral: no per-platform rework of the presentation path.

Rationale as given by the maintainer, which the evidence supports: Flutter's
native context "doesn't seem tested for gaming". The record's own Option A
analysis had already found that Flutter exposes a render *target* to plugins
and no shareable context, so A was never going to answer `SET_HW_RENDER` on
desktop, where the Vulkan cores matter most.

The remaining open questions below are answered as follows; the superseded
text is retained so the reasoning is auditable.

1. **Context ownership** — B. *(decided)*
2. **First API cut** — the full set (`SET_HW_RENDER`,
   `GET_PREFERRED_HW_RENDER`, `GET_HW_RENDER_INTERFACE`,
   `SET_PROC_ADDRESS_CALLBACK`, plus `context_negotiation` so context loss is
   reportable). A partial cut that answers `true` to `SET_HW_RENDER` without
   being able to report loss is the failure mode to avoid.
3. **Verified platform** — Linux desktop is where the existing gates run, so
   it is the platform that gates P8. Android and Windows follow the same code
   path; per-platform context creation is isolated behind one seam so none of
   them needs the others reworked.
4. **Vulkan in scope** — **yes**, and explicitly: `geometry1`, `powercube`,
   `portcomp` and `dreamarc` all reference `vkCreateInstance`, PS2 (issue #55)
   requires Vulkan, and `libretro_vulkan.h` is already vendored. `rcp64` and
   `dualscreen` are GL-only (0 `vkCreateInstance` symbols, 3199 and 15 GL
   symbols), so both backends are required to unblock all six.
5. **`video_cb(NULL)` dupe defect** — out of scope for P8. It is a CPU-path
   correctness bug unrelated to hardware rendering and must not land inside a
   change whose purpose is to avoid disturbing the CPU path. Tracked
   separately.
6. **New dependencies** — none for a first cut. The existing `dynload.h` seam
   resolves `libEGL`/`libGLESv2`/`libvulkan` at runtime; the runtime stays
   free of link-time GL/Vulkan dependencies, which keeps `PLATFORM.md` §6
   true.

### Verification available for this item (checked 2026-09-29)

P8 is **verifiable on the development host**, not only on paper:

- Vulkan 1.4.357 instance, with both `nvidia_icd.json` and `radeon_icd.json`
  present.
- EGL 1.5 initialises; a GLES **3.2** context on a pbuffer binds a
  framebuffer object reporting `GL_FRAMEBUFFER_COMPLETE` on real hardware
  (AMD Radeon, Mesa 26.2.3).

So the GL/GLES seam can be exercised by ctest, and the Vulkan seam can at
minimum have its instance/device/queue negotiation exercised, on the same
machine the rest of the gates run on.

---

## Superseded: the original proposal (retained for audit)

**Original status:** **Proposed** (2026-09-29). Not a decision. The maintainer
selects the context-ownership option and the first API to implement; this
record exists so the choice is made on evidence rather than by whoever writes
the code first. Program item **P8**, gated on P1 (`ROADMAP.md` → *Platform
program*). Platform contract: [`PLATFORM.md`](PLATFORM.md) §2, §6, §7.

### Current architecture (verified 2026-09-29)

Verified in this worktree, not recalled:

- A core is a libretro plugin. The kernel is `runtime/src/runtime.c`
  (C11, `EZCORE_ABI_VERSION 1`, `runtime/include/ezcore_runtime.h:12`).
- `env_cb` (`runtime/src/runtime.c:197`) answers **21 of the 93**
  `RETRO_ENVIRONMENT_*` commands; everything else hits
  `default: return false` (`:402-403`).
  **`SET_HW_RENDER`, `GET_PREFERRED_HW_RENDER`, `GET_HW_RENDER_INTERFACE` and
  `SET_PROC_ADDRESS_CALLBACK` are all unimplemented.** A grep for
  `context_reset` and `RETRO_HW` in `runtime.c` returns **zero hits**: the
  runtime has no concept of a graphics context, cannot report one as lost,
  and cannot advertise its pixel format to a core through the hardware-render
  interface.
- **Every frame on screen is a CPU copy.** `video_cb`
  (`runtime.c:407-409`) `memcpy`s each scanline into a session-owned heap
  buffer `s->frame` (`:411-424`), converting 0RGB1555/RGB565 to XRGB8888 in
  software (`:426+`); `ezcore_frame_pixels_copy` (`:697-710`) then expands
  that to RGBA bytes across FFI into a Dart `Uint8List`; the player turns it
  into a `RawImage` (`lib/screens/player_screen.dart:386`). At 320×240 that
  is ~307 KB of runtime copy plus ~307 KB of FFI copy per frame, ~18 MB/s at
  60 fps — arithmetic from the code, **not a measured figure**.
- The published contract is `ezcore_frame_pixels` → *"Returns const pointer to
  latest frame (XRGB8888). Do NOT free. Fast read access."*
  (`runtime/include/ezcore_runtime.h:65-66`).

**Consequence:** cores that default to a GPU renderer refuse to run.
`geometry1` (PSX), `rcp64` (N64), `dualscreen` (NDS), `portcomp` (PSP),
`dreamarc` (DC) and `powercube` (GC/Wii, GPU-only) are blocked, and
`MATRIX.md` records them as frame-unverified. The CPU path stays green for
`pocketbit`, `advancebit` and `nesbyte`.

### The problem

P8 cannot be "add `SET_HW_RENDER`". The command is a request from the core
for *a render context*; the host must already own one and be able to (a) hand
it a context or a context-creating capability, (b) tell the core which
context version to use, (c) resolve the GL/Vulkan entry points the core needs
(`SET_PROC_ADDRESS_CALLBACK`), and (d) survive a context loss
(`RETRO_ENVIRONMENT_SET_HW_RENDER_CONTEXT_NEGOTIATION` /
`context_reset`). ezCORE currently owns none of that, and the runtime
deliberately has **no external library dependencies** beyond the vendored
`libretro-common` headers (`docs/ARCHITECTURE.md:35-38`).

There is a second, smaller problem that is easy to miss because it is one
line: `video_cb` returns immediately when `data == NULL`
(`runtime.c:409`). In libretro, `video_cb(NULL, …)` is the **"repeat the
previous frame"** signal — a 30 fps core on a 60 Hz display calls it every
other frame. `GET_CAN_DUPE` is answered `true` (`runtime.c:199-202`) on the
stated belief that *"we keep the last decoded frame"*, but the callback drops
the dupe instead of preserving it, so the *host* does not re-present the
retained frame. Whether that is a defect to fix inside P8 or a separate
one-line fix is an open question below.

### The three context-ownership options

Presented as options, not as a recommendation. The maintainer picks.

| | **A — reuse Flutter's context** | **B — C-side EGL/GLES context** | **C — readback only** |
|---|---|---|---|
| Who creates the context | Flutter's renderer | `runtime/src/` on a dedicated render thread | `runtime/src/` on a dedicated render thread |
| What reaches the screen | Flutter-composited external texture | External texture fed from our own GL context | The **existing** `Uint8List` → `RawImage` path, unchanged |
| Dart/UI changes | Texture registration, `Texture` widget, lifecycle | Texture registration **and** a GL→texture upload path | **None** |
| Host ABI changes | additive query | additive query | none required |
| Context loss handling | not ours | ours (`context_reset`) | ours |
| Unblocks the 5 GL-default cores | yes, if the context is actually obtainable | yes | yes |
| Zero-copy | possible | possible | **no** — the readback the item exists to avoid still happens |

#### Option A — reuse Flutter's renderer context

**Pros.** No second GL context on the device; no extra EGL surface to
manage; the most direct route to zero-copy compositing through Flutter's
`TextureRegistry`; natural fit on Android, where the host already owns an EGL
context on a dedicated GL thread — which is exactly the arrangement RetroArch
uses there.

**Cons, and one of them is structural.** Flutter's `TextureRegistry` hands a
native plugin a *render target* (a GL texture id, a `SurfaceTexture`/`GLTexture`,
an iOS `CVPixelBuffer`/texture), **not a shareable GL context**. I could not
find a supported Flutter API that exports the engine's own context for sharing
with third-party native code, and I did not verify Flutter's or Impeller's
sources in this pass — **stated as uncertainty, not as a finding**. So the
practical form of A is *"host provides a render target"*, whereas libretro's
`SET_HW_RENDER` asks for a *context*. The gap between those two is bridged in
the libretro world by the host also implementing
`retro_hw_render_callback::get_current_framebuffer` with a real
`GLuint` framebuffer — i.e. A still requires a runtime-side GL surface and a
`context_reset` path even when the context itself comes from Flutter.

**Costs.** Android-only in practice. Desktop (Linux/Windows/macOS) Flutter
gives the host no comparable handle today, so A does not reach the platforms
where `dreamarc` and `powercube` matter most. The external-texture
registration lifecycle (create → attach → dispose on session end) is new Dart
code with real leak potential.

#### Option B — a C-side EGL/GLES context owned by the runtime

**Pros.** Matches what libretro cores are written and tested against;
uniform across Android and desktop, so one design serves all five GL-default
cores; the runtime fully controls `context_reset`, the swap interval, FBO
creation, and (later) the shader work the Graphics and Shaders roadmap items
want; the presentation seam is a single `TextureRegistry` call regardless of
platform.

**Cons.** The runtime acquires platform GL/EGL responsibilities it has never
had — and `PLATFORM.md` §6 is a list of things that may not quietly become
false, so "the runtime has no external dependencies" and "the runtime creates
a GL context" are in tension and the maintainer should decide which way to
bend. Per-platform context code (EGL on Android/Linux, WGL/ANGLE on Windows,
CGL/NSOpenGL on macOS) is the largest new surface in this item. Then the
compositing question is unsolved by B: our own context still has to hand its
output to Flutter, which is an external texture again — so **B and A
converge on the same Dart-side integration**; they differ in who owns the
context, not in whether a texture is involved. Windows is the sharp edge:
depending on what the loader resolves, a machine without
`opengl32.dll`/`libEGL.dll` has no path, and ANGLE would be a new dependency
(see below).

#### Option C — readback only: keep the core's GL internal, `glReadPixels` into today's buffer

**Pros.** **Zero Dart/UI change.** `video_cb` is unchanged, `s->frame` is
unchanged, `ezcore_frame_pixels*` and the `RawImage` path are unchanged, and
every existing test stays valid by construction. It is the smallest change
that makes the five blocked cores boot and present, and it is therefore the
cheapest way to get evidence about which cores actually work on which
platform before committing to a presentation architecture. It also keeps the
`RawImage` screenshot/thumbnail path free (`ROADMAP.md` → *Capture*:
screenshots are "written locally and used as cover art"). All the hard parts
that matter for correctness — `SET_HW_RENDER`, `GET_PREFERRED_HW_RENDER`,
`GET_HW_RENDER_INTERFACE`, `SET_PROC_ADDRESS_CALLBACK`, `context_reset` — are
still genuinely implemented and still exercised.

**Cons, stated plainly.** It does **not** deliver the performance outcome the
item is for: a frame still crosses GPU→CPU→GPU every frame, at full
resolution, plus a second FFI copy. For 320×240 that is affordable; for a
720p/1080p N64 or GameCube frame it is not. It buys *unblocking*, not
*acceleration*. It also means the CPU mirror is mandatory, not optional, which
is a constraint on the ABI question below.

### The `ezcore_frame_pixels` ownership contract and the CPU mirror

The published promise is a valid pointer to the latest XRGB8888 frame
(`ezcore_runtime.h:65`). Three ways to keep that promise once a GPU path
exists, all presented for choice:

1. **Always mirror (C, and B with a capture tap).** `s->frame` stays
   authoritative. The contract is literally unchanged, screenshots and
   thumbnails keep working, and the CPU path is untouched. Cost: on the GPU
   path there are now *two* copies per frame, and one of them exists only to
   honour a promise nobody exercises at full rate.
2. **Additive, soft-resolved capability query.** Add
   `ezcore_frame_source(s) -> enum { CPU, GL_TEXTURE, VULKAN_TEXTURE }` and
   let `ezcore_frame_pixels` return `NULL` when the source is not CPU.
   Honest, cheap, and — per `ADR-014` and `PLATFORM.md` §6.2 — **additive and
   soft-resolved, so `EZCORE_ABI_VERSION` stays 1.** The cost is a real
   behaviour change behind an unchanged signature, so the header comment must
   change from "do NOT free" to "returns NULL when the session is not on the
   CPU path".
3. **Lazy readback.** `ezcore_frame_pixels` triggers a `glReadPixels` into a
   session scratch buffer on first call per frame. The contract stays true
   and the cost moves to whoever asks (thumbnails, a screenshot, a test).
   Adds a GPU→CPU stall on an unpredictable caller; needs a per-frame
   "already read back" guard.

**No `EZCORE_ABI_VERSION` bump is required** for 1, 2 or 3, because each grows
the surface additively. A bump would only be justified if a *core* had to
implement something new — which `PLATFORM.md` §6.1 forbids — or if we chose
to redefine an existing signature. `PLATFORM.md` §6.12 permits the bump only
with a recorded, reviewed decision; this ADR does not request one, and I am
not confident a bump is the right call for a host-only additive surface.

### Loaders, and the dependency question

Cores load their own GL entry points; the runtime does not need a full
loader for the *core's* sake. What the runtime itself needs is a small
subset — `eglGetProcAddress`/`eglCreateContext`/`eglMakeCurrent` (or the
platform equivalent) to create and current a context under **B**/**C**, and
`glReadPixels` + `glGenTextures`/`glBindTexture`/`glTexImage2D` to read back
under **C** or to upload under **B**.

- **No new third-party dependency is required to get there.** The runtime
  already has a dynamic-loader seam (`dynload.h` / `dynload_posix.c` /
  `dynload_win32.c`); resolving those symbols through it keeps the build
  dependency-free, which is the status quo worth protecting.
- **Platform *headers* are still needed** (EGL + GLESv2 on Android/Linux,
  OpenGL on macOS, GL on Windows), and on Windows that is where a real
  dependency question appears.
- **Vendoring glad/glew, or linking ANGLE, is a separate decision** under
  `project.md` §26 and is **not** authorised by this ADR. ANGLE in
  particular would change what "supports OpenGL" means on Windows and is a
  large, separately-reviewable commitment.
- **Uncertain:** the exact `retro_hw_render_interface` revision available in
  the vendored `runtime/external/libretro-common/include/libretro.h` (which
  `interface_version` / `context_negotiation` / `proc_address` fields exist
  at the pinned revision). I did not verify this in this pass; it must be
  confirmed before any interface struct is filled in.

### Risk to the currently-green CPU path

`pocketbit`, `advancebit` and `nesbyte` are the only render-verified cores, and
they are the tripwire. The specific danger is that a core which *can* use a
GPU path will *take* it as soon as `SET_HW_RENDER` returns `true` — so
answering the command at all is a behaviour change for working cores, not
just for blocked ones.

Mitigations, in order of strength:

1. **The `SET_HW_RENDER` answer is itself the switch.** Answering `false`
   puts every core back on the software `video_cb` path, byte for byte, with
   no flag in the runtime. P8 can therefore ship dark and be switched on per
   session.
2. **Opt-in flag, default off**, exposed per session (player setting) and
   defaulting to off. Optional refinement for the maintainer: allow the
   manifest to *permit* the GPU path per core, so enabling it globally still
   cannot move an unvetted core — but that touches core data, so it is a
   proposal, not a decision.
3. **`test_core_player` and `test_core_boot` must pass unmodified**
   (`PLATFORM.md` §6.3). They run with the path off; any kernel change that
   needs them edited is rejected by contract.
4. **Golden-frame check.** The synthetic core's deterministic output
   (`runtime/test/synth_core/`) is the regression tripwire for "the CPU path
   did not move". The `ezcore_frame_pixels` NULL-dup interaction in particular
   will be caught here if a test covers a `video_cb(NULL, …)` frame.

### Benefits, costs and risks

**Benefits (common to A, B and C).** `SET_HW_RENDER` /
`GET_PREFERRED_HW_RENDER` / `GET_HW_RENDER_INTERFACE` /
`SET_PROC_ADDRESS_CALLBACK` answered, plus a real `context_reset` story.
`geometry1`, `rcp64`, `dualscreen`, `portcomp` and `dreamarc` become eligible
to reach `RENDERS` in `MATRIX.md`, which is the P8 exit condition. The
`RawImage` screenshot path keeps working regardless of session mode.

**Costs.** A new render thread and a GL lifecycle in the kernel; a texture
registration seam in Dart (A and B only); per-platform GL code; a larger
kernel with more platform-specific branches. C avoids the Dart and
presentation costs entirely and is the only option that ships without
touching the UI layer.

**Risks.**

- *Kernel regression on the green path* — mitigated by 1–4 above.
- *Black screen on device* — a core that takes the GPU path and cannot
  present gives no frame and no error. Mitigation: a watchdog — if no frame
  arrives within N frames of `retro_run`, fall back to the CPU path for that
  session and record it in diagnostics. **Whether the maintainer wants that
  auto-fallback or a hard failure is unresolved.**
- *Vulkan left out.* `SET_HW_RENDER` supports
  `RETRO_HW_CONTEXT_VULKAN`/`OPENGL`; PCSX2 (PS2, issue #55) needs
  **Vulkan specifically, not OpenGL**, which no GL-only implementation
  reaches. Whether P8 ships GL-only with PS2 explicitly out of reach, or
  negotiates both contexts from the first cut, is an open question.
- *Context loss* on Android (app backgrounded) and on desktop GPU driver
  reset: cores that have not implemented `context_reset` recovery will show a
  black frame until the session is restarted. `dolphin`-class cores in
  particular are known to be demanding here — **I have not verified that
  claim about any specific core in this pass; treat it as a risk to test, not
  as a fact.**
- *PowerCube is GPU-only.* If it does not present correctly, there is no
  software fallback for it at all.

### Migration plan

Each step is independently releasable and independently revertible; each
keeps the previous step's behaviour intact when the flag is off.

- **P8-0 — truthfulness, no GPU.** Answer `GET_PREFERRED_HW_RENDER` and
  `SET_HW_RENDER` with `false` explicitly rather than falling through to
  `default: return false`, and add the host-side renderer-kind query
  (additive, soft-resolved) so Dart can state what the session is doing. No
  behaviour change; removes an ambiguity.
- **P8-1 — renderer seam in the kernel.** Introduce an internal video-backend
  interface in `runtime/src/` (`cpu` | `gl`) with the current code as the
  `cpu` implementation, plus the opt-in flag plumbing. Still no GL.
- **P8-2 — context + interface.** Implement `SET_HW_RENDER`,
  `GET_PREFERRED_HW_RENDER`, `GET_HW_RENDER_INTERFACE`,
  `SET_PROC_ADDRESS_CALLBACK` and `context_reset` behind the flag. If the
  maintainer picks C, the first presentation is `glReadPixels` into `s->frame`
  and **no Dart change ships at all** — that is the cheapest possible proof
  that the command set is right.
- **P8-3 — presentation.** Only if A or B is chosen and C is insufficient:
  texture registration in Dart, upload or external texture, session
  lifecycle, and the frame-loss watchdog.
- **P8-4 — negotiation breadth.** Vulkan context, if the maintainer scopes it
  into P8; otherwise a recorded deferral with PS2 stated as not reached.
- Gates: P1 must have landed and the P1-blocked cores reached `RENDERS`
  before P8-2 starts (`ROADMAP.md` → *Sequencing rules*).

### Rollback plan

- **Fast path (the one that matters):** the opt-in flag off. `SET_HW_RENDER`
  returns `false`, every core falls back to software `video_cb`, and the
  product is byte-for-byte the product we have today. This must remain
  possible in every released build — a flag that cannot be turned off is not
  a rollback plan.
- **P8-0 and P8-1 are revertible by deleting them**; neither changes a
  published signature.
- **P8-2/P8-3 revert** is: drop the GL sources from the kernel build, delete
  the additive host queries, keep `EZCORE_ABI_VERSION` at 1. Because the
  surface grew additively, the pre-P8 binary and the post-P8 binary are
  mutually usable — the query returns "CPU" and the UI takes the old path.
- If a **dependency** was introduced under `project.md` §26, it must be
  removable without touching anything else in the build. That is a condition
  of approving it, not a hope.
- **Frame-level rollback:** if a session misbehaves on the GPU path, the
  watchdog in *Risks* (if adopted) drops that session to the CPU path without
  an app restart, and the failure is recorded in diagnostics rather than
  being a silent black screen.

### Test plan

Native (CTest, no content required):

1. `test_core_player` and `test_core_boot` pass **unmodified** with the flag
   off and on (`PLATFORM.md` §6.3). This is the primary tripwire.
2. A synth-core mode that calls `SET_HW_RENDER` with each
   `RETRO_HW_CONTEXT_*` value, plus `SET_PROC_ADDRESS_CALLBACK`, asserting the
   runtime's answers: unknown context → `false`; known context with the path
   off → `false`; with the path on → `true` with a populated interface.
3. `context_reset` handling: force a reset notification and assert the core
   re-creates its resources and frames resume, with no leak (sanitizer run).
4. Golden-frame equality: with the flag **off**, the synth core's frames are
   byte-identical to the pre-P8 output (guards the CPU path).
5. A `video_cb(NULL, w, h, pitch)` test asserting the dupe is preserved and
   re-presented — **this test is the definition of the fix for the NULL-dup
   defect**, and whether the fix is in P8's scope decides whether it is
   written here or in a separate change.

Flutter:

6. Unit tests for the opt-in flag: default off; renderer-kind query result
   drives the presentation branch; turning it off mid-session is safe.

Per-core (fork-isolated, as the existing boot tests are):

7. Boot-level checks for `geometry1`, `rcp64`, `dualscreen`, `portcomp` and
   `dreamarc` on the path-on configuration. **These need game content and
   therefore cannot be verified in-repo** — the P8 exit condition ("GL-default
   cores render on a verified platform") is satisfied by a maintainer-run
   check on the platform named in the open questions below, recorded in
   `MATRIX.md` with whatever honesty about that platform's evidence.

Platform:

8. Android: real-device check including background/foreground (context loss)
   and a driver-reset if one can be provoked. Desktop: one platform, GL and —
   if P8-4 is in scope — Vulkan.
9. `flutter analyze`, the full Flutter suite, and the Linux CTest suite stay
   green, recorded per `ROADMAP.md` → *Evidence and change rules*.

### Alternatives considered (for the item as a whole)

- **Ship `SET_HW_RENDER` returning `false` and call P8 done.** Rejected as
  dishonest: it changes no capability and would let the roadmap claim an
  unlock that has not happened.
- **Adopt a third-party frontend's video driver design wholesale.** Rejected
  as a starting point: it presumes the context question is already answered
  and smuggles a large dependency in under a capability item.
- **Defer P8 until PS2's Vulkan requirement is settled.** Rejected: Vulkan
  would then gate five GL-default cores behind a much harder target, and
  `PLATFORM.md` §6.6 forbids holding verifiable capability for a harder
  cousin.
- **Make the GPU path the only path.** Rejected: it would put the three
  render-verified cores at risk for no user-visible gain, and it removes the
  rollback that makes P8 safe to attempt at all.

### Open questions for the maintainer

These are the decisions. Nothing below is settled, and the implementation
should not start until they are answered (`project.md` §1).

1. **Context ownership: A, B, or C?** Note that A and B both require a
   Flutter external texture to get anything on screen, and differ only in who
   creates the context; C requires no UI work at all and no zero-copy. If the
   priority is "unblock the five cores with the least risk", C is the
   cheapest. If it is "make Dolphin and Flycast playable at native
   resolution", C is insufficient and the choice is A or B. **Is the first
   P8 cut an unblocking cut or a performance cut?**
2. **Which API first: `SET_HW_RENDER` alone, or `SET_HW_RENDER` +
   `GET_HW_RENDER_INTERFACE` + `SET_PROC_ADDRESS_CALLBACK` +
   `context_negotiation` together?** I have presented the full set, because a
   partial set that answers `true` to `SET_HW_RENDER` without being able to
   report context loss is the failure mode I would most want to avoid — but
   that argues for a larger first step, not automatically the right one.
3. **Which platform is "the verified platform" for the P8 exit condition?**
   Android (EGL, GLES3, the texture path, and the platform with the most
   cores in use) and Linux desktop (the platform the existing gates run on)
   are the two defensible answers and they imply different amounts of work.
   And: **is Vulkan in P8's scope at all**, given PS2 (issue #55) requires
   it and the exit condition as written says "GL-default cores"?
4. **Is the `video_cb(NULL, …)` dupe defect in P8's scope?** It is a small,
   independent correctness fix, and it is *not* caused by hardware rendering.
   My reading is that it should be its own change with its own test — but it
   touches the CPU path that P8 is simultaneously trying not to disturb, so
   it is the maintainer's call whether the two land together.
5. **`ezcore_frame_pixels` on the GPU path:** always mirror, soft-resolved
   capability query returning `NULL`, or lazy readback? And confirmation
   that **`EZCORE_ABI_VERSION` stays 1** (my reading: it should, since all
   three options are additive host-side surface).
6. **Does any new dependency get approved under `project.md` §26?** My
   reading is that the existing `dynload.h` seam is sufficient for a first
   cut and no dependency is needed at all — but Windows and macOS are where I
   am least certain, and I did not verify the platform SDK/header situation
   on either.

---

## ADR-019: Single-file core packages (`.ezpkg`)

**Status:** **Proposed** (2026-10-01). The maintainer approved the *direction*
("cores are like an exe or an apk — one file") on 2026-10-01; the format
details, the dependency, and the open questions below are not yet decided.
Program item **P2** follow-up. Platform contract: [`PLATFORM.md`](PLATFORM.md)
§4, §5, §6.8–6.9. Format spec: [`PACKAGE_FORMAT.md`](PACKAGE_FORMAT.md).

### Context (verified 2026-10-01)

- `PACKAGE_FORMAT.md` §1 already defines a package as *"a directory (or a zip
  of one)"*.
- The installer refuses every zip up front
  (`lib/services/core_package_installer.dart:147`, refusal code
  `zip_not_supported`), because no zip reader is a dependency. So the spec
  promises something the code refuses.
- Installing a third-party core today means the user picks a **folder**
  (`getDirectoryPath`, `lib/screens/core_manager_screen.dart:681`), and the
  author must hand-write `manifest.json` including a SHA-256 pin per platform.
  There is no packaging tool.
- The product goal is an OS model: anyone can build a core, hand someone one
  file, and that person can install or remove it. A folder is not a thing
  people send to each other; a file is.

### Proposed decision

1. **`.ezpkg` is a zip archive containing exactly one top-level directory,
   `<id>/`, laid out exactly as a v1 package directory** (`PACKAGE_FORMAT.md`
   §1). No new manifest fields and no new metadata — a valid `.ezpkg` is a
   valid directory package once extracted, and vice versa.
2. **Install is extract-then-validate.** The archive is extracted into a
   private staging directory under hostile-input rules (below). The existing
   validator and install pipeline then run **unchanged** on the extracted
   directory: validate → pin-verify → consent → stage. Nothing about trust
   changes: a file-installed core is **Unverified**, opt-in, never
   auto-updated (§6.9, ADR-016).
3. **A packaging tool**, `scripts/ezpkg.py` (stdlib `zipfile` + `hashlib`, no
   new dependency): `pack <dir>` validates the directory, computes the
   artifact pin for each library present, writes it into `manifest.json`, and
   emits a deterministic archive (sorted entries, fixed timestamps) so the
   same input always produces the same bytes. `check <file.ezpkg>` runs the
   same rules the app does.
4. **iOS stays excluded.** iOS forbids loading native code at runtime
   (`PLATFORM.md` §3); `.ezpkg` install is desktop and Android only.

### Extraction rules (each one is a test)

Zip archives are a well-known attack surface ("zip slip", zip bombs). Each
rule below rejects the whole package — nothing is partially extracted into
the vault:

| Rule | Rejects |
|---|---|
| Single root | any entry not under exactly one `<id>/` directory |
| Path confinement | absolute paths, drive letters, `..` segments, backslash separators, NUL bytes |
| No links | entries whose external attributes mark a symlink or a device |
| No duplicates | two entries whose paths collide after case folding (Windows/macOS file systems are case-insensitive) |
| Size caps | total uncompressed > 512 MiB (the existing `defaultMaxPackageBytes`); more than 4,096 entries |
| Bomb ratio | any entry whose uncompressed/compressed ratio exceeds 200:1 |
| Plain storage | encrypted entries; compression methods other than stored (0) and deflate (8) |
| Declared vs actual | an entry whose inflated size differs from the size the header declared |

Extraction never writes outside the staging directory, never follows links,
and enforces the size caps while inflating (not after) so a lying header
cannot exhaust disk or memory.

### Alternatives

- **Keep folder packages only.** No dependency, no new attack surface. But
  the spec/code mismatch stays, and "send someone a core" stays awkward. It
  fails the stated product goal.
- **A custom container format.** Avoids zip's quirks, but no tool on earth
  can open it, authors need our tooling just to look inside, and we would
  write a parser for a format nobody has security-reviewed. Worse on every
  axis that matters.
- **Signed packages now.** Signing is P7 and has its own ADR requirement;
  bundling it here would couple two risky changes. `.ezpkg` reserves nothing
  that blocks a later signature file inside `<id>/`.

### What could break

- A bug in path handling is the classic way an archive installer writes files
  where it should not. Mitigated by the rules above, each with a hostile
  fixture test, and by running the existing validator after extraction as a
  second line of defence.
- Adding a dependency adds supply-chain surface (`project.md` §26).
- Existing directory packages are unaffected: the directory path stays
  supported and is the code path every `.ezpkg` ends up on.

### How it would be tested

- Round trip: `ezpkg.py pack` a directory → install the `.ezpkg` → the staged
  result is byte-identical to installing the directory.
- One generated hostile archive per row of the rules table, each asserting
  refusal **and** that the vault and staging directory are left empty.
- The Python tool and the Dart installer run the same hostile fixtures, so
  the author's `check` and the user's install can never disagree.

### Open questions for the maintainer

1. **Zip reader dependency** (`project.md` §26). Options:
   (a) `package:archive` (MIT, pure Dart, widely used) — use only its parser
   and do all path/size checks ourselves, never its "extract to disk" helper;
   (b) a minimal in-repo reader for stored + deflate entries using
   `dart:io`'s `ZLibCodec(raw: true)` — no dependency, but roughly 300 lines
   of parser we must own. **Recommendation: (a)**, because a widely-used
   parser is less likely to be wrong than a new one, and our own checks sit
   on top either way.
2. **One file per platform, or one file for all platforms?** v1 layout holds
   one library per package, so the simplest `.ezpkg` is per-platform (like
   per-ABI APKs). A "fat" package carrying Linux, Windows, macOS and Android
   libraries in one file is friendlier for users but changes the v1 layout
   (`lib/<platform-key>/…`) and needs a format version bump.
   **Recommendation:** per-platform first, fat package as v2.
3. **Extension name.** `.ezpkg` is proposed; any short, unregistered
   extension works. Android file pickers match on MIME type, so the app would
   also accept `application/zip`.
4. **Removal.** Uninstalling a file-installed core already exists in the
   registry; should removal also delete that core's saved options and
   per-game overrides, or keep them in case it is reinstalled?
   **Recommendation:** keep them (§6.11, never knowingly lose user data).

---

## ADR-020: On-screen controls are data (`ezcore.controls/1`)

**Status:** **Accepted** (2026-10-01). The maintainer set the direction
(customisable on-screen buttons, reset to default, shell-like layouts such
as a DS clamshell, shipped by core packages, fully user customisable) and
delegated acceptance of the format ("do the right thing", 2026-10-01).
Program item **P4**. Built-ins, the user editor and package-supplied
layouts all use this one format. The three open questions below stay open
and do not block v1: no shell images, no analog/touch-region controls, and
family labels rather than core-descriptor labels until each is decided.

### Context

The player's touch controls were eight text chips in a row: no layout per
system, no shoulders, no shell, no customisation. `PACKAGE_FORMAT.md` already
reserves a `layouts/` directory for this, "data-only by design".

### Proposed decision

One JSON format serves built-in layouts, a user's customised copy, and
layouts a core package ships:

- `format: "ezcore.controls/1"`, `id`, `name`, `systems`, `orientation`
  (`portrait` | `landscape` | `any`), `opacity` (0.1–1).
- `screen`: where the game picture goes, as fractions of the player area,
  optionally `split: 2` with `arrange: stacked | side` and a `gap` — a DS
  frame (two screens stacked) drawn as two panels.
- `shell`: an optional fill colour, corner radius and hinge line. Declarative
  only: no images, paths or URLs in v1.
- `controls`: up to 64 of `dpad` or `button`, each a rectangle in fractions;
  a button presses one RetroPad input (`a`, `b`, `x`, `y`, `l`, `r`, `l2`,
  `r2`, `l3`, `r3`, `select`, `start`, directions) or a host action (`menu`,
  `fast_forward`); optional label (≤12 chars) and shape.

Validation is strict (`ControlLayout.parse`): unknown fields rejected, every
number range-checked, rectangles confined to the player area, ids
`[a-z0-9_]`, nothing that can execute, load or fetch. Every built-in layout
must also pass geometry rules in tests: no overlapping controls, none
covering the picture, and a Menu control so touch can always leave a game.

### Alternatives

- **Per-system hard-coded widgets.** Fast to write, impossible for a package
  or a user to change — fails the stated goal.
- **RetroArch overlay format (`.cfg` + images).** Large, image-driven and
  loosely specified; adopting it would mean parsing an ad-hoc format and
  accepting arbitrary images. May be worth an importer later, not as the
  native format.

### Open questions for the maintainer

1. Shell images (a real device photo/vector) in a later version — needs the
   same path-confinement rules as other package assets.
2. Analog sticks and a touchscreen region (DS bottom screen, PSP stick)
   depend on P3 input; reserved as future control types.
3. Labels from the core's own input descriptors (`SET_INPUT_DESCRIPTORS`)
   instead of family defaults — more accurate per core, needs a session.

---

## Open Decisions

These need to be made before Phase 1:

| # | Question | Options |
|---|---|---|
| 1 | Free tier save slots | 3 / 5 / 10 |
| 2 | Lifetime Pro slots | 500 / 1000 / Unlimited |
| 3 | Refund policy | 14-day / 30-day / No refunds |
| 4 | Family sharing | No / Yes (up to 5) |
| 5 | Open source from day 1 | Yes / No (private until launch) |
| 6 | Development pace | Full-time (36 weeks) / Part-time (52-72 weeks) |
| 7 | Team | Just you + me / + core contributors / + UI designer |
| 8 | Desktop-first or mobile-first | Desktop / Mobile / Simultaneous |

## ADR-021: Core system data — a core's own data files

**Status:** Proposed (2026-10-02). Implemented behind the manifest field it
introduces; a package without `system_data` behaves exactly as before.
Needs the maintainer's acceptance (it changes the package format).

### Context

GameCube (Dolphin) refused to boot — "codehandler.bin missing" — and PSP
(PPSSPP) warned "Core system files missing, expect bugs". Both cores look for
their own data in the libretro system directory: `dolphin-emu/Sys` and
`PPSSPP`. These folders come from each core's source tree, under the core's
own licence (GPL). They are not BIOS: no console firmware, keys or games.
The package format had no way to ship them, so every user would have had to
find and copy them by hand.

### Decision

A package may declare `"system_data": ["<folder>", ...]` and ship those
folders under `system/`. The app copies them into the system directory —
at install (into the vault next to the core), at staging for bundled cores,
and before each session — refreshing them when the core version changes.
The rules (PACKAGE_FORMAT.md §10) keep it data: exactly the declared
folders, no links, no execute bits, no executable or script signatures, size
and file caps, no BIOS file names. A same-named folder the app did not create
is left untouched.

### Consequences

- GameCube boots and PSP gets its assets with no manual setup (powercube and
  portcomp manifests declare their folders; `scripts/build_core.sh` stages
  them with `stage_system_data`).
- Data in `system/` is validated but not pinned the way the core library is.
  It cannot run, but a tampered official bundle could still change, say, a
  game-settings file. Pinning a hash of the data tree alongside the library
  is a possible follow-up.
- Downloaded (`delivery: download`) cores need the data in the download too;
  not done yet. powercube and portcomp are bundled.

### Alternatives

- **Ask users to copy the folders.** Every GameCube user would hit a boot
  failure first; rejected.
- **Point the core at the core's own folder instead of the system dir.**
  libretro has one system directory per frontend; the cores read their data
  relative to it, so this would need per-core patches.
- **Bundle the data inside the app.** Couples the app to particular cores and
  breaks the "cores are apps" model; rejected.


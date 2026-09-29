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
every third-party author. Separately, the kernel implements **13 of the 93**
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

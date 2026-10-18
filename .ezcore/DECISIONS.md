# ezCORE Current Decisions

> Snapshot date: 2026-09-23
> These entries summarize decisions currently reflected in code. Historical
> and superseded ADRs remain in [`../docs/DECISIONS.md`](../docs/DECISIONS.md).

## D-001 — C11 runtime behind ABI v1

### Decision

Keep the emulator runtime in C11 and expose the versioned pure C ABI in
`runtime/include/ezcore_runtime.h` to Dart through FFI.

### Reason

The existing runtime and libretro boundary work, have a small dependency
surface, and can be tested independently of Flutter. A language migration
would add risk without solving the current product blockers.

### Alternatives

A C++ runtime rewrite, a Rust runtime, or direct Flutter-to-core loading were
considered. They are not justified until a measured requirement appears.

### Consequences

Memory/lifecycle review and optional-symbol handling remain important. ABI
changes require compatibility planning and tests.

## D-002 — Flutter/Dart owns presentation and application coordination

### Decision

Use Flutter for the cross-platform UI and keep application state/services in
Dart. The player presents frames and sends commands; the worker/runtime owns
execution.

### Reason

One UI codebase serves the current platform targets, while an isolate keeps
native frame work out of the UI execution context.

### Alternatives

Separate native UI stacks were rejected because they multiply maintenance.
The worker is not a security sandbox; native code still runs in-process.

### Consequences

Platform seams and FFI contracts must stay explicit. UI code must not learn
core internals or branch on individual core IDs.

## D-003 — Modular, pinned libretro cores

### Decision

Treat each core as a separately versioned libretro artifact described by a
manifest and SHA-256 pin. The runtime is the only execution boundary.

### Reason

Separate artifacts preserve upstream licensing/provenance, allow independent
verification, and keep core-specific code out of the application shell.

### Alternatives

Linking all cores into one binary or allowing unverified runtime downloads was
rejected. iOS downloads executable code are prohibited by the project's
policy.

### Consequences

Every shipped platform needs a build, pin, and verification record. A core
that only compiles is not considered playable.

## D-004 — Local-first data and saves

### Decision

Keep games, settings, save states, and generated visual data local by default.
Use `SaveSyncProvider` as a seam for future providers, but do not require an
account or network.

### Reason

The product is usable offline and avoids turning a local emulator into a
service dependency. Existing user data is compatibility-sensitive.

### Alternatives

Cloud-first storage, accounts, and telemetry were considered and deferred.
Future providers must not break the local provider contract.

### Consequences

Persistence formats need explicit migration and corruption handling. Sync is
not part of the current release promise.

## D-005 — Hybrid core delivery

### Decision

Bundle ordinary cores and allow explicit on-demand downloads for the large
desktop cores. Verify downloaded bytes against the catalog pin before staging;
never download cores on iOS.

### Reason

Large optional cores otherwise dominate packages, while pin verification keeps
the same trust boundary for bundled and downloaded artifacts.

### Alternatives

One platform-wide download, a new HTTP dependency, and a hosted core store were
rejected for now. The current fetcher uses `dart:io` and the repository's
release assets.

### Consequences

A missing release asset fails honestly. Platform-specific download evidence
must be kept separate from bundle evidence.

## D-006 — Orbit is the current identity, not a hardcoded future architecture

### Decision

Keep Orbit as the current visual identity while allowing future theme and
graphics abstractions to replace direct token/widget coupling.

### Reason

Orbit is a product asset, but hardcoding it throughout the app would make
community customization and alternative platforms harder.

### Alternatives

Freezing the current direct-token design was rejected for long-term growth;
immediately building a full theme package system would be premature.

### Consequences

Theme/package work must be incremental and must preserve responsive behavior.

## D-007 — Holds and license boundaries

### Decision

Keep the Switch and 3DS slots on hold. (Updated 2026-10-18: the PS2 slot was
lifted for BIOS-free-first cores — DualVU (Play!) and LRPS2 — see
[`../docs/DECISIONS.md`](../docs/DECISIONS.md) ADR-023.) Do not distribute
ROMs, BIOS, firmware, keys, or unlicensed core binaries. Preserve per-core
provenance and license checks.

### Reason

These boundaries reduce legal, licensing, and circumvention risk for the
project and its users.

### Alternatives

Adding held cores or bundling user content was rejected. The project will not
silently change these boundaries without maintainer and licensing review.

### Consequences

Some planned systems remain reserved rather than silently unavailable. New
core work must pass provenance, license, and policy gates first.

## D-008 — README is a trust surface

### Decision

Rewrite the public README around the current product identity, verified
capabilities, clear limitations, build/download paths, contribution guidance,
and optional sponsorship. Keep the writing concise and human rather than using
exaggerated compatibility or feature claims.

### Reason

The README is often the first and only page a potential user or contributor
sees. Clear boundaries build more trust than a longer list of promises, and a
professional presentation helps the project compete for attention without
disguising its experimental state.

### Alternatives

Keeping the previous emoji-heavy marketing copy was rejected because it mixed
historical claims with current behavior. A feature-complete launch page was
also rejected because the roadmap and matrix are not uniformly complete.

### Consequences

README updates are part of project-control work. When implementation or
verification changes, the README must be checked for stale claims alongside the
matrix and release documentation.

# ezCORE — platform readiness plan

**Derived from** `main` @ `6c5f36f` (2026-09-29), every figure re-measured rather
than quoted from an older doc. Anything I could not verify is marked UNVERIFIED
instead of assumed.

## Where we actually are

| Gate | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **567 pass / 5 skip / 0 fail** |
| `ctest` | **14/14** |
| Released | `v0.2.0` — Linux x64 + Android only |

21 cores carry a `delivery` map. A further 3 (`citra_hold`, `ps2_hold`,
`switch_hold`) are the project's legal holds and record no delivery at all.
Measured from `cores/catalog.json`:

| Platform | bundled | on-demand | absent |
|---|---|---|---|
| linux | 11 | 3 | 4 (+3 no key) |
| windows | 11 | 3 | 7 |
| macos | 11 | 3 | 7 |
| android | 7 | 0 | 14 |
| **ios** | **6** | 0 | **15** |

The desktop three are symmetric and healthy. **Mobile is the hole** — iOS has
6 of 21 and Android 7, and neither has a single on-demand core.

## Answering the question directly

"What remains to be fully ready for all platforms, emulators, features?"

Five things, in dependency order. Nothing here is guesswork; each item is a
measured gap.

---

## 1. Finish P1 — the keystone, and the gate on everything else

`ROADMAP.md:147` forbids starting P5/P6/P8/P9 until P1 lands **and** the six
blocked cores reach RENDERS. P1 is partly done and partly not:

| P1 exit criterion | State | Evidence |
|---|---|---|
| `docs/API.md` + `ARCHITECTURE.md` exist | done | 20,072 B / 8,423 B |
| Core options implemented | **done** | `runtime.c:250` `SET_CORE_OPTIONS_V2`, `:291` `_INTL` |
| A test fails if a header symbol is undocumented | **MISSING** | no `api_doc`/`abi_doc` test in `test/` |
| `GET_MEMORY_MAPS` | **done** — `runtime.c:857,861` exports both halves. *This row was wrong when first written; the plan measured `GET_MEMORY_MAPS` as 0 hits when the real gap was that `SET_MEMORY_MAPS` was captured but the per-port `SET_CONTROLLER_INFO` content had no reader.* |
| `GET_CONTROLLER_INFO` | **now done** — `runtime.c:857,862` add `ezcore_get_controller_port_type{,_count}` (memory-map readers at `:874,878`) plus Dart wrappers, with a C test proving order, per-port counts and bounds refusal |
| 6 blocked cores → RENDERS | **blocked** | all 6 need `hw_render` |

**This is the single highest-value item on the board.** The missing doc gate is
precisely what let `7 of 92` sit wrong in six files for months — the count was
never checked by anything. Adding it is small and it makes every later doc edit
self-verifying.

**Blocked cores — all 6 need `hw_render`**, and the required backend is now
known from the binaries themselves:

| Core | Evidence from the binary | Backend needed |
|---|---|---|
| `portcomp` | vulkan 974, gl 397 | **Vulkan** |
| `powercube` | vulkan 647, gl 126 | **Vulkan** |
| `geometry1` | vulkan 596, gl 188 | **Vulkan** |
| `dreamarc` | vulkan 223, gl 191 | **Vulkan** |
| `rcp64` | gl 3275, vulkan 0, metal 0 | **OpenGL**, not Metal |
| `dualscreen` | gl 27 | **OpenGL** |

Method: `strings` counts of backend symbols in each staged `.so`, not an
assumption. An earlier draft of this file claimed `rcp64` needed Metal from a
loose substring match; it has **zero** Metal symbols and 3275 GL ones, so that
claim was wrong and is corrected here.

All 6 call `SET_HW_RENDER`; the 4 with heavy Vulkan linkage are the ones worth
starting with, because a Vulkan surface unblocks four cores for one piece of
work. `rcp64` and `dualscreen` need a GL context, which is a different and
smaller job.

So P8 is not "some GPU support" — it is a **Vulkan surface for four cores and
a GL context for two**, and none of them can reach RENDERS without it. This also
shapes ADR-018: context ownership has to be answered per-backend, not once.

## 2. P8 — the GPU path (unblocks 6 cores)

`env_cb` answers **22 of 93** environment commands. The four that matter for
these cores are `SET_HW_RENDER`, `GET_PREFERRED_HW_RENDER`,
`SET_PROC_ADDRESS_CALLBACK`, `GET_HW_RENDER_INTERFACE` — none implemented.

ADR-018 is **Proposed, not Accepted**. Per the rule that a gate cannot be
skipped, this needs your decision on context ownership before implementation
starts. This is the biggest single engineering item on the board.

## 3. Mobile delivery — the actual "all platforms" gap

Not a P-item; it's tooling, and it is what makes the app unavailable rather than
merely less complete.

- ~~**`scripts/ios_frameworks.sh` — MISSING.**~~ **NOW WRITTEN.** The dangling
  reference at `scripts/release.sh:18` is resolved. It wraps each staged
  `native/cores-ios-arm64/<id>/*.dylib` into an `<id>.framework` bundle with an
  `Info.plist` and an `@rpath`-correct install name, skips the legal-hold cores
  so a blocked core can never reach an archive, and has a `--check` mode that
  fails on a missing/malformed bundle or an install name that disagrees with
  its path — the corruption that would otherwise only surface as a `dlopen`
  failure on a user's device. It deliberately does NOT re-patch minos:
  `ios_fix_min_version` (core_platform.sh:74) already does that at stage time
  and refuses the build if it fails; re-patching here would rewrite the bytes
  the committed pins were computed from. **iOS still has no verified
  artifact** — this makes iOS *buildable*; issue #65 still has to produce and
  verify one on a macOS host.
- ~~**`scripts/android-stubs/` — MISSING.**~~ **NOW SHIPPED.** Required by
  `scripts/build_core.sh:299` for cardcon's `-lrt` linker stub. `librt.so` is a
  text GNU ld script (`INPUT(-lc)`) that satisfies `-lrt` on bionic, which has
  no librt, and contributes no definitions of its own so it can never shadow a
  real libc symbol. Covered by `test/android_stub_test.dart`, which links a
  renamed copy and runs it, with a negative control proving the stub is
  load-bearing. Android still tops out at 7 bundled cores until the next
  release re-pins, so treat that count as not-yet-advanced.
- **0 on-demand cores on either mobile platform.** Desktop has 3 each; mobile
  has none. Either the on-demand path is unported to mobile, or it is
  intentionally off — either way it is undocumented.

**Consequence: only `v0.2.0` (Linux + Android) is a verified artifact.
Windows, macOS and iOS have delivery flags in the catalog but no verified
build.** Do not describe them as shipping until issue #65 produces binaries.

## 4. P6 — crash containment (a core crash still kills the app)

The seam and the exit-code contract are proven (`EZCORE_CRASH_AFTER` → rc 9,
`crash_signal_exit_code` CTest). **But `supervisedProcess` throws
`UnsupportedContainmentError` and no child process is ever spawned.** A
segfaulting core still takes the app with it.

Gated on P1, and it should stay gated — the P1 note about large layers built on
an unfinished kernel contract is exactly this case.

## 5. Trust, signing, and content (P5/P7 + the honesty items)

- **P7** — `cores/registry.json` is 481 bytes with no production reader. Either
  make it real or delete it.
- **P5** — trust tiers, so unverified cores are opt-in and never auto-updated.
- **EZC-015** — `gambatte`, `blastproc`, `coinbox`, `superfx` hold pinned
  artifacts and matrix RENDERS evidence but are `absent` on all 5 platforms.
  Three are non-commercial-licence; `gambatte` is GPL-2.0-only and therefore
  distributable. Flipping it is a §28 decision and needs your call.
- **EZC-017** — the `crash_core` fixture fails the RENDERS restore gate. No
  real core is affected (all 18 staged cores: zero exit-6), so it is fixture
  work, not a gate defect.
- **Re-run the boot matrix before the next release.** #81 made RENDERS stricter;
  6 cores sit at IDENTIFIES and could turn red.

## Explicitly not planned

- **P4** (skins/touch layouts) and **P9** (Tier-2 engines) — both downstream of
  P3 and P6 respectively, and neither is needed for "playable on every
  platform".
- **P6 before P1, P8 before P1** — forbidden by `ROADMAP.md:147` and I am not
  going to quietly work around a rule you wrote.

## Recommended order

1. ~~**P1 doc gate**~~ — **DONE**, and extended: `check_api_docs.py` for
   the ezCORE ABI plus a new `check_env_coverage_docs.py` for the libretro
   capability figure, both wired into ctest (14 -> 15).
2. ~~**`GET_MEMORY_MAPS` + `GET_CONTROLLER_INFO`**~~ — **DONE.** Memory maps
   were already complete. Controller-info *reads* were added (see the P1 table).
   The doc gate is also in.
3. **Decide ADR-018** — your call, gates all of P8
4. **P8 Vulkan (desktop)** then **Metal (Apple)** — unblocks 4 + 2 cores
5. ~~**`ios_frameworks.sh`**~~ — **done.** Both halves of this item are now
   written; what remains is *verifying* them, which needs a macOS host and is
   issue #65's work.
6. **P6 real supervision** — once P1 is closed
7. **P5/P7 trust + EZC-015 decision** — before public release

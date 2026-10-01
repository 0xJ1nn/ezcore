# ezCORE Core × Platform Matrix

> **Last verified:** 2026-09-28 — P1b capability surface merged: `env_cb` answers
> **17 of the 93** environment requests (core options v2 + intl, input
> descriptors, controller info, memory maps), with the Dart bindings, the
> 4-layer global/system/core/game resolver, and the worker protocol landed via
> #45/#48/#50. The option surface removes the kernel blocker for frame
> verification of the built-but-unverified systems; their RENDERS evidence
> still accrues per system below. The `linux-x64` tier was rebuilt on the
> current toolchain and re-pinned — `fix/linux-x64-repin`; native ctest 14/14
> including `boot_pocketbit`; the app stages 14 bundled cores with zero pin
> refusals. macOS arm64 remains run-verified from v0.1.1 (2026-09-19).
>
> Re-check the kernel coverage count against the **vendored** header before
> quoting it — see the note in [`../ROADMAP.md`](../ROADMAP.md):
>
> ```bash
> grep -o 'RETRO_ENVIRONMENT_[A-Z0-9_]*' \
>   runtime/external/libretro-common/include/libretro.h | sort -u | wc -l   # -> 93
> grep -oE 'case RETRO_ENVIRONMENT_[A-Z0-9_]+' \
>   runtime/src/runtime.c | sort -u | wc -l                               # -> 13
> ```
>
> **Refresh:** build the tier (`scripts/build_core.sh`), then
> `flutter test test/core_matrix_test.dart` (subprocess-isolated harness).
>
> **2026-09-23 audit note:** the current committed manifests contain no
> `ios-arm64` artifact pins. Historical `BUILT` iOS cells below are retained as
> dated evidence, not current distribution or runtime proof; see
> [`.ezcore/CORE_MATRIX.md`](../.ezcore/CORE_MATRIX.md) for the conservative
> snapshot.

### Fixture provenance (corrected 2026-09-29)

The local-only fixture set is **three ROMs, one of which is CC0** — not three
CC0 ROMs. Per-file, with evidence:

| Fixture | Status | Evidence |
|---|---|---|
| `ezcore_nes_minimal.nes` | **CC0 / public domain** — self-authored, generated in-tree | generator prints `License: CC0 / public domain (original code)` at `scripts/gen_nes_minimal_rom.py:136`; header comment `scripts/gen_nes_minimal_rom.py:10` |
| `cpu_instrs.gb` | **Copyrighted** — Blargg's CPU instruction test suite, no CC0/PD grant in-tree | consumed by `boot_pocketbit` (`runtime/CMakeLists.txt:278-281`) and mapped at `test/core_matrix_test.dart:52-53`; suite described as "(Blargg)" in the Fixtures section below |
| `test.gba` | **No declared licence** — third-party GBA homebrew (4 KB OBJTEST) | consumed by `boot_advancebit` (`runtime/CMakeLists.txt:283-286`) and mapped at `test/core_matrix_test.dart:54` |

Only the generated NES ROM carries a redistribution statement. The other two
have no per-file LICENSE and are developer-local only
(`native/test-roms/` is gitignored), which is why neither may enter a bundle.

**Honest record of the correction:** this file contained no literal
"3 CC0 test ROMs" sentence before this commit — the header carried no CC0
claim at all, and the Fixtures list below described the ROMs without per-file
licence status. This block adds the provenance that was missing; no prior
"CC0" wording was overwritten. Stated per project.md §30 rather than silently
rewriting the header as if it had been wrong.

## Local test content (2026-10-01)

Boot evidence dated 2026-10-01 used homebrew, freeware and shareware files
downloaded from archive.org with maintainer approval. They are **not in the
repository** and never bundled; they live in a developer-local folder with a
`SOURCES.md` that records each file's archive.org item and SHA-256. Items:
`controller-test-roms` (N64/GB/GBA/Genesis/Dreamcast/PSP test ROMs),
`240p-test-suite-ps-1`, `240p_Test_Suite_v1.07_by_Artemio_Ua_PD`,
`worldofsand-ds`, `cryptofthefungallord-dreamcast`, `doom_20230531`,
`harry9c7_gmail_SKY`, `lsdoom`, `yokero-v-1.0.1.7z`. A Nintendo factory test
cartridge in the controller pack is **not** used as evidence for any row.
Re-running a row: `EZCORE_BOOT_OPTIONS="k=v;..." runtime/build-linux/test_core_boot <core> <rom>`
(options support: #92).

## Levels

| Level | Meaning | How proven |
|---|---|---|
| `—` | Not attempted | — |
| BUILT | Compiles + links for the target triple | `file`/`readelf`/`vtool` arch + platform + minos, `nm` retro exports |
| PINNED | sha256 recorded in `cores/<id>/manifest.json` | `scripts/pin_artifacts.py` + review |
| IDENTIFIES | Loads + inits; the harness **prints** the reported name and version | `test_core_boot --identify-only` exit 0 |
| RENDERS | Boots content: 30 frames, a nonzero pre-restore pixel sum, and a serialize/`ezcore_unserialize` round trip whose post-restore pixel sum stays within `RESTORE_PIXEL_SUM_TOLERANCE_REL` (2%) | `test_core_boot <rom>` exit 0 |
| SHIPPED | In `release.sh` bundles for that OS | Bundle inspection |

Rules: pins are evidence, never aspirational (`pin_artifacts.py` refuses
blocked cores). iOS entries must be interpreter (manifest validation
enforces; `TIER_IOS` excludes JIT-default cores until flags are verified).

**Harness limits on IDENTIFIES and RENDERS** (corrected 2026-09-29 — both
levels previously claimed more than the harness asserts):

- `IDENTIFIES` proves load + init only. `run_identify_only` prints
  `ezcore_core_name`/`ezcore_core_version` at `runtime/test/test_core_boot.c:159`
  and returns 0 unconditionally at `runtime/test/test_core_boot.c:161`; the
  printed name is **never checked for NULL or emptiness**. A core that
  reports an empty name still earns IDENTIFIES.
- `RENDERS` now checks state fidelity, not just that a round trip was
  callable. The **pre**-restore pixel sum is asserted nonzero (a zero sum
  returns 3), and the **post**-restore sum must stay within
  `RESTORE_PIXEL_SUM_TOLERANCE_REL` (2%) of it or the harness exits 6. The
  tolerance is deliberate: the harness cannot distinguish "restore lost
  pixels" from "this renderer is not a pure function of emulated state", so
  exact equality would fail cores that are correct.
- What the RENDERS gate is **still not**: pixel-exact. A 2% sum tolerance is a
  loose smoke gate — a core that swaps two equally-weighted sprites can still
  pass. The drained audio frame count and the `cheat_reset`/`cheat_set` calls
  remain print-only and are not asserted at all.

## Cores × platforms

| Core | macOS arm64 | iOS arm64 | Android arm64 | Linux x64 | Windows x64 | Notes |
|---|---|---|---|---|---|---|
| pocketbit | RENDERS | BUILT | BUILT | BUILT | — | iOS needed `ios-arm64` + gmake4 + serial (pb12 race); Linux verified with live boot test (Damuel.gb: load/init/frames/save-restore) |
| gambatte | RENDERS ⚠ | BUILT | BUILT | — | — | ⚠ **Catalog contradiction:** `cores/catalog.json` records `delivery: absent` on *all five* platforms, so staging ships it nowhere, while artifact pins exist for `macos-arm64` / `linux-x64` / `android-arm64`. Its licence is **GPL-2.0-only** (distributable — unlike `superfx`/`blastproc`/`coinbox`, which are non-commercial and are correctly `absent`). A pin plus a RENDERS result implies it was meant to ship. Resolving this is a distribution decision under `project.md` §28, not a docs edit — tracked, see `.ezcore/KNOWN_ISSUES.md`. Android via `unix` (no android branch upstream) |
| advancebit | RENDERS | — | BUILT | BUILT | — | iOS excluded: dynarec default unverified; Android needed `-Wno-error=int-conversion` (NDK r27) |
| nesbyte | IDENTIFIES | BUILT | BUILT | BUILT | — | iOS needed `ios-arm64` (TLS requires minos 9+). **Cell is one run behind its own infrastructure:** the CC0 fixture is on disk, a `boot_nesbyte` CTest is registered (`runtime/CMakeLists.txt:288-291`) and the Dart matrix maps it (`test/core_matrix_test.dart:55`), so promoting to RENDERS needs only running the existing harness — `ctest -R boot_nesbyte` or `flutter test test/core_matrix_test.dart`. Not promoted here: no harness was run for this edit, so the result would be unverified (project.md §74) |
| superfx | IDENTIFIES (not distributed) | BUILT | BUILT | — | — | Non-commercial license — no binaries shipped; recipe only. Android via `unix` (no android branch upstream) |
| blastproc | IDENTIFIES (not distributed) | BUILT | BUILT | RENDERS (not distributed, 2026-10-01) | — | Linux: Genesis Plus GX boots the 240p Test Suite (Genesis). Non-commercial license — no binaries shipped; recipe only. Android via `unix` |
| joystick | IDENTIFIES | BUILT | BUILT | BUILT | — | Android needed `PTHREAD_FLAGS=` (no libpthread in NDK) |
| cardcon | IDENTIFIES | BUILT | BUILT | BUILT | — | Android needed `-lrt` wrapper (NDK has no librt) |
| realmode | IDENTIFIES | BUILT | BUILT | BUILT · frames, no state (2026-10-01) | — | Linux: DOSBox Pure renders its start menu (640×400) from the DOOM shareware installer zip, but refuses to serialize until a program runs ("Unable to save state while game is not running"), so not RENDERS. Needs a self-running DOS fixture. Android needed `ISMAC=` + NDK `STRIP`; all-interpreter (perf caveat) |
| coinbox | IDENTIFIES | BUILT | BUILT | — | — | All-interpreter on 64-bit (Cyclone is 32-bit ARM only) |
| pointclick | IDENTIFIES | — | BUILT | BUILT · **crashes** (2026-10-01) | — | Linux: ScummVM segfaults after failing to open *Beneath a Steel Sky* given as a bare `sky.dsk` (no `sky.cpt`, no game directory) — a content-shape problem, but a crash on bad input still kills the app (P6). macOS first build 2026-09-19 (freetype zconf.h patch was being reverted by their configure step — see build_core.sh); Android arm64 staged + pinned the same day |
| geometry1 | IDENTIFIES | — | — | **RENDERS** (2026-10-01) | — | Linux: SwanStation boots the 240p Test Suite (PS1) on its **default software renderer** — 256×224, restore within 2%. The old "needs GL" note was wrong for this core. Fixture is local-only (see *Local test content*) |
| rcp64 | IDENTIFIES | — | — | BUILT · **RENDERS on #93 build** (2026-10-01) | — | Default GLideN64 refuses without GL. The currently pinned Linux artifact has **no Angrylion compiled** (asking for it crashes in `plugin_start_gfx`); the #93 build (`HAVE_THR_AL=1 HAVE_PARALLEL_RSP=1 LLE=1`) with `mupen64plus-rdp-plugin=angrylion` + `rsp-plugin=parallel` (or `cxd4`) reaches RENDERS on two N64 homebrew ROMs, 640×480, restore exact. Needs #89 (option delivery) and #92 (harness options); app default via #94 |
| dualscreen | IDENTIFIES | — | — | **RENDERS** (2026-10-01) | — | Linux: boots *World of Sand* (DS homebrew) on defaults — 256×384, restore exact. The old "needs core options" note no longer applies |
| portcomp | IDENTIFIES | — | — | BUILT · **crashes on load** (2026-10-01) | — | Linux: PPSSPP renders zero pixels without a GPU context, then aborts (`terminate called without an active exception`, SIGABRT) — in the app this kills ezCORE (P6). Needs P8 |
| dreamarc | IDENTIFIES | — | — | BUILT · load refused (2026-10-01) | — | Linux: Flycast refuses `load_game` on a Dreamcast homebrew `.cdi` without a GPU context. Needs P8 |
| powercube | IDENTIFIES | — (delivery absent) | — | BUILT · load refused (2026-10-01) | — | Linux: Dolphin (Null video backend) refuses to boot a GameCube homebrew `.dol`. No software renderer exists: needs P8 |
| twinsh | IDENTIFIES | — | — | BUILT | — | SH-2 interpreter; slow by nature, frames unverified |
| citra/switch/ps2 | holds | holds | holds | holds | holds | Holds, never built |

## Platform shells & app builds

| Platform | Shell | App build | Audio sink | Gamepad | Notes |
|---|---|---|---|---|---|
| macOS | ✅ | ✅ debug (+ release via release.sh) | AVAudioEngine ✅ | GCController ✅ | Sandbox bookmarks wired; E2E pending human run |
| Linux | ✅ (`flutter create`) | CI | ALSA/FFI (code, unverified) | evdev (code, unverified) | Never executed here; CI leg covers |
| Windows | ✅ (renamed binary) | CI | waveOut/FFI (code, unverified) | XInput/FFI (code, unverified) | `dynload_win32.c` compiles on CI |
| Android | ✅ | ✅ debug APK | AudioTrack ✅ (code) | KeyEvent ✅ (code) | Needs device run; cores verified ELF+symbols |
| iOS | ✅ (15.0 floor) | release build w/ 15.0 pods fix (verifying) | AVAudioEngine ✅ (code) | GCController ✅ (code) | No sim/device here; cores verified Mach-O+symbols |

## Xcode 27 notes (paid forward)

- `libretro-deps/.../libmad/VERSION` (upstream audit stamp) shadows C++20
  `<version>` on case-insensitive APFS → recipe deletes it pre-build with
  `DEBUG_ALLOW_DIRTY_SUBMODULES=1` so their configure script doesn't
  `git reset --hard` it back mid-build.
- SameBoy BootROMs need GNU make 4+ (`realpath`) and a serial build
  (parallel-unsafe pb12 link).
- iOS links need `ios-arm64` (plain `ios` = armv7) and a post-link
  `vtool -set-build-version` to minos 15.0 (makefiles only set it for
  compiles).
- iOS deployment floor is 15.0 (Xcode 27); core minos normalized to match.

## Fixtures

`native/test-roms/` (gitignored, local-only): `cpu_instrs.gb` (Blargg —
copyrighted), `test.gba` (4 KB OBJTEST homebrew — **no declared licence**),
`ezcore_nes_minimal.nes` (**CC0**, self-authored). Three fixtures, one CC0 —
see the provenance table above. RENDERS-level coverage beyond
GB/GBC/GBA needs sourced public-domain homebrew per system + per-file
LICENSE (the `test/fixtures/` allowlist in `banned_content_scan.sh`
exists for exactly this) — open item, tracked in RELEASE_PLAN.

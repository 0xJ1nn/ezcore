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
> dated evidence, not current distribution or runtime proof.

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
"CC0" wording was overwritten. Stated openly rather than silently
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

**What a RENDERS row must also carry (2026-11-21).** A nonzero pixel sum and a
successful save/restore are not enough on their own — a row that names no
stored frame has no frame evidence. Set `EZCORE_FRAME_PPM=<path>` when running
`test_core_boot <rom>`: after the frame budget the harness writes the last
frame as a binary PPM (P6, 8-bit RGB) and prints exactly one line,
`frame: <width>x<height> sum=<pixelsum> sha256=<hex> file=<path>`, where the
hash is SHA-256 over the RGB bytes and the sum is the pixel sum printed above
it. A frame is evidence only for the RENDERS row of that exact core build fed
that exact content, and only when it differs from the frame the same build
draws for a file from another system (or when that core correctly refuses the
foreign file). It is not evidence for BUILT, PINNED, IDENTIFIES or SHIPPED, for
a different core build, or for a row whose cell has not actually been upgraded
against a stored frame. Where the destination cannot be opened the harness now
fails with exit 7 rather than skipping, so a claimed frame cannot turn out to
be a file that was never written.

A stored frame is evidence for its core build and its content. A hash that
repeats across two different inputs is decoration, not rendering — a core that
paints one picture for an NES file and a GBA cartridge earns no RENDERS claim,
which is what happened to `geometry1`. This change sets the rule only; no cell
is promoted to RENDERS here, because the claims wait for captured frames.

**Harness limits on IDENTIFIES and RENDERS** (corrected 2026-09-29 — both
levels previously claimed more than the harness asserts):

- `IDENTIFIES` proves load + init only. `run_identify_only` prints
  `ezcore_core_name`/`ezcore_core_version` at `runtime/test/test_core_boot.c:407`
  and returns 0 unconditionally at `runtime/test/test_core_boot.c:409`; the
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
| pocketbit | BUILT | BUILT | BUILT | BUILT | — | iOS needed `ios-arm64` + gmake4 + serial (pb12 race). The recorded boot ran on Linux, not macOS; no frame was recorded, so RENDERS is not established for either cell (frame rule at :82-90) |
| gambatte | BUILT | BUILT | BUILT | — | — | ⚠ Catalog contradiction: `cores/catalog.json` records `delivery: absent` on all five platforms while artifact pins exist for macOS/Linux/Android; licence is GPL-2.0-only. The macOS cell has no `boot_gambatte` ctest and no in-tree fixture, so the recorded boot is not reproducible here; no frame was recorded, so RENDERS is not established (frame rule at :82-90). Resolving the distribution conflict is a maintainer decision. Android via `unix` (no android branch upstream) |
| advancebit | BUILT | — | BUILT | BUILT | — | iOS excluded: dynarec default unverified. The `boot_advancebit` ctest is fixture-gated in `runtime/CMakeLists.txt` and the fixture is absent from the tree, so the recorded boot is not reproducible here; no frame was recorded, so RENDERS is not established (frame rule at :82-90). Android needed `-Wno-error=int-conversion` (NDK r27) |
| nesbyte | IDENTIFIES | BUILT | BUILT | BUILT | — | Linux: the recorded `ctest -R boot_nesbyte` run used the generated CC0 ROM, which is local-only and absent from the tree; its restore stayed within 2% (`runtime/test/test_core_boot.c:98`), a smoke gate, not pixel equality. No frame was recorded, so RENDERS is not established (frame rule at :82-90). iOS needed `ios-arm64` (TLS requires minos 9+) |
| superfx | IDENTIFIES | BUILT | BUILT | — | — | Non-commercial licence — no binaries shipped; recipe only (delivery absent on all five platforms, `cores/catalog.json`). Android via `unix` (no android branch upstream) |
| blastproc | IDENTIFIES | BUILT | BUILT | BUILT | — | Linux: no `boot_blastproc` ctest and no in-tree fixture, so the recorded boot is not reproducible here; no frame was recorded, so RENDERS is not established (frame rule at :82-90). Non-commercial licence — no binaries shipped; recipe only (delivery absent on all five platforms, `cores/catalog.json`). Android via `unix` |
| joystick | IDENTIFIES | BUILT | BUILT | BUILT | — | Android needed `PTHREAD_FLAGS=` (no libpthread in NDK) |
| cardcon | IDENTIFIES | BUILT | BUILT | BUILT | — | Android needed `-lrt` wrapper (NDK has no librt) |
| realmode | IDENTIFIES | BUILT | BUILT | BUILT | — | Linux: the recorded boot opened the DOS start menu, but serialize was refused until a program runs, so this is not RENDERS; no frame was recorded (frame rule at :82-90). Needs a self-running DOS fixture. Android needed `ISMAC=` + NDK `STRIP`; all-interpreter (perf caveat) |
| coinbox | IDENTIFIES | BUILT | BUILT | — | — | All-interpreter on 64-bit (Cyclone is 32-bit ARM only) |
| pointclick | IDENTIFIES | — | BUILT | BUILT | — | Linux: a recorded run crashed on a bare `sky.dsk`; the exit-9 crash classification is proven in `runtime/test/test_core_boot.c` and `runtime/test/test_crash_signal.c`, but the event has no in-tree log and is not asserted here. macOS first build 2026-09-19 (freetype zconf.h patch was being reverted by their configure step — see build_core.sh); Android arm64 staged + pinned the same day |
| geometry1 | IDENTIFIES | — | — | BUILT | — | Linux: a recorded negative control fed a NES file and a GBA cartridge; the core accepted both and produced the same picture it draws for its own content, so video output cannot evidence PlayStation rendering. Loading, init and save-restore stand; the earlier RENDERS row is withdrawn. No frame was recorded (frame rule at :82-90). Restoring the row needs one real PSX image whose frame differs from a negative control |
| rcp64 | IDENTIFIES | — | — | BUILT | — | Linux: a recorded run used GLideN64 via `EZCORE_BOOT_OPTIONS`; the committed default RDP plugin is `angrylion` (`cores/rcp64/manifest.json:49`), so GLideN64 was an override, not the default. The recorded restore stayed within 2% (`runtime/test/test_core_boot.c:98`). No frame was recorded, so RENDERS is not established (frame rule at :82-90) |
| dualscreen | IDENTIFIES | — | — | BUILT | — | Linux: a recorded boot on defaults reached save-restore within 2% (`runtime/test/test_core_boot.c:98`). No frame was recorded, so RENDERS is not established (frame rule at :82-90) |
| portcomp | IDENTIFIES | — | — | BUILT | — | Linux: a recorded PPSSPP boot used `EZCORE_BOOT_FRAMES=300 EZCORE_BOOT_PACE=1` because PPSSPP draws on its own thread, and reached save-restore within 2% (`runtime/test/test_core_boot.c:98`). No frame was recorded, so RENDERS is not established (frame rule at :82-90) |
| dreamarc | IDENTIFIES | — | — | BUILT | — | Linux: a recorded Flycast boot on OpenGL reached save-restore within 2% (`runtime/test/test_core_boot.c:98`), but the harness frame was black, so it does not evidence content rendering. No frame was recorded, so RENDERS is not established (frame rule at :82-90) |
| powercube | IDENTIFIES | — | — | BUILT | — | iOS: `delivery.ios` is `bundled` (`cores/powercube/manifest.json:44`, `cores/catalog.json:922`); the note at `cores/powercube/manifest.json:38` says absent. Linux: a recorded Dolphin boot reached save-restore within 2% (`runtime/test/test_core_boot.c:98`). No frame was recorded, so RENDERS is not established (frame rule at :82-90) |
| twinsh | IDENTIFIES | — | — | BUILT | — | SH-2 interpreter; slow by nature, frames unverified |
| lrps2 | — | — | — | BUILT | — | Linux x64: a recorded LRPS2 boot used a user-supplied BIOS and stayed within the 2% restore tolerance (`runtime/test/test_core_boot.c:98`). BIOS and content are local-only, never in the repository. No frame was recorded, so RENDERS is not established (frame rule at :82-90). Catalog entry: `cores/lrps2/manifest.json` (delivery `linux: bundled`; BIOS gated at `pcsx2/bios`) |
| dualvu | — | — | — | BUILT | — | Linux x64: a recorded BIOS-free Play! `ui_libretro` boot (pinned d44bfa1) stayed within the 2% restore tolerance (`runtime/test/test_core_boot.c:98`); the `boot_dualvu` ctest is fixture-gated and the ELF is absent from the tree. No frame was recorded, so RENDERS is not established (frame rule at :82-90). Fixture is local-only, never committed. Catalog entry: `cores/dualvu/manifest.json` (delivery `linux: absent` — `cores/dualvu/manifest.json:30`, `cores/catalog.json:371`; artifact pinned) |
| citra/switch | holds | holds | holds | holds | holds | Holds, never built |

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
exists for exactly this) — open item.

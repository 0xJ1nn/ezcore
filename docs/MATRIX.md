# ezCORE Core × Platform Matrix

> **Handhelds verified 2026-11-22.** `potator` was promoted to RENDERS on Linux x64
> against two different licence-clean Supervision programs whose recorded frames
> differ, and `gw` gained its first real content run: it draws, refuses foreign
> files, and stays at IDENTIFIES because its core reports no save states — the
> level definition below requires a serialize round trip, and the claim stops
> where the harness stops.
>
> **Playability sweep 2026-11-22.** Every built Linux x64 core with
> licence-clean content was run through `test_core_boot` with frame capture, each
> positive case twice, plus a foreign-file control. Two cells moved up:
> `joystick` (Atari 2600, BUILT → RENDERS) against an original CC0 hand-assembled
> homebrew program, and `dualscreen` (NDS, BOOTS → RENDERS) against two CC0 NDS
> homebrew ROMs. `nesbyte`, `pocketbit`, `advancebit`, `rcp64`, `potator` and `gw`
> were re-measured and keep their levels — the captured hashes for `nesbyte`'s
> 240p frame, both `potator` frames and both `gw` panels reproduce the values
> already recorded below byte for byte. Five built cores (`cardcon`, `geometry1`,
> `portcomp`, `realmode`, `twinsh`) had no local legal content, so no new claim is
> made for them. SNES (`superfx`) and Genesis (`blastproc`) have manifests but no
> source in this tree and could not be built here. The harness gained a
> `frame_hash_reproducible` CTest (two runs must print the same frame SHA-256 and
> it must match the stored PPM's RGB bytes); full native ctest 23/23.
>
> **Verified again 2026-11-21.** The boot harness now records the frame it drew:
> `EZCORE_FRAME_PPM=<path>` writes the last frame as a binary PPM and prints its
> SHA-256. Four Linux cells were promoted to RENDERS against a captured frame
> with a differing negative control — `pocketbit`, `advancebit`, `nesbyte`,
> `rcp64` — and each hash reproduced on a second run. The dated note below is
> kept as the record of what was true on 2026-09-28.
>
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
| BOOTS | Loads real content, runs the frame budget, produces a nonzero pre-restore pixel sum, and survives a serialize/`ezcore_unserialize` round trip whose post-restore pixel sum stays within `RESTORE_PIXEL_SUM_TOLERANCE_REL` (2%) — but no frame was kept, so the picture itself is unverified | `test_core_boot <rom>` exit 0, no `EZCORE_FRAME_PPM` |
| RENDERS | BOOTS, plus a recorded frame that differs from the same build fed a file from another system (or that core refusing that file) | BOOTS, plus `EZCORE_FRAME_PPM` and one control run |
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

The frame budget changes the frame, so a recorded hash is comparable only at
the budget it was taken at. The default is 30 frames; where a note names a
larger budget, the hash was taken with `EZCORE_BOOT_FRAMES` set to that value.
The same build on the same content at the same budget reproduces the same
hash, which was checked by running each promoted case twice.

A stored frame is evidence for its core build and its content. A hash that
repeats across two different inputs is decoration, not rendering — a core that
paints one picture for an NES file and a GBA cartridge earns no RENDERS claim,
which is what happened to `geometry1`. Four Linux cells were promoted on
2026-11-21 against a captured frame; the rest stay BUILT until someone captures
one, because what is missing for them is the frame, not the build.

**Cores without save states (2026-11-22).** The ladder assumes every core can
serialize. Some cannot: `gw` returns 0 from `retro_serialize_size`, so the
harness stops at exit 4 by definition and the core can never reach BOOTS no
matter how correctly it draws. That is a limit of the measurement, not a
verdict on the core, so such a row stays at IDENTIFIES and its note carries the
recorded frames and the refusals itself. Do not invent a level between
IDENTIFIES and BOOTS for it: a level that only one core can hold is not a
ladder, and calling it RENDERS would claim the state round trip the harness
never made.

**Harness limits on IDENTIFIES and RENDERS** (corrected 2026-09-29 — both
levels previously claimed more than the harness asserts):

- `IDENTIFIES` proves load + init only. `run_identify_only` in
  `runtime/test/test_core_boot.c` prints `ezcore_core_name` and
  `ezcore_core_version` and then returns 0 unconditionally; the printed name is
  **never checked for NULL or emptiness**. A core that reports an empty name
  still earns IDENTIFIES.
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
- **Reproducibility (2026-11-22).** An earlier runner set its `reproducible`
  flag by comparing two **exit codes** and captured no frame on the second run,
  so a core that repaints a different picture on every boot would still have
  earned that label. RENDERS rows here do not rely on it. The `frame_hash_reproducible` CTest added to
  `runtime/CMakeLists.txt` enforces the stronger contract on the harness: two
  runs must print the same frame SHA-256, that hash must equal SHA-256 over the
  stored PPM's RGB bytes, and an unwritable capture destination must be exit 7
  rather than a silent skip.

## Cores × platforms

| Core | macOS arm64 | iOS arm64 | Android arm64 | Linux x64 | Windows x64 | Notes |
|---|---|---|---|---|---|---|
| pocketbit | BUILT | BUILT | BUILT | RENDERS | — | Linux: captured 160x144 frame, sum 381089848954, sha256 `34cd921e4812f6b61e632efe0132b7663ce3ad995fa814fbb8d0c48eadcde96e` at the default 30-frame budget; restore exact; reproduced twice. The same build drew a different frame (`5f5b4058…`) for an NES file, so the frame follows the content. The boot ROM was absent and the core fell back to its own startup image, which is what the frame shows. The recorded boot ran on Linux, not macOS, and no frame exists for any other platform, so only this cell is RENDERS. iOS needed `ios-arm64` + gmake4 + serial (pb12 race) |
| gambatte | BUILT | BUILT | BUILT | — | — | ⚠ Catalog contradiction: `cores/catalog.json` records `delivery: absent` on all five platforms while artifact pins exist for macOS/Linux/Android; licence is GPL-2.0-only. The macOS cell has no `boot_gambatte` ctest and no in-tree fixture, so the recorded boot is not reproducible here; no frame was recorded, so RENDERS is not established (frame rule above). Resolving the distribution conflict is a maintainer decision. Android via `unix` (no android branch upstream) |
| advancebit | BUILT | — | BUILT | RENDERS | — | Linux: captured 240x160 frame, sum 639944581886, sha256 `15992d2a7b0bdd8c8cf96d50f76d4b49c2ceb6299eb991750823cf02f56f62ec`; restore exact; reproduced twice. The same build drew a different frame (`c44d0f4f…`) for a Game Boy file. The `boot_advancebit` ctest is fixture-gated in `runtime/CMakeLists.txt` and the fixture is absent from the tree, so this run is not the ctest. iOS excluded: dynarec default unverified. Android needed `-Wno-error=int-conversion` (NDK r27) |
| nesbyte | IDENTIFIES | BUILT | BUILT | RENDERS | — | Linux: captured 256x240 frame, sum 263508456624048, sha256 `ce915ccefd866e98d08bd59dc9659a1169107ef66d8508a59a6bef84c0ed2c42`; restore exact; reproduced twice. The control is a refusal rather than a foreign frame: fed a Game Boy file, the core failed to load it and exited 2. The recorded `ctest -R boot_nesbyte` used a generated ROM that is local-only and absent from the tree; the captured frame is the evidence here, not the ctest. Re-verified 2026-11-22: this build fed an open-source 240p test suite for the NES (Artemio's, local-only) at the default budget reproduced that exact sum and hash twice, with 8 colours and the same exit-2 Game Boy refusal — so the recorded frame's content was the 240p suite, not the generated ROM as the previous sentence implied. The generated CC0 ROM draws a flat one-colour frame (`499cf31d8cba…`), which is not itself frame evidence. iOS needed `ios-arm64` (TLS requires minos 9+) |
| superfx | IDENTIFIES | BUILT | BUILT | — | — | Non-commercial licence — no binaries shipped; recipe only (delivery absent on all five platforms, `cores/catalog.json`). Android via `unix` (no android branch upstream) |
| blastproc | IDENTIFIES | BUILT | BUILT | BUILT | — | Linux: no `boot_blastproc` ctest and no in-tree fixture, so the recorded boot is not reproducible here; no frame was recorded, so RENDERS is not established (frame rule above). Non-commercial licence — no binaries shipped; recipe only (delivery absent on all five platforms, `cores/catalog.json`). Android via `unix` |
| joystick | IDENTIFIES | BUILT | BUILT | RENDERS | — | Linux (promoted 2026-11-22): captured a 160x274 frame (8 colours) at the default 30-frame budget from `ezcore_a26_cycle.a26`, an original CC0 hand-assembled 4K homebrew program (ROM SHA-256 `22fa3a5ab62d29a…`, regenerated byte-for-byte by `scripts/gen_a26_minimal_rom.py`); sum 339449734080, sha256 `eacfe614aff741d3734632b6ded1507d4cdba12a23f80810a811285893c4b63b`, save state 1216 bytes, restore exact, reproduced twice. A second original Atari program drew a different frame (`aef879b9b321…`), and the core refused a CC0 NES file (exit 2), so the picture follows the content. The generated ROM is never committed. Android needed `PTHREAD_FLAGS=` (no libpthread in NDK) |
| cardcon | IDENTIFIES | BUILT | BUILT | BUILT | — | Android needed `-lrt` wrapper (NDK has no librt). A negative control fed the Linux build a NES archive and a Game Boy file: it accepted both and drew the **same** frame (256x243, identical pixel sum), so the gate cannot tell a PC Engine boot from decoration here. This row stays BUILT: a frame from this core proves nothing until it differs by content |
| realmode | IDENTIFIES | BUILT | BUILT | BUILT | — | Linux: the recorded boot opened the DOS start menu, but serialize was refused until a program runs, so this is not RENDERS; no frame was recorded (frame rule above). Needs a self-running DOS fixture. Android needed `ISMAC=` + NDK `STRIP`; all-interpreter (perf caveat) |
| coinbox | IDENTIFIES | BUILT | BUILT | — | — | All-interpreter on 64-bit (Cyclone is 32-bit ARM only) |
| pointclick | IDENTIFIES | — | BUILT | BUILT | — | Linux: a recorded run crashed on a bare `sky.dsk`; the exit-9 crash classification is proven in `runtime/test/test_core_boot.c` and `runtime/test/test_crash_signal.c`, but the event has no in-tree log and is not asserted here. macOS first build 2026-09-19 (freetype zconf.h patch was being reverted by their configure step — see build_core.sh); Android arm64 staged + pinned the same day |
| geometry1 | IDENTIFIES | — | — | BOOTS | — | Linux: a recorded negative control fed a NES file and a GBA cartridge; the core accepted both and produced the same picture it draws for its own content, so video output cannot evidence PlayStation rendering. Loading, init and save-restore stand; the earlier RENDERS row is withdrawn. No frame was recorded (frame rule above). Restoring the row needs one real PSX image whose frame differs from a negative control |
| rcp64 | IDENTIFIES | — | — | RENDERS | — | Linux: captured 640x480 frame, sum 1314321213910097, sha256 `92578030330267ec89e3c79047fb29b87472417bb81c9936b9a39ce74d9c5f32`; restore exact; reproduced twice. Taken with the committed default RDP plugin, `angrylion` (`default_options` in `cores/rcp64/manifest.json`); the earlier GLideN64 run in this row was an `EZCORE_BOOT_OPTIONS` override and is not what this cell records. The core refused NES and Game Boy files (exit 2). An unrelated N64 fixture that exercises compression hung for over three minutes and was killed; that is a property of the fixture, and it is not evidence either way |
| dualscreen | IDENTIFIES | — | — | RENDERS | — | Linux (promoted 2026-11-22): captured 256x384 frames at the default 30-frame budget from two CC0 NDS homebrew ROMs (`nmap.nds` from rmn20/NormalmappingDS, `BlimpChicken.nds` from My-name-is-TJ/blimp-chicken-ds). `nmap`: sum 420659624461213, sha256 `7d64943140bc36a67bf6085928da568a8c78288b31fd9ada98b65ccd35d2d2cd`, 338 colours, save state 6518475 bytes, restore exact, reproduced twice; the other program drew a different frame (`8b5d8b81b30e…`, 3 colours). A Game Boy file was accepted but drew a different frame (`cc8c92a39f01…`); an NES file crashed the core (exit 9) rather than being cleanly refused — recorded as a core robustness limit, not as evidence of refusal. The core printed that it was using its bundled fallback BIOS. Both ROMs are local-only, never in the repository |
| portcomp | IDENTIFIES | — | — | BOOTS | — | Linux: a recorded PPSSPP boot used `EZCORE_BOOT_FRAMES=300 EZCORE_BOOT_PACE=1` because PPSSPP draws on its own thread, and reached save-restore within 2% (the `RESTORE_PIXEL_SUM_TOLERANCE_REL` macro in `runtime/test/test_core_boot.c`, 0.02). No frame was recorded, so RENDERS is not established (frame rule above) |
| dreamarc | IDENTIFIES | — | — | BOOTS | — | Linux: a recorded Flycast boot on OpenGL reached save-restore within 2% (the `RESTORE_PIXEL_SUM_TOLERANCE_REL` macro in `runtime/test/test_core_boot.c`, 0.02), but the harness frame was black, so it does not evidence content rendering. No frame was recorded, so RENDERS is not established (frame rule above) |
| powercube | IDENTIFIES | — | — | BOOTS | — | iOS: `delivery.ios` is `bundled` (`cores/powercube/manifest.json:44`, `cores/catalog.json:922`); the note at `cores/powercube/manifest.json:38` says absent. Linux: a recorded Dolphin boot reached save-restore within 2% (the `RESTORE_PIXEL_SUM_TOLERANCE_REL` macro in `runtime/test/test_core_boot.c`, 0.02). No frame was recorded, so RENDERS is not established (frame rule above) |
| twinsh | IDENTIFIES | — | — | BUILT | — | SH-2 interpreter; slow by nature, frames unverified |
| lrps2 | — | — | — | BOOTS | — | Linux x64: a recorded LRPS2 boot used a user-supplied BIOS and stayed within the 2% restore tolerance (the `RESTORE_PIXEL_SUM_TOLERANCE_REL` macro in `runtime/test/test_core_boot.c`, 0.02). BIOS and content are local-only, never in the repository. No frame was recorded, so RENDERS is not established (frame rule above). Catalog entry: `cores/lrps2/manifest.json` (delivery `linux: bundled`; BIOS gated at `pcsx2/bios`) |
| dualvu | — | — | — | BOOTS | — | Linux x64: a recorded BIOS-free Play! `ui_libretro` boot (pinned d44bfa1) stayed within the 2% restore tolerance (the `RESTORE_PIXEL_SUM_TOLERANCE_REL` macro in `runtime/test/test_core_boot.c`, 0.02); the `boot_dualvu` ctest is fixture-gated and the ELF is absent from the tree. No frame was recorded, so RENDERS is not established (frame rule above). Fixture is local-only, never committed. Catalog entry: `cores/dualvu/manifest.json` (delivery `linux: absent` — `cores/dualvu/manifest.json:30`, `cores/catalog.json:371`; artifact pinned) |
| potator | — | — | — | RENDERS | — | Linux x64: captured 160x160 frames at a 300-frame budget (`EZCORE_BOOT_FRAMES=300`) from two different Supervision homebrew programs; the two frames differ, so the picture follows the content, and each hash reproduced on a second run — sums 410876588538 and 358826035828, sha256 `7e40afa3f962344bd4c4a435b1e41b630834bca97d54e90a5221fdb0ca2a2237` and `1d0a6cae15d8568633e8a2d0d4fbe98993a8f7334360cc29a8d5f71dcaf92091`. Restore exact both times. The controls are refusals: an NES file exited 2, and a file from another handheld system drew a zero pixel sum (exit 3). Both runs used the published `v0.2.0` `linux-x64` artifact, byte-identical to the manifest pin. Content is MIT-licensed homebrew, local-only, never in the repository |
| gw | — | — | — | IDENTIFIES | — | Linux x64: loads, inits and draws a full handheld panel from two different packs, but `retro_serialize_size` returns 0 — the core has no save states — so it cannot reach BOOTS as defined above, which requires a serialize round trip. The frames are recorded as evidence of drawing, not as a level claim: 562x374 with 1779 colours (sha256 `9c37a52386d7e6a47a99c4f70e9859ae44db65d75084bb88be0a564594d3d3d8`) and 612x377 with 3992 colours (sha256 `7ec620897c06a08a54d07ef78684a68c7086a20ed0e7b84e141fe09eb0eb3811`), each reproduced twice; it refused a file from another handheld system and a Game Boy file, both exit 2. Because the cell stays IDENTIFIES, nothing here claims the panel is correct. Content is CC BY-NC-SA packs used locally, never shipped |
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
exists for exactly this). Two such sources now exist and are used
locally, never committed: MIT-licensed CROSS-LIB builds for Watara
Supervision, and CC BY-NC-SA `.mgw` packs for the LCD handhelds.

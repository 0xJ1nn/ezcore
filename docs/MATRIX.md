# ezCORE Core × Platform Matrix

> **Last verified:** 2026-09-19 (macOS arm64 full desktop set — 18 cores built, 15 bundled; scummvm added this date; Snes9x and Genesis Plus GX removed from distribution — non-commercial licenses)
> **Refresh:** build the tier (`scripts/build_core.sh`), then
> `flutter test test/core_matrix_test.dart` (subprocess-isolated harness).

## Levels

| Level | Meaning | How proven |
|---|---|---|
| `—` | Not attempted | — |
| BUILT | Compiles + links for the target triple | `file`/`readelf`/`vtool` arch + platform + minos, `nm` retro exports |
| PINNED | sha256 recorded in `cores/<id>/manifest.json` | `scripts/pin_artifacts.py` + review |
| IDENTIFIES | Loads + inits + names itself in the harness | `test_core_boot --identify-only` exit 0 |
| RENDERS | Boots content: 30 frames, nonzero pixels, save/restore | `test_core_boot <rom>` exit 0 |
| SHIPPED | In `release.sh` bundles for that OS | Bundle inspection |

Rules: pins are evidence, never aspirational (`pin_artifacts.py` refuses
blocked cores). iOS entries must be interpreter (manifest validation
enforces; `TIER_IOS` excludes JIT-default cores until flags are verified).

## Cores × platforms

| Core | macOS arm64 | iOS arm64 | Android arm64 | Linux x64 | Windows x64 | Notes |
|---|---|---|---|---|---|---|
| sameboy | RENDERS | BUILT | BUILT | — | — | iOS needed `ios-arm64` + gmake4 + serial (pb12 race) |
| gambatte | RENDERS | BUILT | BUILT | — | — | Android via `unix` (no android branch upstream) |
| mgba | RENDERS | — | BUILT | — | — | iOS excluded: dynarec default unverified; Android needed `-Wno-error=int-conversion` (NDK r27) |
| mesen | IDENTIFIES | BUILT | BUILT | — | — | iOS needed `ios-arm64` (TLS requires minos 9+) |
| snes9x | IDENTIFIES (not distributed) | BUILT | BUILT | — | — | Non-commercial license — no binaries shipped; recipe only. Android via `unix` (no android branch upstream) |
| genesis_plus_gx | IDENTIFIES (not distributed) | BUILT | BUILT | — | — | Non-commercial license — no binaries shipped; recipe only. Android via `unix` |
| stella | IDENTIFIES | BUILT | BUILT | — | — | Android needed `PTHREAD_FLAGS=` (no libpthread in NDK) |
| beetle_pce | IDENTIFIES | BUILT | BUILT | — | — | Android needed `-lrt` wrapper (NDK has no librt) |
| dosbox_pure | IDENTIFIES | BUILT | BUILT | — | — | Android needed `ISMAC=` + NDK `STRIP`; all-interpreter (perf caveat) |
| fbneo | IDENTIFIES | BUILT | BUILT | — | — | All-interpreter on 64-bit (Cyclone is 32-bit ARM only) |
| scummvm | IDENTIFIES | — | BUILT | — | — | macOS first build 2026-09-19 (freetype zconf.h patch was being reverted by their configure step — see build_core.sh); Android arm64 staged + pinned the same day |
| swanstation | IDENTIFIES | — | — | — | — | Default renderer needs GL context the runtime doesn't provide; frames unverified |
| mupen64plus | IDENTIFIES | — | — | — | — | Same GL caveat (Angrylion path needs core options = ABI v2) |
| melonds | IDENTIFIES | — | — | — | — | Same GL caveat (software renderer needs core options) |
| ppsspp | IDENTIFIES | — | — | — | — | Same GL caveat |
| flycast | IDENTIFIES | — | — | — | — | Same GL caveat |
| dolphin | IDENTIFIES | — (delivery absent) | — | — | — | No software renderer exists: blocked on GPU context (post-v1), not attempted |
| beetle_saturn | IDENTIFIES | — | — | — | — | SH-2 interpreter; slow by nature, frames unverified |
| citra/switch/ps2 | holds | holds | holds | holds | holds | Legal blocks, never built |

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

`native/test-roms/` (gitignored, local-only): `cpu_instrs.gb` (Blargg),
`test.gba` (4 KB OBJTEST homebrew). RENDERS-level coverage beyond
GB/GBC/GBA needs sourced public-domain homebrew per system + per-file
LICENSE (the `test/fixtures/` allowlist in `banned_content_scan.sh`
exists for exactly this) — open item, tracked in RELEASE_PLAN.

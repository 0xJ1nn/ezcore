# Core × platform matrix

The table records the strongest verified level for each core on each release
target. A cell proves that target alone; a result never carries over to another
platform. Frames, hashes, commands and the limits of each measurement are kept
by the maintainers, not published here.

## Levels

| Level | Meaning |
|---|---|
| — | Not attempted. |
| BUILT | Compiles and links for the target triple. |
| IDENTIFIES | Loads and initialises; the harness prints the reported name and version. |
| BOOTS | Loads real content, survives a save-state round trip and draws a nonzero frame that was not kept. |
| RENDERS | BOOTS, plus a recorded frame that differs from the same build fed another system's file, or that the core refuses. |
| PLAYS | A scripted session in the play harness or the in-app selftest passed every checkpoint. |

PINNED (a SHA-256 in the manifest) and SHIPPED (present in a release bundle) are
recorded in the maintainers' evidence, not as cells below. A `holds` cell marks
a core that is reserved but never built.

## Cores × platforms

| Core | macOS arm64 | iOS arm64 | Android arm64 | Linux x64 | Windows x64 | Last verified |
|---|---|---|---|---|---|---|
| pocketbit | BUILT | BUILT | BUILT | RENDERS | — | 2026-11-22 |
| gambatte | BUILT | BUILT | BUILT | IDENTIFIES | — | 2026-11-22 |
| advancebit | BUILT | — | BUILT | RENDERS | — | 2026-11-22 |
| nesbyte | IDENTIFIES | BUILT | BUILT | RENDERS | — | 2026-11-22 |
| superfx | IDENTIFIES | BUILT | BUILT | IDENTIFIES | — | 2026-11-22 |
| blastproc | IDENTIFIES | BUILT | BUILT | BUILT | — | — |
| joystick | IDENTIFIES | BUILT | BUILT | RENDERS | — | 2026-11-22 |
| cardcon | IDENTIFIES | BUILT | BUILT | BUILT | — | 2026-11-22 |
| realmode | IDENTIFIES | BUILT | BUILT | BUILT | — | 2026-11-22 |
| coinbox | IDENTIFIES | BUILT | BUILT | IDENTIFIES | — | 2026-11-22 |
| pointclick | IDENTIFIES | — | BUILT | BUILT | — | 2026-09-19 |
| geometry1 | IDENTIFIES | — | — | BOOTS | — | 2026-11-21 |
| rcp64 | IDENTIFIES | — | — | RENDERS | — | 2026-11-22 |
| dualscreen | IDENTIFIES | — | — | RENDERS | — | 2026-11-22 |
| portcomp | IDENTIFIES | — | — | BOOTS | — | 2026-11-22 |
| dreamarc | IDENTIFIES | — | — | BOOTS | — | 2026-11-22 |
| powercube | IDENTIFIES | — | — | BOOTS | — | 2026-11-22 |
| twinsh | IDENTIFIES | — | — | BUILT | — | 2026-11-22 |
| lrps2 | — | — | — | BOOTS | — | 2026-11-22 |
| dualvu | — | — | — | BOOTS | — | 2026-11-22 |
| potator | — | — | — | RENDERS | — | 2026-11-22 |
| gw | — | — | — | IDENTIFIES | — | 2026-11-22 |
| citra/switch | holds | holds | holds | holds | holds | — |

"Last verified" is the date of the most recent recorded check for that row; a
dash means the record has no dated check. The cell values are unchanged from the
earlier matrix. Detailed evidence for each row is kept by the maintainers.

## Platform shells and app builds

| Platform | Shell | App build | Audio sink | Gamepad | Notes |
|---|---|---|---|---|---|
| macOS | ✅ | ✅ debug (+ release via release.sh) | AVAudioEngine ✅ | GCController ✅ | Sandbox bookmarks wired; E2E pending human run |
| Linux | ✅ (`flutter create`) | CI | ALSA/FFI (code, unverified) | evdev (code, unverified) | Flutter shell CI-built, not run on a desktop here; the native boot harness does run on Linux x64 (see the core matrix above) |
| Windows | ✅ (renamed binary) | CI | waveOut/FFI (code, unverified) | XInput/FFI (code, unverified) | `dynload_win32.c` compiles on CI |
| Android | ✅ | ✅ debug APK | AudioTrack ✅ (code) | KeyEvent ✅ (code) | Needs device run; cores verified ELF+symbols |
| iOS | ✅ (15.0 floor) | CI build; unsigned compile check only, no signed release artifact | AVAudioEngine ✅ (code) | GCController ✅ (code) | No sim/device here; cores verified Mach-O+symbols, no current `ios-arm64` pins |

All five targets — iOS, Android, macOS arm64, Linux x64 and Windows x64 — are
required for a release. No row above waives one: macOS end-to-end runs, desktop
audio and gamepad runs, Android and iOS device runs, and a signed iOS release
remain outstanding. A result in one cell proves that target alone.

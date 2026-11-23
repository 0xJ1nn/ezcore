# Native audio

The runtime owns one playback device per process. The core's libretro audio
callback writes stereo 16-bit frames into a lock-free ring; the device thread
reads them, resamples them to the device rate and writes 32-bit float samples
to the platform backend. Dynamic rate control nudges the resample ratio by at
most 0.5% from the ring's fill level, so emulation stays paced by the audio
clock and short scheduling delays do not become audible gaps. The device is
shared by every session because only one core runs at a time.

`runtime/src/ezcore_audio.c` is the single implementation for all five release
targets. miniaudio supplies the device clock and backend selection; its single
header is vendored in `runtime/external/miniaudio/` under the public-domain or
MIT-0 licence recorded in `THIRD_PARTY_NOTICES.md`. No firmware, keys or game
content are involved.

## Interface

`ezcore_audio_open` takes the core and device sample rates, the channel count
(two), the ring capacity, an initial gain, a mute flag and a backend choice.
`EZCORE_AUDIO_BACKEND_AUTO` selects the platform device;
`EZCORE_AUDIO_BACKEND_NULL` selects a silent device that runs at the requested
rate, for deterministic tests. `ezcore_audio_close` stops the device.
`ezcore_audio_set_volume` and `ezcore_audio_set_muted` are safe to call while
it runs. `ezcore_audio_stats` reports frames written and played, underruns,
overruns, buffered frames, fill fraction, resample ratio and device state.

## Backends

| Target | Backend selected by miniaudio | Build status |
|---|---|---|
| Linux x64 | PulseAudio, PipeWire or ALSA | Built and tested here |
| Android arm64 | AAudio, with OpenSL ES as fallback | Built and linked here; not run on a device |
| macOS arm64 | Core Audio | Build steps written; unverified, no macOS host here |
| iOS arm64 | Core Audio | Build steps written; unverified, no iOS host here |
| Windows x64 | WASAPI | Build steps written; unverified, no Windows host here |

## Build and verify

Every target uses the same CMake sources. Fetch the libretro header once, then
use the row for the host:

```bash
scripts/build_core.sh --fetch-headers
scripts/build_runtime.sh linux      # or macos, windows, android, ios
```

`scripts/build_runtime.sh` runs the C tests on Linux and macOS. On the other
targets it builds and links the runtime and every native test, including the
audio test; the tests run on a host with that platform's toolchain. The audio
test loads the synthetic core, opens the null backend at 48 kHz, feeds the
ring through the real libretro audio callbacks for ten seconds of device time
and fails on any underrun, timeout or dropped frame. It prints one JSON line
with the measured counters.

| Target | Command | Evidence |
|---|---|---|
| Linux x64 | `scripts/build_runtime.sh linux` then `ctest --test-dir runtime/build-linux --output-on-failure` | 23 of 23 tests pass; audio test: 480000 frames played, 0 underruns, 0 overruns |
| Android arm64 | `ANDROID_NDK_HOME=<ndk> scripts/build_runtime.sh android` | Runtime and native tests link for `arm64-v8a`; not run |
| macOS arm64 | `ARCH=arm64 scripts/build_runtime.sh macos` | Unverified on this machine |
| iOS arm64 | `scripts/build_runtime.sh ios` on a macOS host with Xcode | Unverified on this machine |
| Windows x64 | `scripts/build_runtime.sh windows` on a Windows host with MSVC | Unverified on this machine |

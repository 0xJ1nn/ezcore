# ezCore C ABI Specification

> **Version:** 1.0
> **Date:** 2026-09-16
> **Header:** `runtime/include/ezcore_runtime.h`
> **Language:** C11 (pure C ABI)

---

## Overview

The ezCore runtime exports a pure C ABI that Flutter/Dart binds to via `dart:ffi`. The ABI is versioned (`EZCORE_ABI_VERSION`) and stable — once a function is exported, its signature never changes.

The runtime is written in C11 and its ABI is plain C. Dart never sees any
other language's types — the FFI bindings and the header are the whole
contract.

---

## ABI Version

```c
#define EZCORE_ABI_VERSION 1
```

When the ABI changes incompatibly, this number is bumped. The Flutter layer checks this at load time and refuses to run with an incompatible runtime.

---

## Types

### Opaque Session

```c
typedef struct ezcore_session ezcore_session;
```

An opaque handle to a loaded libretro core session. Created by `ezcore_load`, destroyed by `ezcore_unload`. All other functions take a session pointer.

### Pixel Format

The runtime always presents frames as XRGB8888 to the frontend. Cores that
request another format (`RETRO_PIXEL_FORMAT_0RGB1555`, `RETRO_PIXEL_FORMAT_RGB565`)
are converted internally (`runtime/src/runtime.c:128-140`). No pixel-format
constants are exported — the presentation format is fixed by the ABI, not
selectable. (Pixel-format selection is a P1b idea, tracked in the roadmap.)

### Error Buffer

```c
char err[256];
```

All functions that can fail take an error buffer. On failure, the buffer is filled with a human-readable error message. On success, the buffer is unchanged.

### Native Audio

```c
typedef struct ezcore_audio ezcore_audio;
```

An opaque handle to the process-wide playback device. Created by
`ezcore_audio_open`, destroyed by `ezcore_audio_close`.

`ezcore_audio_config` carries the core and device sample rates, channel count,
ring capacity, initial gain and mute state, and the backend choice.
`ezcore_audio_statistics` carries the frame counters, ring fill, resample ratio
and device state. `ezcore_audio_backend` is either `EZCORE_AUDIO_BACKEND_AUTO` for
the platform device or `EZCORE_AUDIO_BACKEND_NULL` for the test device.

### Native Run Loop

```c
typedef struct ezcore_loop ezcore_loop;
```

An opaque handle to the runtime-owned run thread for one session. Created by
`ezcore_loop_start`, joined and destroyed by `ezcore_loop_stop`. The thread calls
`retro_run` paced by the audio device clock, or by a monotonic clock when no
device is open. Frames are published into a three-slot buffer where the newest
complete frame wins; a reader pins one slot until it releases it.

`ezcore_loop_config` selects the pacing rate and the frame-time histogram.
`ezcore_loop_statistics` carries frame counts, dropped frames, control counts,
device underruns, frame-time percentiles and the histogram.

---

## Functions

### Lifecycle

#### `ezcore_abi_version`

```c
int ezcore_abi_version(void);
```

Returns `EZCORE_ABI_VERSION`. The Flutter layer calls this first to verify compatibility.

**Returns:** ABI version number (currently `1`).

---

#### `ezcore_set_dirs`

```c
void ezcore_set_dirs(const char *system_dir, const char *save_dir);
```

Sets host-owned content directories. Must be called before `ezcore_load` when cores need system/save paths (mupen64plus crashes without them).

**Parameters:**
- `system_dir` — path to system directory (BIOS, firmware, etc.)
- `save_dir` — path to save directory (save states, SRAM, etc.). The runtime also uses it for battery saves: see `ezcore_load_game`.

**Thread safety:** Not thread-safe. Call once at startup before any sessions are created.

---

#### `ezcore_load`

```c
ezcore_session *ezcore_load(const char *core_path, char *err, size_t err_len);
```

Loads a libretro core from disk. The core is dlopen'd with `RTLD_NOW | RTLD_LOCAL`. All required libretro symbols are resolved. The core's `retro_api_version` must return 1.

**Parameters:**
- `core_path` — path to the core shared library (`.so`/`.dylib`/`.dll`)
- `err` — error buffer (filled on failure)
- `err_len` — size of error buffer

**Returns:** Session pointer on success, `NULL` on failure.

**Errors:**
- `dlopen failed: <dlerror>` — core couldn't be loaded
- `core missing symbol: <sym>` — required libretro symbol not found
- `unsupported libretro API version` — core doesn't implement API v1

---

#### `ezcore_unload`

```c
void ezcore_unload(ezcore_session *s);
```

Unloads a core session. Calls `retro_deinit`, dlcloses the handle, and frees all associated resources (frame buffer, audio ring).

Battery-backed save RAM is copied out before `retro_unload_game` and written to
the session's `.srm` file (see `ezcore_load_game`); a core frees its save buffer
during teardown, so the copy has to happen first.

**Parameters:**
- `s` — session pointer (from `ezcore_load`)

**Thread safety:** Not thread-safe. Ensure no other thread is using the session.

---

#### `ezcore_init`

```c
bool ezcore_init(ezcore_session *s);
```

Initializes the core. Calls `retro_init`. Most cores don't need this explicitly (it's called during `retro_load_game`), but some cores require it for environment setup.

**Parameters:**
- `s` — session pointer

**Returns:** `true` on success, `false` on failure.

---

#### `ezcore_reset`

```c
void ezcore_reset(ezcore_session *s);
```

Soft-resets the currently loaded game (calls the core's `retro_reset`). A
no-op when no game is loaded or the core does not export `retro_reset`.

**Parameters:**
- `s` — session pointer

**Thread safety:** Not thread-safe. Call from the emulation thread; safe only
after `ezcore_load_game`.

---

### Game Loading

#### `ezcore_load_game`

```c
bool ezcore_load_game(ezcore_session *s, const char *rom_path,
                      const void *data, size_t size);
```

Loads a game into the core. The ROM data is passed as a memory buffer (not read from disk by the runtime). The core's `retro_load_game` is called with a `retro_game_info` struct.

**Parameters:**
- `s` — session pointer
- `rom_path` — path to the ROM file (for cores that need it)
- `data` — ROM data buffer (loaded by the Flutter layer)
- `size` — size of ROM data in bytes

**Returns:** `true` on success, `false` on failure.

**Battery saves:** on success the runtime derives `<save_dir>/<content basename>.srm`
and, if that file exists and its length matches the core's save RAM exactly,
copies it in before the first frame. `ezcore_unload` writes the region back, so
a battery save survives the session without the host asking. A file of the
wrong length is ignored rather than spliced into the core's memory; sessions
started without a save directory persist nothing.

**Note:** Several cores (e.g., mGBA) dereference the game info here and segfault if called before `retro_init`. The runtime handles this by calling `retro_init` first if not already done.

---

### Execution

#### `ezcore_run_frame`

```c
void ezcore_run_frame(ezcore_session *s);
```

Runs one frame of emulation. Calls `retro_run`. The video refresh callback updates the frame buffer, and the audio callback appends to the audio ring.

**Parameters:**
- `s` — session pointer

**Thread safety:** Not thread-safe. Call from a single emulation thread.

---

### Introspection

#### `ezcore_core_name`

```c
const char *ezcore_core_name(ezcore_session *s);
```

Returns the core's library name (e.g., "Mesen", "Snes9x").

**Parameters:**
- `s` — session pointer

**Returns:** Core name string, or `"?"` if not available.

---

#### `ezcore_core_version`

```c
const char *ezcore_core_version(ezcore_session *s);
```

Returns the core's library version (e.g., "0.9.9").

**Parameters:**
- `s` — session pointer

**Returns:** Core version string, or `"?"` if not available.

---

#### `ezcore_system_geometry`

```c
void ezcore_system_geometry(ezcore_session *s, unsigned *w, unsigned *h,
                            double *fps);
```

Queries the system AV info for the currently loaded game. Returns base width, base height, and target FPS.

**Parameters:**
- `s` — session pointer
- `w` — output: base width in pixels (0 if no game loaded)
- `h` — output: base height in pixels (0 if no game loaded)
- `fps` — output: target frames per second (0 if no game loaded)

**Important:** Must only be called after `ezcore_load_game` succeeds. Several cores crash on pre-load AV queries.

---

#### `ezcore_sample_rate`

```c
double ezcore_sample_rate(ezcore_session *s);
```

Returns the audio sample rate from the core's AV timing. `0.0` when no game
is loaded.

**Parameters:**
- `s` — session pointer

**Thread safety:** Not thread-safe — queries the core
(`retro_get_system_av_info`) directly, so it must run on the emulation thread.

---

### Input

#### `ezcore_set_button`

```c
void ezcore_set_button(ezcore_session *s, unsigned port,
                       unsigned button_id, bool pressed);
```

Sets one button's pressed state. `button_id` is a `RETRO_DEVICE_ID_JOYPAD_*`
value; `port` is the player index (0–3). Out-of-range values are ignored.

**Thread safety:** Not thread-safe. The state is read by `ezcore_run_frame`'s
input poll — the caller must serialise against it (the frontend routes input
through its emulation worker).

---

#### `ezcore_clear_buttons`

```c
void ezcore_clear_buttons(ezcore_session *s, unsigned port);
```

Clears all pressed buttons for one port (0–3). Out-of-range ports are ignored.

**Thread safety:** Not thread-safe — same serialisation duty as
`ezcore_set_button`.

#### `ezcore_set_analog`

```c
void ezcore_set_analog(ezcore_session *s, unsigned port, unsigned stick,
                       unsigned axis, int16_t value);
```

Sets one analog stick axis for a port (0–3). `stick` is 0 (left) or 1
(right), as `RETRO_DEVICE_INDEX_ANALOG_*`; `axis` is 0 (x) or 1 (y); `value`
is −32768…32767. Analog-button reads (pressure triggers, index
`RETRO_DEVICE_INDEX_ANALOG_BUTTON`) follow the digital button state: a pressed
button reads `0x7fff`. Out-of-range arguments are ignored.

**Thread safety:** Not thread-safe — same serialisation duty as
`ezcore_set_button`.

#### `ezcore_mouse_move`

```c
void ezcore_mouse_move(ezcore_session *s, int dx, int dy);
```

Adds relative mouse motion. Motion accumulates until the next
`ezcore_run_frame`, which hands the core one delta for the whole frame; every
read during that frame returns the same delta.

**Thread safety:** Not thread-safe — same serialisation duty as
`ezcore_set_button`.

#### `ezcore_set_mouse_button`

```c
void ezcore_set_mouse_button(ezcore_session *s, unsigned id, bool pressed);
```

Sets a mouse button, where `id` is a `RETRO_DEVICE_ID_MOUSE_*` value (`LEFT`,
`RIGHT`, `MIDDLE`, `WHEELUP`, …). Ids of 32 and above are ignored.

**Thread safety:** Not thread-safe — same serialisation duty as
`ezcore_set_button`.

#### `ezcore_set_key`

```c
void ezcore_set_key(ezcore_session *s, unsigned keycode, bool pressed,
                    uint32_t character, uint16_t modifiers);
```

Sets a keyboard key, where `keycode` is a `RETROK_*` value, `character` the
UTF-32 character typed (or 0) and `modifiers` the `RETROKMOD_*` bits. Updates
the polled key state and, when the core registered one through
`RETRO_ENVIRONMENT_SET_KEYBOARD_CALLBACK`, calls its keyboard callback.
Keycodes of `RETROK_LAST` and above are ignored.

**Thread safety:** Not thread-safe; the keyboard callback runs inside this
call, on the caller's thread, so it must be the thread that runs frames.

#### `ezcore_set_pointer`

```c
void ezcore_set_pointer(ezcore_session *s, int16_t x, int16_t y, bool pressed);
```

Sets the pointer (touchscreen). `x` and `y` span the core's whole output,
−32767 (left/top) to 32767 (right/bottom).

**Thread safety:** Not thread-safe — same serialisation duty as
`ezcore_set_button`.

All input — buttons, sticks, mouse buttons and motion, keys and the pointer —
is released by `ezcore_reset` and by a successful `ezcore_load_game`.

---

### Video

#### `ezcore_frame_pixels`

```c
const uint32_t *ezcore_frame_pixels(ezcore_session *s, unsigned *w, unsigned *h);
```

Returns a pointer to the latest video frame. The frame is in XRGB8888 format (4 bytes per pixel, upper byte ignored).

**Parameters:**
- `s` — session pointer
- `w` — output: frame width in pixels
- `h` — output: frame height in pixels

**Returns:** Pointer to frame buffer, or `NULL` if no frame available.

**Lifetime:** The pointer is valid until the next `ezcore_run_frame` call. Copy the data if you need to retain it.

---

#### `ezcore_frame_size`

```c
void ezcore_frame_size(ezcore_session *s, unsigned *w, unsigned *h);
```

Returns the latest frame's dimensions in pixels. `0`/`0` when no frame has
been produced yet.

---

#### `ezcore_frame_pixels_copy`

```c
size_t ezcore_frame_pixels_copy(ezcore_session *s, uint8_t *out,
                                size_t out_size);
```

Copies the latest frame into `out` as RGBA bytes. `out` must be at least
`w * h * 4` bytes.

**Returns:** Bytes copied (`w * h * 4`), or `0` if no frame has been produced
yet.

**Thread safety:** Not thread-safe — reads the frame state `ezcore_run_frame`
writes; call from the emulation thread.

---

#### `ezcore_video_attach`

```c
bool ezcore_video_attach(ezcore_session *s, void *window, unsigned width,
                         unsigned height);
```

Attaches the `ANativeWindow` behind a Flutter `SurfaceProducer` surface to a
session and sets its buffers to `width` × `height` RGBA. The caller must keep
the window handle valid until `ezcore_video_detach`. Detach releases the
handle. Returns `false` when any argument is invalid or the window refuses the
geometry.

---

#### `ezcore_video_detach`

```c
void ezcore_video_detach(ezcore_session *s);
```

Stops presenting into the window and releases the native handle. Safe to call
on a session that is not attached.

---

#### `ezcore_video_present`

```c
bool ezcore_video_present(ezcore_session *s);
```

Copies the session's latest frame into the attached window and posts it. Call
from the emulation thread after the frame is complete. Returns `false` when no
window is attached, no frame exists, or the window's buffer is too small.

---

#### `ezcore_video_stats`

```c
bool ezcore_video_stats(ezcore_session *s, ezcore_video_statistics *out);
```

Reads the presentation counters and attached geometry. Returns `false` when no
window is attached. The counters are safe to read while frames are presented.

---

#### `ezcore_video_blit_rows`

```c
bool ezcore_video_blit_rows(uint8_t *dst, size_t dst_stride,
                            const uint32_t *src, unsigned width,
                            unsigned height, bool bgra);
```

Copies XRGB8888 pixels into 32-bit rows of `dst_stride` bytes, setting alpha to
opaque. `bgra` selects B,G,R,A byte order instead of R,G,B,A. Returns `false`
on invalid arguments. This is the platform-neutral copy the Android bridge
uses and the host test verifies.

---

### Audio

#### `ezcore_audio_drain`

```c
size_t ezcore_audio_drain(ezcore_session *s, int16_t *out, size_t frames);
```

Drains audio frames from the ring buffer. Audio is stereo signed 16-bit PCM.

**Parameters:**
- `s` — session pointer
- `out` — output buffer (must hold `frames * 2` int16_t values)
- `frames` — number of frames to drain

**Returns:** Number of frames actually drained (may be less than requested if ring is empty).

**Thread safety:** Not thread-safe. The drain is an unsynchronised
`memcpy`/`memmove` on the session's ring buffer
(`runtime/src/runtime.c:433-443`); the caller must serialise against
`ezcore_run_frame`, which appends to the same ring.

---

#### `ezcore_audio_drain_copy`

```c
size_t ezcore_audio_drain_copy(ezcore_session *s, int16_t *out,
                               size_t max_frames);
```

Drains up to `max_frames` stereo s16 samples into `out` — the copy variant of
`ezcore_audio_drain`.

**Returns:** Frames drained; may be less than requested when the ring is
empty.

**Thread safety:** Not thread-safe — same unsynchronised ring access as
`ezcore_audio_drain`.

---

#### `ezcore_audio_pending`

```c
size_t ezcore_audio_pending(ezcore_session *s);
```

Returns the number of audio frames currently queued in the ring buffer.

**Thread safety:** Not thread-safe. Reads the ring's fill level without
synchronisation.

---

### Native audio device

The device is process-wide and shared by the active session. Opening it
attaches a lock-free ring to the libretro audio callbacks; a resampler and
dynamic rate control run on the device thread. The same implementation drives
every release target: miniaudio selects AAudio/OpenSL on Android, Core Audio
on iOS and macOS, WASAPI on Windows, and ALSA, PulseAudio or PipeWire on Linux.
`EZCORE_AUDIO_BACKEND_NULL` selects a silent device that runs at the requested
sample rate for deterministic tests.

#### `ezcore_audio_open`

```c
ezcore_audio *ezcore_audio_open(const ezcore_audio_config *config, char *err,
                                size_t err_len);
```

Opens and starts the playback device. `config` supplies the core and device
sample rates, channel count (two), ring capacity, initial volume, mute state
and backend. On failure `err` receives a human-readable reason.

**Returns:** An opaque device handle, or `NULL` on failure.

**Thread safety:** Call from the emulation thread before frames run.

---

#### `ezcore_audio_close`

```c
void ezcore_audio_close(ezcore_audio *audio);
```

Stops the device, detaches it from the libretro audio callbacks and frees its
buffers. Passing `NULL` is a no-op.

**Thread safety:** Call from the emulation thread after the core stops
producing audio.

---

#### `ezcore_audio_set_volume`

```c
void ezcore_audio_set_volume(ezcore_audio *audio, float volume);
```

Sets a linear gain in the range 0 to 1; values outside the range are clamped.
The change reaches the next device callback.

**Thread safety:** Safe to call while the device is running.

---

#### `ezcore_audio_set_muted`

```c
void ezcore_audio_set_muted(ezcore_audio *audio, bool muted);
```

Mutes or unmutes playback. Muted callbacks still consume core audio and keep
the device clock running.

**Thread safety:** Safe to call while the device is running.

---

#### `ezcore_audio_stats`

```c
bool ezcore_audio_stats(ezcore_audio *audio, ezcore_audio_stats *out);
```

Copies the device counters into `out`: frames written by the core, frames
played, underruns, overruns, buffered frames, ring fill fraction, current
resample ratio, volume, mute state, the device sample rate and whether the
device is running.

**Returns:** `false` when either argument is `NULL`, otherwise `true`.

**Thread safety:** Safe to call while the device is running; the counters are
atomic snapshots, not a single instant across all fields.

---

### Native Run Loop

#### `ezcore_loop_start`

```c
ezcore_loop *ezcore_loop_start(ezcore_session *s, const ezcore_loop_config *config,
                               char *err, size_t err_len);
```

Starts one run thread for a loaded session. `config` may be `NULL` for defaults
(60 Hz pacing, 64 histogram buckets over 40 ms); a `target_fps` of zero uses the
core's reported rate. A session can have only one run loop at a time.

**Returns:** the loop handle, or `NULL` with a message in `err`.

#### `ezcore_loop_stop`

```c
void ezcore_loop_stop(ezcore_loop *loop);
```

Asks the thread to stop, joins it and frees the loop. Safe after the session's
core has crashed only if the loop thread is still alive.

#### `ezcore_loop_frame`

```c
const uint32_t *ezcore_loop_frame(ezcore_loop *loop, unsigned *w, unsigned *h);
```

Pins and returns the newest complete XRGB8888 frame, with its dimensions in
`w` and `h`. Returns `NULL` before the first frame or while another frame is
pinned.

**Thread safety:** Safe to call from the drawing thread. The pinned slot is not
overwritten until `ezcore_loop_frame_release`.

#### `ezcore_loop_frame_release`

```c
void ezcore_loop_frame_release(ezcore_loop *loop);
```

Releases the pinned frame. Never keep the pointer from `ezcore_loop_frame` past
this call.

#### `ezcore_loop_set_button`

```c
void ezcore_loop_set_button(ezcore_loop *loop, unsigned port, unsigned button,
                            bool pressed);
```

Writes one RetroPad button state into an atomic slot. The run thread copies it
into the session before the next `retro_run`, so the caller does not wait for a
frame. `port` is 0-3 and `button` is a `RETRO_DEVICE_ID_JOYPAD_*` value.

#### `ezcore_loop_clear_buttons`

```c
void ezcore_loop_clear_buttons(ezcore_loop *loop, unsigned port);
```

Clears every button on one port through the same atomic slot.

#### `ezcore_loop_set_analog`

```c
void ezcore_loop_set_analog(ezcore_loop *loop, unsigned port, unsigned stick,
                            unsigned axis, int16_t value);
```

Writes one analog axis into an atomic slot. `stick` is 0 (left) or 1 (right),
`axis` is 0 (x) or 1 (y), and `value` is -32768 to 32767.

#### `ezcore_loop_control_pause`

```c
uint64_t ezcore_loop_control_pause(ezcore_loop *loop, bool paused);
```

Queues a pause or resume to be applied between frames. Returns a token, or 0 if
the queue is full.

#### `ezcore_loop_control_fast_forward`

```c
uint64_t ezcore_loop_control_fast_forward(ezcore_loop *loop, uint32_t factor);
```

Queues a fast-forward factor of 1-8. The loop runs that many frames per audio
period and mutes device audio until normal speed resumes.

#### `ezcore_loop_control_save`

```c
uint64_t ezcore_loop_control_save(ezcore_loop *loop, void *out, size_t size);
```

Queues a save state. The run thread writes the state into `out` between frames;
the caller keeps ownership of that buffer and must not read it before the token
has completed.

#### `ezcore_loop_control_load`

```c
uint64_t ezcore_loop_control_load(ezcore_loop *loop, const void *data, size_t size);
```

Queues a save state to load. The bytes are copied when the control is queued, so
the caller may free them immediately.

#### `ezcore_loop_control_reset`

```c
uint64_t ezcore_loop_control_reset(ezcore_loop *loop);
```

Queues a soft reset between frames.

#### `ezcore_loop_control_cheat_reset`

```c
uint64_t ezcore_loop_control_cheat_reset(ezcore_loop *loop);
```

Queues a cheat reset between frames.

#### `ezcore_loop_control_cheat_set`

```c
uint64_t ezcore_loop_control_cheat_set(ezcore_loop *loop, unsigned index,
                                        bool enabled, const char *code);
```

Queues one cheat code. The code string is copied when queued.

#### `ezcore_loop_control_option`

```c
uint64_t ezcore_loop_control_option(ezcore_loop *loop, const char *key,
                                     const char *value);
```

Queues a core option change. Both strings are copied when queued. The control
succeeds only when the loaded core registered that option.

#### `ezcore_loop_control_wait`

```c
bool ezcore_loop_control_wait(ezcore_loop *loop, uint64_t token,
                              uint32_t timeout_ms, bool *result);
```

Waits up to `timeout_ms` for a queued control to be applied and writes whether
the core accepted it to `result`. Returns `false` on an unknown token or a
timeout.

#### `ezcore_loop_stats`

```c
bool ezcore_loop_stats(ezcore_loop *loop, ezcore_loop_statistics *out);
```

Copies a consistent statistics snapshot: frames run, frames dropped when every
buffer slot was ready, controls applied and pending, device underruns, the last,
mean, median, 95th and 99th percentile and maximum frame times, and the frame
histogram. Returns `false` when either argument is `NULL`. Safe to poll at any
rate.

---

### Cheats

#### `ezcore_cheat_reset`

```c
void ezcore_cheat_reset(ezcore_session *s);
```

Resets all cheats. Calls `retro_cheat_reset` when the core exports it;
otherwise this is a safe no-op.

**Parameters:**
- `s` — session pointer

---

#### `ezcore_cheat_set`

```c
bool ezcore_cheat_set(ezcore_session *s, unsigned index, bool enabled,
                      const char *code);
```

Attempts to set a cheat code. Calls `retro_cheat_set` when the core exports it.
The libretro hook has no return value, so this does not validate the code or
confirm that the core applied its effect.

**Parameters:**
- `s` — session pointer
- `index` — cheat slot index (0-based)
- `enabled` — whether the cheat is active
- `code` — cheat code string (GameShark/Action Replay format)

**Returns:** `true` when a non-null code was dispatched to an available core
hook; `false` when the runtime cannot dispatch it (for example, a missing core
hook or null code). It does not indicate code validity.

---

### Save States

#### `ezcore_serialize_size`

```c
size_t ezcore_serialize_size(ezcore_session *s);
```

Returns the size of the save state in bytes. Calls `retro_serialize_size`.

**Parameters:**
- `s` — session pointer

**Returns:** Size in bytes, or 0 if save states are not supported or no game is loaded.

---

#### `ezcore_serialize`

```c
bool ezcore_serialize(ezcore_session *s, void *out, size_t size);
```

Serializes the current state to a buffer. Calls `retro_serialize`.

**Parameters:**
- `s` — session pointer
- `out` — output buffer (must be at least `ezcore_serialize_size` bytes)
- `size` — size of output buffer

**Returns:** `true` on success, `false` on failure.

**Note:** The bytes are opaque — the frontend never interprets them. They are stored as-is and passed to `ezcore_unserialize` later.

---

#### `ezcore_unserialize`

```c
bool ezcore_unserialize(ezcore_session *s, const void *data, size_t size);
```

Restores a previously saved state. Calls `retro_unserialize`.

**Parameters:**
- `s` — session pointer
- `data` — save state data (from `ezcore_serialize`)
- `size` — size of data in bytes

**Returns:** `true` on success, `false` on failure.

---

## Core Options & Capability Surface

The runtime deep-copies every string the core supplies via the libretro
environment calls (`RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2`,
`SET_CORE_OPTIONS_INTL`, `SET_INPUT_DESCRIPTORS`, `SET_CONTROLLER_INFO`,
`SET_MEMORY_MAPS`).  The host-owned copies persist until `ezcore_unload`
or the next `SET_CORE_OPTIONS*` call.  All out-pointer parameters return
pointers into runtime-owned memory — do **not** free them.

### Core Options

#### `ezcore_get_core_option_count`

```c
unsigned ezcore_get_core_option_count(ezcore_session *s);
```

Returns the number of core options registered by the loaded core via
`RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2` or `SET_CORE_OPTIONS_INTL`.

**Parameters:**
- `s` — session pointer

**Returns:** Option count (0 when none registered or `s` is invalid).

#### `ezcore_get_core_option`

```c
bool ezcore_get_core_option(ezcore_session *s, unsigned index,
                            const char **key, const char **default_value,
                            const char **value);
```

Retrieves a stored core option by zero-based index.  The `value` field is
the current selection (initialised to `default_value` when the option is
registered, then changed by `ezcore_set_core_option`).

**Parameters:**
- `s` — session pointer
- `index` — zero-based option index
- `key` — output: option key
- `default_value` — output: default value for the option
- `value` — output: current value (may differ from default after
  `ezcore_set_core_option`)

**Returns:** `true` on success, `false` if the index is out of range or
`s` is invalid.

#### `ezcore_set_core_option`

```c
bool ezcore_set_core_option(ezcore_session *s, const char *key,
                            const char *value);
```

Sets the current value of a core option identified by `key`.  The new
value is deep-copied into runtime memory; the caller's `value` pointer
may be freed or reused immediately after the call returns.

**Parameters:**
- `s` — session pointer
- `key` — option key (must match a registered option)
- `value` — new value string

**Returns:** `true` when `key` matched a registered option, `false`
otherwise (including when `s` or `key` is NULL).

### Input Descriptors

#### `ezcore_get_input_descriptor_count`

```c
unsigned ezcore_get_input_descriptor_count(ezcore_session *s);
```

Returns the number of input descriptors registered via
`RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS`.  Returns 0 when none or
`s` is invalid.

#### `ezcore_get_input_descriptor`

```c
bool ezcore_get_input_descriptor(ezcore_session *s, unsigned index,
                                 unsigned *port, unsigned *device,
                                 unsigned *desc_index, unsigned *id,
                                 const char **description);
```

Retrieves a stored input descriptor by zero-based index.  Any of the
out-params may be NULL (skipped).  The `description` pointer is
runtime-owned (do not free).

**Returns:** `true` on success, `false` if the index is out of range.

### Controller Info

#### `ezcore_get_controller_port_count`

```c
unsigned ezcore_get_controller_port_count(ezcore_session *s);
```

Returns the number of controller ports with info registered via
`RETRO_ENVIRONMENT_SET_CONTROLLER_INFO`.  Returns 0 when none or
`s` is invalid.

#### `ezcore_get_controller_port_type_count`

```c
unsigned ezcore_get_controller_port_type_count(ezcore_session *s, unsigned port);
```

Returns the number of device types the core registered for one port via
`RETRO_ENVIRONMENT_SET_CONTROLLER_INFO`.  Returns 0 when the port is out of
range, the core registered none, or `s` is invalid.

A port count of 1 tells you a core has ports, not which devices they accept.
This is the first half of that answer.

#### `ezcore_get_controller_port_type`

```c
bool ezcore_get_controller_port_type(ezcore_session *s, unsigned port,
                                     unsigned type_index, unsigned *id,
                                     const char **description);
```

Retrieves one device type of one port.  On success fills any non-NULL
out-params.  `description` is runtime-owned and valid for the session
lifetime (do not free).

**Returns:** `true` on success, `false` if the port or the type index is out
of range.

Iterate `port` over `0..ezcore_get_controller_port_count` and `type_index`
over `0..ezcore_get_controller_port_type_count` to enumerate every device a
core accepts on every port — `RETRO_DEVICE_JOYPAD`, `RETRO_DEVICE_MOUSE`,
`RETRO_DEVICE_LIGHTGUN` and the rest.  This is what a frontend needs to offer
the right control scheme per port, and it is the prerequisite for P3's
non-joypad device support: until a core's declared capabilities were readable,
a frontend could only assume every port is a joypad.

### Memory Map

#### `ezcore_get_memory_descriptor_count`

```c
unsigned ezcore_get_memory_descriptor_count(ezcore_session *s);
```

Returns the number of memory-map descriptors registered via
`RETRO_ENVIRONMENT_SET_MEMORY_MAPS`.  Returns 0 when none or `s` is
invalid.

#### `ezcore_get_memory_descriptor`

```c
bool ezcore_get_memory_descriptor(ezcore_session *s, unsigned index,
                                  uint64_t *flags, void **ptr,
                                  size_t *offset, size_t *start,
                                  size_t *select, size_t *disconnect,
                                  size_t *len, const char **addrspace);
```

Retrieves a stored memory descriptor by zero-based index.  The `ptr`
field aliases core-owned memory (valid for the session lifetime); all
other out-params copy runtime-owned metadata.  Any out-param may be
NULL.

**Returns:** `true` on success, `false` if the index is out of range.

#### `ezcore_get_legacy_memory`

```c
bool ezcore_get_legacy_memory(ezcore_session *s, unsigned id,
                              void **ptr, size_t *size);
```

Fallback for cores with no `SAVE_RAM`-flagged memory-map descriptor: reads the
legacy `retro_get_memory_data`/`retro_get_memory_size` entry points for the
requested libretro memory id. The returned pointer aliases core-owned memory
valid for the session lifetime. Empty regions and cores without the optional
entry points return `false`.

**Returns:** `true` when a non-empty legacy memory region is available.

---

## Error Handling

All functions that can fail follow one of two patterns:

1. **Return NULL/false** — the function returns a null pointer or false, and the error buffer is filled
2. **Return 0** — the function returns 0 (size_t) indicating failure

The Flutter layer checks all return values and surfaces errors to the user.

---

## Thread Safety

| Function | Thread Safety |
|---|---|
| `ezcore_abi_version` | Thread-safe |
| `ezcore_set_dirs` | Not thread-safe (call once at startup) |
| `ezcore_load` | Not thread-safe |
| `ezcore_unload` | Not thread-safe |
| `ezcore_init` | Not thread-safe |
| `ezcore_load_game` | Not thread-safe |
| `ezcore_run_frame` | Not thread-safe (single emulation thread) |
| `ezcore_core_name` | Thread-safe (read-only) |
| `ezcore_core_version` | Thread-safe (read-only) |
| `ezcore_system_geometry` | Not thread-safe (call from emulation thread) |
| `ezcore_frame_pixels` | Not thread-safe (call from emulation thread) |
| `ezcore_audio_drain` | Not thread-safe (serialise against `ezcore_run_frame`) |
| `ezcore_reset` | Not thread-safe (emulation thread) |
| `ezcore_sample_rate` | Not thread-safe (emulation thread — queries the core) |
| `ezcore_set_button` | Not thread-safe (emulation thread) |
| `ezcore_clear_buttons` | Not thread-safe (emulation thread) |
| `ezcore_frame_size` | Not thread-safe (emulation thread) |
| `ezcore_frame_pixels_copy` | Not thread-safe (emulation thread) |
| `ezcore_video_attach` | Not thread-safe (call before the session runs) |
| `ezcore_video_detach` | Not thread-safe (call after the session stops) |
| `ezcore_video_present` | Not thread-safe (emulation thread) |
| `ezcore_video_stats` | Thread-safe (snapshot behind a lock) |
| `ezcore_video_blit_rows` | Thread-safe (operates on caller buffers) |
| `ezcore_audio_drain_copy` | Not thread-safe (serialise against `ezcore_run_frame`) |
| `ezcore_audio_pending` | Not thread-safe (emulation thread) |
| `ezcore_cheat_reset` | Not thread-safe |
| `ezcore_cheat_set` | Not thread-safe |
| `ezcore_serialize_size` | Not thread-safe |
| `ezcore_serialize` | Not thread-safe |
| `ezcore_unserialize` | Not thread-safe |
| `ezcore_get_core_option_count` | Not thread-safe (reads session-owned storage) |
| `ezcore_get_core_option` | Not thread-safe (reads session-owned storage) |
| `ezcore_set_core_option` | Not thread-safe (mutates session-owned storage) |
| `ezcore_get_input_descriptor_count` | Not thread-safe (reads session-owned storage) |
| `ezcore_get_input_descriptor` | Not thread-safe (reads session-owned storage) |
| `ezcore_get_controller_port_count` | Not thread-safe (reads session-owned storage) |
| `ezcore_get_memory_descriptor_count` | Not thread-safe (reads session-owned storage) |
| `ezcore_get_memory_descriptor` | Not thread-safe (reads session-owned storage) |
| `ezcore_get_legacy_memory` | Not thread-safe (aliases core-owned memory) |

**Typical usage:** One thread owns the session and runs `ezcore_run_frame` in a loop. Everything else — audio drain, input, cheats, save states — happens on that thread, or between frames with the caller serialising. The runtime has no internal locks; the frontend owns the concurrency.

---

## Memory Management

- The runtime owns all memory associated with a session
- The frontend never frees runtime-allocated memory
- Frame buffers and audio rings are freed by `ezcore_unload`
- Save state buffers are owned by the frontend (allocated before `ezcore_serialize`)

---

## Future ABI Extensions

When new features are added, the ABI version is bumped and new functions are appended. Existing functions never change signature.

Planned for ABI v2:
- `ezcore_get_log` — retrieve core log messages
- `ezcore_get_perf` — performance counters (frame time, audio latency)
- per-game core options (GL-renderer cores currently need them)

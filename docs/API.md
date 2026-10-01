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
- `save_dir` — path to save directory (save states, SRAM, etc.)

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

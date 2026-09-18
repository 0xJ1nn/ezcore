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

```c
#define EZCORE_PIXEL_XRGB8888 0
#define EZCORE_PIXEL_0RGB1555 1
#define EZCORE_PIXEL_RGB565   2
```

The runtime always presents frames as XRGB8888 to the frontend. Cores that request other formats are converted internally.

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

**Thread safety:** Safe to call from a different thread than `ezcore_run_frame`.

---

### Cheats

#### `ezcore_cheat_reset`

```c
void ezcore_cheat_reset(ezcore_session *s);
```

Resets all cheats. Calls `retro_cheat_reset`.

**Parameters:**
- `s` — session pointer

---

#### `ezcore_cheat_set`

```c
bool ezcore_cheat_set(ezcore_session *s, unsigned index, bool enabled,
                      const char *code);
```

Sets a cheat code. Calls `retro_cheat_set`.

**Parameters:**
- `s` — session pointer
- `index` — cheat slot index (0-based)
- `enabled` — whether the cheat is active
- `code` — cheat code string (GameShark/Action Replay format)

**Returns:** `true` on success, `false` on failure (e.g., invalid code format).

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
| `ezcore_audio_drain` | Thread-safe (safe from audio thread) |
| `ezcore_cheat_reset` | Not thread-safe |
| `ezcore_cheat_set` | Not thread-safe |
| `ezcore_serialize_size` | Not thread-safe |
| `ezcore_serialize` | Not thread-safe |
| `ezcore_unserialize` | Not thread-safe |

**Typical usage:** One emulation thread runs `ezcore_run_frame` in a loop. The audio thread calls `ezcore_audio_drain`. The main thread calls everything else (load, unload, cheats, saves) when the user interacts.

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

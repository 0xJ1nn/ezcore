// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

#ifndef EZCORE_RUNTIME_H
#define EZCORE_RUNTIME_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define EZCORE_ABI_VERSION 1

/* Opaque session bound to one loaded libretro core. */
typedef struct ezcore_session ezcore_session;

/* ABI every core plugin must satisfy (== libretro API version 1). */
int ezcore_abi_version(void);

/* Host-owned content directories. Call before ezcore_load when cores need
 * system/save paths (mupen64plus crashes without them). */
void ezcore_set_dirs(const char *system_dir, const char *save_dir);

/* Lifecycle */
ezcore_session *ezcore_load(const char *core_path, char *err, size_t err_len);
void ezcore_unload(ezcore_session *s);
bool ezcore_init(ezcore_session *s);
bool ezcore_load_game(ezcore_session *s, const char *rom_path,
                   const void *data, size_t size);
void ezcore_run_frame(ezcore_session *s);
/* Soft-reset the currently loaded game. Safe only after load_game. */
void ezcore_reset(ezcore_session *s);

/* Introspection (geometry requires a successfully loaded game — several
 * cores crash on pre-load AV queries; the runtime returns zeros before). */
const char *ezcore_core_name(ezcore_session *s);
const char *ezcore_core_version(ezcore_session *s);
void ezcore_system_geometry(ezcore_session *s, unsigned *w, unsigned *h,
                         double *fps);
/* Sample rate from AV timing. Valid after load_game. */
double ezcore_sample_rate(ezcore_session *s);

/* Input: set/clear individual button state. button_id is RETRO_DEVICE_ID_JOYPAD_*.
 * port is the player index (0..3). */
void ezcore_set_button(ezcore_session *s, unsigned port, unsigned button_id,
                    bool pressed);
void ezcore_clear_buttons(ezcore_session *s, unsigned port);

/* Analog stick: stick 0 = left, 1 = right (RETRO_DEVICE_INDEX_ANALOG_*);
 * axis 0 = x, 1 = y; value -32768..32767. Analog-button reads (pressure
 * triggers) follow the digital button state: pressed reads 0x7fff. */
void ezcore_set_analog(ezcore_session *s, unsigned port, unsigned stick,
                       unsigned axis, int16_t value);

/* Mouse (port 0). Motion accumulates until the next ezcore_run_frame, which
 * hands the core one delta for the whole frame. id is RETRO_DEVICE_ID_MOUSE_*
 * (LEFT, RIGHT, MIDDLE, WHEELUP, ...). */
void ezcore_mouse_move(ezcore_session *s, int dx, int dy);
void ezcore_set_mouse_button(ezcore_session *s, unsigned id, bool pressed);

/* Keyboard (port 0). keycode is a RETROK_* value; character is the UTF-32
 * character typed, or 0; modifiers are RETROKMOD_* bits. Updates the polled
 * key state and, when the core registered one, calls its keyboard callback. */
void ezcore_set_key(ezcore_session *s, unsigned keycode, bool pressed,
                    uint32_t character, uint16_t modifiers);

/* Pointer / touchscreen (port 0). x and y span the core's whole output,
 * -32767 (left/top) .. 32767 (right/bottom). */
void ezcore_set_pointer(ezcore_session *s, int16_t x, int16_t y, bool pressed);

/* Cheats — optional core entry points. If unsupported, reset is a no-op and
 * set returns false. A true set result means dispatch was attempted; the
 * libretro hook is void and cannot report code validation. */
void ezcore_cheat_reset(ezcore_session *s);
bool ezcore_cheat_set(ezcore_session *s, unsigned index, bool enabled,
                   const char *code);

/* Video: latest frame pixels (XRGB8888).
 * Copies the frame into `out` as RGBA bytes. out must be >= w*h*4 bytes.
 * Returns bytes copied (w*h*4) or 0 if no frame yet. */
size_t ezcore_frame_pixels_copy(ezcore_session *s, uint8_t *out,
                             size_t out_size);

/* Frame dimensions. 0 when no frame yet. */
void ezcore_frame_size(ezcore_session *s, unsigned *w, unsigned *h);

/* Returns const pointer to latest frame (XRGB8888). Do NOT free. Fast read access. */
const uint32_t *ezcore_frame_pixels(ezcore_session *s, unsigned *w, unsigned *h);

/* --- Video texture bridge (Android) ---
 * A Flutter SurfaceProducer owns an android.view.Surface. Its ANativeWindow is
 * attached to a session here, and each completed frame is blitted into the
 * window (CPU-core path). HW-render cores hand an EGL surface to the bridge in
 * later work; this path is the RGBA blit both use for presentation. The same
 * calls work with a fake window handle on a host for state tests, but only an
 * Android build can present into a real ANativeWindow. */
typedef struct {
  uint64_t presents;       /* frames copied into the window */
  uint64_t failed_presents;/* present calls with no frame or no window */
  unsigned width;          /* geometry set at attach time */
  unsigned height;
  bool attached;
} ezcore_video_statistics;

bool ezcore_video_attach(ezcore_session *s, void *window, unsigned width,
                         unsigned height);
void ezcore_video_detach(ezcore_session *s);
bool ezcore_video_present(ezcore_session *s);
bool ezcore_video_stats(ezcore_session *s, ezcore_video_statistics *out);

/* Copies XRGB8888 [src] into 32-bit [dst] rows of [dst_stride] bytes. When
 * [bgra] is true the byte order is B,G,R,A; otherwise R,G,B,A. Alpha is 255.
 * Platform-neutral so the copy can be verified without an Android device. */
bool ezcore_video_blit_rows(uint8_t *dst, size_t dst_stride,
                            const uint32_t *src, unsigned width,
                            unsigned height, bool bgra);

/* --- Native audio device ---
 * One process-wide playback device, fed by the current session's libretro
 * audio callbacks. It owns the lock-free frame ring, the resampler and the
 * dynamic rate control; the platform backend and device clock come from
 * miniaudio, so the same code runs on all five release targets. Open it once
 * the core's sample rate is known and close it before the session unloads. */
typedef struct ezcore_audio ezcore_audio;

typedef enum {
  EZCORE_AUDIO_BACKEND_AUTO = 0, /* platform default (AAudio, Core Audio, WASAPI, ...) */
  EZCORE_AUDIO_BACKEND_NULL = 1  /* deterministic device for tests */
} ezcore_audio_backend;

typedef struct {
  uint32_t input_sample_rate;  /* core rate from retro_get_system_av_info */
  uint32_t output_sample_rate; /* device rate, normally 48000 */
  uint32_t channels;           /* libretro is stereo: 2 */
  uint32_t ring_frames;        /* ring capacity in frames; nearest power of two */
  float volume;                /* 0..1 linear gain */
  bool muted;
  ezcore_audio_backend backend;
} ezcore_audio_config;

typedef struct {
  uint64_t frames_written;  /* frames accepted from the core into the ring */
  uint64_t frames_played;   /* frames delivered to the device */
  uint64_t underruns;       /* callbacks that ran out of core audio */
  uint64_t overruns;        /* frames dropped because the ring was full */
  size_t buffered_frames;   /* frames in the ring at the time of the call */
  double fill_fraction;     /* 0..1 of ring capacity */
  double rate_ratio;        /* current resample ratio (input/output) */
  float volume;
  bool muted;
  bool device_running;
  uint32_t output_sample_rate; /* device rate; used to pace the run loop */
} ezcore_audio_statistics;

ezcore_audio *ezcore_audio_open(const ezcore_audio_config *config, char *err,
                                size_t err_len);
void ezcore_audio_close(ezcore_audio *audio);
void ezcore_audio_set_volume(ezcore_audio *audio, float volume);
void ezcore_audio_set_muted(ezcore_audio *audio, bool muted);
bool ezcore_audio_stats(ezcore_audio *audio, ezcore_audio_statistics *out);

/* --- Native run loop ---
 * The runtime owns one thread per session. It calls retro_run paced by the
 * audio device clock (or a monotonic clock when no device is open), publishes
 * frames into a three-slot buffer where the newest complete frame wins, and
 * applies input and control changes written from any thread without waiting
 * for a frame. Used both in-process and by the supervised host process. */
typedef struct ezcore_loop ezcore_loop;

typedef struct {
  uint32_t target_fps;       /* pacing rate; 0 uses the core's geometry fps */
  uint32_t histogram_buckets;/* frame-time histogram size; 0 selects 16 */
  double histogram_max_ms;   /* widest bucket; 0 selects 40 ms */
} ezcore_loop_config;

typedef struct {
  uint64_t frames_run;         /* frames completed by the loop thread */
  uint64_t dropped_frames;     /* frames replaced before a reader pinned them */
  uint64_t control_applied;    /* controls applied so far */
  uint64_t control_pending;    /* controls waiting at the time of the snapshot */
  uint64_t audio_underruns;    /* device underruns sampled from the audio device */
  double frame_last_ms;        /* duration of the last frame's work */
  double frame_mean_ms;
  double frame_p50_ms;
  double frame_p95_ms;
  double frame_p99_ms;
  double frame_max_ms;
  size_t histogram_len;        /* number of buckets in histogram */
  const uint32_t *histogram;   /* bucket i counts frames under (i+1)*max/len ms */
} ezcore_loop_statistics;

/* Starts the run thread for a loaded session. Fails when the session is NULL
 * or a second loop is already running for it. Stops joins the thread. */
ezcore_loop *ezcore_loop_start(ezcore_session *s, const ezcore_loop_config *config,
                               char *err, size_t err_len);
void ezcore_loop_stop(ezcore_loop *loop);

/* Pins the newest complete frame for reading: returns XRGB8888 pixels and
 * their dimensions, or NULL when no frame has been published yet. The slot
 * cannot be overwritten until ezcore_loop_frame_release. Never free or keep
 * the pointer past the release. */
const uint32_t *ezcore_loop_frame(ezcore_loop *loop, unsigned *w, unsigned *h);
void ezcore_loop_frame_release(ezcore_loop *loop);

/* Input written from Dart through FFI. The loop copies these atomics into the
 * session immediately before each retro_run, so no frame round trip is needed. */
void ezcore_loop_set_button(ezcore_loop *loop, unsigned port, unsigned button,
                            bool pressed);
void ezcore_loop_clear_buttons(ezcore_loop *loop, unsigned port);
void ezcore_loop_set_analog(ezcore_loop *loop, unsigned port, unsigned stick,
                            unsigned axis, int16_t value);

/* Control queue. Each call returns a token (0 means the queue was full) and
 * is applied on the loop thread between two frames. Wait with a timeout in
 * milliseconds; *result receives whether the core accepted the control. */
uint64_t ezcore_loop_control_pause(ezcore_loop *loop, bool paused);
uint64_t ezcore_loop_control_fast_forward(ezcore_loop *loop, uint32_t factor);
uint64_t ezcore_loop_control_save(ezcore_loop *loop, void *out, size_t size);
uint64_t ezcore_loop_control_load(ezcore_loop *loop, const void *data, size_t size);
uint64_t ezcore_loop_control_reset(ezcore_loop *loop);
uint64_t ezcore_loop_control_cheat_reset(ezcore_loop *loop);
uint64_t ezcore_loop_control_cheat_set(ezcore_loop *loop, unsigned index,
                                        bool enabled, const char *code);
uint64_t ezcore_loop_control_option(ezcore_loop *loop, const char *key,
                                     const char *value);
bool ezcore_loop_control_wait(ezcore_loop *loop, uint64_t token,
                              uint32_t timeout_ms, bool *result);
bool ezcore_loop_stats(ezcore_loop *loop, ezcore_loop_statistics *out);

/* Audio: frames appended by the audio batch callback; drained by player. */
size_t ezcore_audio_drain(ezcore_session *s, int16_t *out, size_t frames);
size_t ezcore_audio_drain_copy(ezcore_session *s, int16_t *out,
                            size_t max_frames);
/* Current number of audio frames queued in the ring buffer. */
size_t ezcore_audio_pending(ezcore_session *s);

/* Save states (runtime-owned; local vault today, sync providers tomorrow).
 * All three require a loaded game and degrade to 0/false when the core
 * omits the entry points. */
size_t ezcore_serialize_size(ezcore_session *s);
bool ezcore_serialize(ezcore_session *s, void *out, size_t size);
bool ezcore_unserialize(ezcore_session *s, const void *data, size_t size);

/* --- Core Options & Capability Surface ---
 * The runtime stores deep copies of everything the core hands to
 * env_cb via the libretro environment calls below.  Strings originate
 * from the core (core-owned lifetimes) and are duplicated into
 * runtime-owned heap memory so they remain valid for the lifetime of
 * the session.  All out-pointers point into runtime-owned memory valid
 * until ezcore_unload or the next SET_CORE_OPTIONS* call. */

/* Number of core options registered by the loaded core (via
 * RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2 or SET_CORE_OPTIONS_INTL).
 * Returns 0 when none have been registered or the session is invalid. */
unsigned ezcore_get_core_option_count(ezcore_session *s);

/* Retrieve a core option by zero-based index.
 * On success, fills any non-NULL out-params with runtime-owned strings
 * (key, default_value, current value).  Returns false if the index is
 * out of range or the session is invalid. */
bool ezcore_get_core_option(ezcore_session *s, unsigned index,
                            const char **key, const char **default_value,
                            const char **value);

/* Set the current value of a core option by key.  The value is deep-copied
 * into runtime memory; the caller's string may be freed or reused afterwards.
 * Returns true when the key matched an existing option, false otherwise.
 * The core reads the value through RETRO_ENVIRONMENT_GET_VARIABLE; a value
 * that differs from the current one is reported to it once through
 * RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE.  Many cores read options only inside
 * retro_load_game, so set them after ezcore_load and before
 * ezcore_load_game for them to apply from the first frame. */
bool ezcore_set_core_option(ezcore_session *s, const char *key,
                            const char *value);

/* Number of input descriptors registered via
 * RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS.  Returns 0 when none or
 * the session is invalid. */
unsigned ezcore_get_input_descriptor_count(ezcore_session *s);

/* Retrieve an input descriptor by zero-based index.  On success fills any
 * non-NULL out-params.  Returns false if the index is out of range. */
bool ezcore_get_input_descriptor(ezcore_session *s, unsigned index,
                                 unsigned *port, unsigned *device,
                                 unsigned *desc_index, unsigned *id,
                                 const char **description);

/* Number of controller ports with info registered via
 * RETRO_ENVIRONMENT_SET_CONTROLLER_INFO.  Returns 0 when none or
 * the session is invalid. */
unsigned ezcore_get_controller_port_count(ezcore_session *s);

/* Number of device types the core registered for one port via
 * RETRO_ENVIRONMENT_SET_CONTROLLER_INFO.  Returns 0 when the port is out of
 * range, the core registered none, or the session is invalid. */
unsigned ezcore_get_controller_port_type_count(ezcore_session *s, unsigned port);

/* Retrieve one device type of one port.  On success fills any non-NULL
 * out-params; \c description is runtime-owned and valid for the session
 * lifetime.  Returns false if the port or the type index is out of range. */
bool ezcore_get_controller_port_type(ezcore_session *s, unsigned port,
                                     unsigned type_index, unsigned *id,
                                     const char **description);

/* Number of memory-map descriptors registered via
 * RETRO_ENVIRONMENT_SET_MEMORY_MAPS.  Returns 0 when none or
 * the session is invalid. */
unsigned ezcore_get_memory_descriptor_count(ezcore_session *s);

/* Retrieve a memory-map descriptor by zero-based index.  On success fills
 * any non-NULL out-params.  The \c ptr field points into core-owned memory
 * (NOT copied by the runtime); all other fields are runtime-owned copies.
 * Returns false if the index is out of range. */
bool ezcore_get_memory_descriptor(ezcore_session *s, unsigned index,
                                  uint64_t *flags, void **ptr,
                                  size_t *offset, size_t *start,
                                  size_t *select, size_t *disconnect,
                                  size_t *len, const char **addrspace);

#ifdef __cplusplus
}
#endif

#endif /* EZCORE_RUNTIME_H */

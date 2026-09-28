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

#ifdef __cplusplus
}
#endif

#endif /* EZCORE_RUNTIME_H */

#ifndef HUH_BRIDGE_H
#define HUH_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define HUH_ABI_VERSION 1

/* Opaque session bound to one loaded libretro core. */
typedef struct huh_session huh_session;

/* ABI every core plugin must satisfy (== libretro API version 1). */
int huh_abi_version(void);

/* Lifecycle */
huh_session *huh_load(const char *core_path, char *err, size_t err_len);
void huh_unload(huh_session *s);
bool huh_init(huh_session *s);
bool huh_load_game(huh_session *s, const char *rom_path,
                   const void *data, size_t size);
void huh_run_frame(huh_session *s);

/* Introspection (geometry requires a successfully loaded game — several
 * cores crash on pre-load AV queries; the bridge returns zeros before). */
const char *huh_core_name(huh_session *s);
const char *huh_core_version(huh_session *s);
void huh_system_geometry(huh_session *s, unsigned *w, unsigned *h,
                         double *fps);

/* Cheats — forward to retro_cheat_reset / retro_cheat_set */
void huh_cheat_reset(huh_session *s);
bool huh_cheat_set(huh_session *s, unsigned index, bool enabled,
                   const char *code);

/* Video: latest frame copied here by the video refresh callback.
 * Flavor 0 = XRGB8888. Caller reads w*h pixels after huh_run_frame. */
const uint32_t *huh_frame_pixels(huh_session *s, unsigned *w, unsigned *h);

/* Audio: frames appended by the audio batch callback; drained by player. */
size_t huh_audio_drain(huh_session *s, int16_t *out, size_t frames);

#ifdef __cplusplus
}
#endif

#endif /* HUH_BRIDGE_H */

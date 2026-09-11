/* huh bridge — loads a libretro core dylib and forwards the session API.
 * Desktop/Android path: dlopen at runtime after sha256 verification.
 * iOS path: cores are linked/bundled; huh_load resolves bundled symbols.
 */
#include "libretro_bridge.h"

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "libretro.h"

struct huh_session {
  void *handle;
  char core_path[1024];
  /* libretro entry points */
  void (*retro_init)(void);
  void (*retro_deinit)(void);
  unsigned (*retro_api_version)(void);
  void (*retro_get_system_info)(struct retro_system_info *);
  void (*retro_get_system_av_info)(struct retro_system_av_info *);
  bool (*retro_load_game)(const struct retro_game_info *);
  void (*retro_run)(void);
  void (*retro_cheat_reset)(void);
  void (*retro_cheat_set)(unsigned, bool, const char *);
  /* latest video frame (owned, XRGB8888) */
  uint32_t *frame;
  unsigned frame_w, frame_h;
  /* audio ring (stereo s16) */
  int16_t *audio;
  size_t audio_cap, audio_len;
  char name[128];
  char version[64];
};

static huh_session *g_active = NULL;

/* ---- environment / callbacks (minimal v0 set; extended per TODO) ---- */

static bool env_cb(unsigned cmd, void *data) {
  (void)cmd;
  (void)data;
  return false;
}

static void video_cb(const void *data, unsigned width, unsigned height,
                     size_t pitch) {
  if (!g_active || !data) return;
  huh_session *s = g_active;
  if (width != s->frame_w || height != s->frame_h) {
    free(s->frame);
    s->frame = malloc((size_t)width * height * 4);
    if (!s->frame) return;
    s->frame_w = width;
    s->frame_h = height;
  }
  const uint8_t *src = data;
  for (unsigned y = 0; y < height; y++) {
    memcpy(s->frame + (size_t)y * width,
           src + (size_t)y * pitch, (size_t)width * 4);
  }
}

static void audio_sample_cb(int16_t left, int16_t right) {
  if (!g_active) return;
  huh_session *s = g_active;
  if (s->audio_len + 1 > s->audio_cap) return; /* drop on overflow (v0) */
  s->audio[s->audio_len * 2] = left;
  s->audio[s->audio_len * 2 + 1] = right;
  s->audio_len++;
}

static size_t audio_batch_cb(const int16_t *data, size_t frames) {
  for (size_t i = 0; i < frames; i++)
    audio_sample_cb(data[i * 2], data[i * 2 + 1]);
  return frames;
}

static void input_poll_cb(void) {}
static int16_t input_state_cb(unsigned a, unsigned b, unsigned c, unsigned d) {
  (void)a; (void)b; (void)c; (void)d;
  return 0;
}

/* ---- public API ---- */

int huh_abi_version(void) { return HUH_ABI_VERSION; }

#define LOAD_SYM(s, field, sym)                                  \
  do {                                                           \
    s->field = dlsym(s->handle, sym);                            \
    if (!s->field) {                                             \
      snprintf(err, err_len, "core missing symbol: %s", sym);    \
      dlclose(s->handle);                                        \
      free(s);                                                   \
      return NULL;                                               \
    }                                                            \
  } while (0)

huh_session *huh_load(const char *core_path, char *err, size_t err_len) {
  huh_session *s = calloc(1, sizeof(*s));
  if (!s) return NULL;
  snprintf(s->core_path, sizeof(s->core_path), "%s", core_path);
  s->handle = dlopen(core_path, RTLD_NOW | RTLD_LOCAL);
  if (!s->handle) {
    snprintf(err, err_len, "dlopen failed: %s", dlerror());
    free(s);
    return NULL;
  }
  LOAD_SYM(s, retro_init, "retro_init");
  LOAD_SYM(s, retro_deinit, "retro_deinit");
  LOAD_SYM(s, retro_api_version, "retro_api_version");
  LOAD_SYM(s, retro_get_system_info, "retro_get_system_info");
  LOAD_SYM(s, retro_get_system_av_info, "retro_get_system_av_info");
  LOAD_SYM(s, retro_load_game, "retro_load_game");
  LOAD_SYM(s, retro_run, "retro_run");
  LOAD_SYM(s, retro_cheat_reset, "retro_cheat_reset");
  LOAD_SYM(s, retro_cheat_set, "retro_cheat_set");

  if (s->retro_api_version() != 1) {
    snprintf(err, err_len, "unsupported libretro API version");
    dlclose(s->handle);
    free(s);
    return NULL;
  }
  struct retro_system_info info = {0};
  s->retro_get_system_info(&info);
  snprintf(s->name, sizeof(s->name), "%s",
           info.library_name ? info.library_name : "?");
  snprintf(s->version, sizeof(s->version), "%s",
           info.library_version ? info.library_version : "?");

  void (*set_env)(retro_environment_t) =
      dlsym(s->handle, "retro_set_environment");
  void (*set_video)(retro_video_refresh_t) =
      dlsym(s->handle, "retro_set_video_refresh");
  void (*set_audio)(retro_audio_sample_t) =
      dlsym(s->handle, "retro_set_audio_sample");
  void (*set_audio_batch)(retro_audio_sample_batch_t) =
      dlsym(s->handle, "retro_set_audio_sample_batch");
  void (*set_poll)(retro_input_poll_t) =
      dlsym(s->handle, "retro_set_input_poll");
  void (*set_state)(retro_input_state_t) =
      dlsym(s->handle, "retro_set_input_state");
  if (set_env) set_env(env_cb);
  if (set_video) set_video(video_cb);
  if (set_audio) set_audio(audio_sample_cb);
  if (set_audio_batch) set_audio_batch(audio_batch_cb);
  if (set_poll) set_poll(input_poll_cb);
  if (set_state) set_state(input_state_cb);

  s->audio_cap = 8192;
  s->audio = malloc(s->audio_cap * 2 * sizeof(int16_t));
  return s;
}

void huh_unload(huh_session *s) {
  if (!s) return;
  if (g_active == s) g_active = NULL;
  s->retro_deinit();
  dlclose(s->handle);
  free(s->frame);
  free(s->audio);
  free(s);
}

bool huh_init(huh_session *s) {
  if (!s) return false;
  g_active = s;
  s->retro_init();
  return true;
}

bool huh_load_game(huh_session *s, const char *rom_path, const void *data,
                   size_t size) {
  if (!s) return false;
  struct retro_game_info info = {rom_path, data, size, NULL};
  return s->retro_load_game(&info);
}

void huh_run_frame(huh_session *s) {
  if (!s) return;
  g_active = s;
  s->retro_run();
}

const char *huh_core_name(huh_session *s) { return s ? s->name : "?"; }
const char *huh_core_version(huh_session *s) { return s ? s->version : "?"; }

void huh_system_geometry(huh_session *s, unsigned *w, unsigned *h,
                         double *fps) {
  if (!s) return;
  struct retro_system_av_info av;
  memset(&av, 0, sizeof(av));
  s->retro_get_system_av_info(&av);
  if (w) *w = av.geometry.base_width;
  if (h) *h = av.geometry.base_height;
  if (fps) *fps = av.timing.fps;
}

void huh_cheat_reset(huh_session *s) {
  if (s) s->retro_cheat_reset();
}

bool huh_cheat_set(huh_session *s, unsigned index, bool enabled,
                   const char *code) {
  if (!s || !code) return false;
  s->retro_cheat_set(index, enabled, code);
  return true;
}

const uint32_t *huh_frame_pixels(huh_session *s, unsigned *w, unsigned *h) {
  if (!s) return NULL;
  if (w) *w = s->frame_w;
  if (h) *h = s->frame_h;
  return s->frame;
}

size_t huh_audio_drain(huh_session *s, int16_t *out, size_t frames) {
  if (!s || !out) return 0;
  size_t n = s->audio_len < frames ? s->audio_len : frames;
  memcpy(out, s->audio, n * 2 * sizeof(int16_t));
  memmove(s->audio, s->audio + n * 2,
          (s->audio_len - n) * 2 * sizeof(int16_t));
  s->audio_len -= n;
  return n;
}

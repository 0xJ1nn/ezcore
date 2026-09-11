/* ezCore runtime — loads a libretro core dylib and forwards the session API.
 * Desktop/Android path: dlopen at runtime after sha256 verification.
 * iOS path: cores are linked/bundled; ezcore_load resolves bundled symbols.
 */
#include "ezcore_runtime.h"

#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "libretro.h"

struct ezcore_session {
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
  /* Save states are core-optional: NULL-checked at every call. */
  size_t (*retro_serialize_size)(void);
  bool (*retro_serialize)(void *, size_t);
  bool (*retro_unserialize)(const void *, size_t);
  /* latest video frame (owned, XRGB8888) */
  uint32_t *frame;
  unsigned frame_w, frame_h;
  enum retro_pixel_format pixfmt;
  /* audio ring (stereo s16) */
  int16_t *audio;
  size_t audio_cap, audio_len;
  char name[128];
  char version[64];
  bool game_loaded;
  bool inited;
};

static ezcore_session *g_active = NULL;

/* ---- environment / callbacks (minimal v0 set; extended per TODO) ---- */

static char g_system_dir[1024] = {0};
static char g_save_dir[1024] = {0};

static void bridge_log(enum retro_log_level level, const char *fmt, ...) {
  (void)level;
  va_list args;
  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  va_end(args);
}

/* Host-owned content directories. Defaults are CWD-relative; the embedding
 * app should call ezcore_set_dirs() before loading cores that save or need
 * system files (BIOS lives in the app-managed vault, never here). */
void ezcore_set_dirs(const char *system_dir, const char *save_dir) {
  if (system_dir) snprintf(g_system_dir, sizeof(g_system_dir), "%s", system_dir);
  if (save_dir) snprintf(g_save_dir, sizeof(g_save_dir), "%s", save_dir);
}

static bool env_cb(unsigned cmd, void *data) {
  switch (cmd) {
    case RETRO_ENVIRONMENT_GET_CAN_DUPE:
      /* We keep the last decoded frame, so dupes are free. */
      if (data) *(bool *)data = true;
      return true;
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
      /* Required at init by several cores (mupen64plus strncpy's this
       * without a NULL check — returning false segfaults them). */
      if (!g_system_dir[0]) snprintf(g_system_dir, sizeof(g_system_dir), ".");
      if (data) *(const char **)data = g_system_dir;
      return true;
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
      if (!g_save_dir[0]) snprintf(g_save_dir, sizeof(g_save_dir), ".");
      if (data) *(const char **)data = g_save_dir;
      return true;
    case RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY:
      if (!g_system_dir[0]) snprintf(g_system_dir, sizeof(g_system_dir), ".");
      if (data) *(const char **)data = g_system_dir;
      return true;
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
      enum retro_pixel_format fmt = *(const enum retro_pixel_format *)data;
      if (fmt != RETRO_PIXEL_FORMAT_0RGB1555 &&
          fmt != RETRO_PIXEL_FORMAT_XRGB8888 &&
          fmt != RETRO_PIXEL_FORMAT_RGB565) {
        return false;
      }
      if (g_active) g_active->pixfmt = fmt;
      return true;
    }
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
      struct retro_log_callback *cb = data;
      if (cb) cb->log = bridge_log;
      return true;
    }
    case RETRO_ENVIRONMENT_SET_MESSAGE: {
      const struct retro_message *msg = data;
      if (msg && msg->msg) fprintf(stderr, "[core] %s\n", msg->msg);
      return true;
    }
    default:
      return false;
  }
}

static void video_cb(const void *data, unsigned width, unsigned height,
                     size_t pitch) {
  if (!g_active || !data || width == 0 || height == 0) return;
  ezcore_session *s = g_active;
  if (width != s->frame_w || height != s->frame_h) {
    free(s->frame);
    s->frame = malloc((size_t)width * height * 4);
    if (!s->frame) return;
    s->frame_w = width;
    s->frame_h = height;
  }
  if (s->pixfmt == RETRO_PIXEL_FORMAT_XRGB8888) {
    const uint8_t *src = data;
    for (unsigned y = 0; y < height; y++) {
      memcpy(s->frame + (size_t)y * width,
             src + (size_t)y * pitch, (size_t)width * 4);
    }
    return;
  }
  /* 0RGB1555 / RGB565 -> XRGB8888 expansion. */
  const uint8_t *src = data;
  for (unsigned y = 0; y < height; y++) {
    const uint16_t *row = (const uint16_t *)(src + (size_t)y * pitch);
    for (unsigned x = 0; x < width; x++) {
      uint16_t p = row[x];
      unsigned r, g, b;
      if (s->pixfmt == RETRO_PIXEL_FORMAT_RGB565) {
        r = (p >> 11) & 0x1F;
        g = (p >> 5) & 0x3F;
        b = p & 0x1F;
        r = (r << 3) | (r >> 2);
        g = (g << 2) | (g >> 4);
        b = (b << 3) | (b >> 2);
      } else {
        r = (p >> 10) & 0x1F;
        g = (p >> 5) & 0x1F;
        b = p & 0x1F;
        r = (r << 3) | (r >> 2);
        g = (g << 3) | (g >> 2);
        b = (b << 3) | (b >> 2);
      }
      s->frame[(size_t)y * width + x] =
          (uint32_t)((r << 16) | (g << 8) | b);
    }
  }
}

static void audio_sample_cb(int16_t left, int16_t right) {
  if (!g_active) return;
  ezcore_session *s = g_active;
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

int ezcore_abi_version(void) { return EZCORE_ABI_VERSION; }

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

ezcore_session *ezcore_load(const char *core_path, char *err, size_t err_len) {
  ezcore_session *s = calloc(1, sizeof(*s));
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
  /* Save-state entry points are core-optional (older cores may omit them). */
  s->retro_serialize_size = dlsym(s->handle, "retro_serialize_size");
  s->retro_serialize = dlsym(s->handle, "retro_serialize");
  s->retro_unserialize = dlsym(s->handle, "retro_unserialize");

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

  s->audio_cap = 8192;
  s->audio = malloc(s->audio_cap * 2 * sizeof(int16_t));
  s->pixfmt = RETRO_PIXEL_FORMAT_0RGB1555; /* libretro default */
  g_active = s;

  if (set_env) set_env(env_cb);

  /* QUIRK init-before-callbacks: Mesen's retro_set_video_refresh
   * dereferences its Console, which only exists after retro_init
   * (spec-violating, verified in Mesen/Libretro/libretro.cpp).
   * Every other core keeps the spec order. */
  bool early_init = info.library_name &&
                    strstr(info.library_name, "Mesen") != NULL;
  if (early_init) {
    s->retro_init();
    s->inited = true;
  }

  if (set_video) set_video(video_cb);
  if (set_audio) set_audio(audio_sample_cb);
  if (set_audio_batch) set_audio_batch(audio_batch_cb);
  if (set_poll) set_poll(input_poll_cb);
  if (set_state) set_state(input_state_cb);
  return s;
}

void ezcore_unload(ezcore_session *s) {
  if (!s) return;
  if (g_active == s) g_active = NULL;
  s->retro_deinit();
  dlclose(s->handle);
  free(s->frame);
  free(s->audio);
  free(s);
}

bool ezcore_init(ezcore_session *s) {
  if (!s) return false;
  g_active = s;
  if (!s->inited) {
    s->retro_init();
    s->inited = true;
  }
  return true;
}

bool ezcore_load_game(ezcore_session *s, const char *rom_path, const void *data,
                   size_t size) {
  if (!s) return false;
  struct retro_game_info info = {rom_path, data, size, NULL};
  bool ok = s->retro_load_game(&info);
  s->game_loaded = ok;
  return ok;
}

void ezcore_run_frame(ezcore_session *s) {
  if (!s) return;
  g_active = s;
  s->retro_run();
}

const char *ezcore_core_name(ezcore_session *s) { return s ? s->name : "?"; }
const char *ezcore_core_version(ezcore_session *s) { return s ? s->version : "?"; }

/* Requires a loaded game: several cores (e.g. mGBA) dereference active
 * content here and segfault when called pre-load. Frontends must only
 * query geometry after ezcore_load_game succeeds. */
void ezcore_system_geometry(ezcore_session *s, unsigned *w, unsigned *h,
                         double *fps) {
  if (!s) return;
  if (!s->game_loaded) {
    if (w) *w = 0;
    if (h) *h = 0;
    if (fps) *fps = 0;
    return;
  }
  struct retro_system_av_info av;
  memset(&av, 0, sizeof(av));
  s->retro_get_system_av_info(&av);
  if (w) *w = av.geometry.base_width;
  if (h) *h = av.geometry.base_height;
  if (fps) *fps = av.timing.fps;
}

void ezcore_cheat_reset(ezcore_session *s) {
  if (s) s->retro_cheat_reset();
}

bool ezcore_cheat_set(ezcore_session *s, unsigned index, bool enabled,
                   const char *code) {
  if (!s || !code) return false;
  s->retro_cheat_set(index, enabled, code);
  return true;
}

const uint32_t *ezcore_frame_pixels(ezcore_session *s, unsigned *w, unsigned *h) {
  if (!s) return NULL;
  if (w) *w = s->frame_w;
  if (h) *h = s->frame_h;
  return s->frame;
}

size_t ezcore_audio_drain(ezcore_session *s, int16_t *out, size_t frames) {
  if (!s || !out) return 0;
  size_t n = s->audio_len < frames ? s->audio_len : frames;
  memcpy(out, s->audio, n * 2 * sizeof(int16_t));
  memmove(s->audio, s->audio + n * 2,
          (s->audio_len - n) * 2 * sizeof(int16_t));
  s->audio_len -= n;
  return n;
}

/* Save states live in the runtime (local vault today, sync providers
 * tomorrow). All three require a loaded game and degrade to 0/false
 * when the core omits the entry points. */
size_t ezcore_serialize_size(ezcore_session *s) {
  if (!s || !s->game_loaded || !s->retro_serialize_size) return 0;
  return s->retro_serialize_size();
}

bool ezcore_serialize(ezcore_session *s, void *out, size_t size) {
  if (!s || !s->game_loaded || !s->retro_serialize || !out) return false;
  return s->retro_serialize(out, size);
}

bool ezcore_unserialize(ezcore_session *s, const void *data, size_t size) {
  if (!s || !s->game_loaded || !s->retro_unserialize || !data) return false;
  return s->retro_unserialize(data, size);
}

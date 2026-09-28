/* ezCore runtime — loads a libretro core dylib and forwards the session API.
 * Desktop/Android path: dynload seam at runtime after sha256 verification.
 * iOS path: cores are linked/bundled; ezcore_load resolves bundled symbols.
 */
#include "ezcore_runtime.h"

#include "dynload.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "libretro.h"

/* ---- Core options & capability storage (host-owned deep copies) ---- */

/* Core options API version reported to cores via GET_CORE_OPTIONS_VERSION.
 * 0x10000 = v1, 0x20000 = v2 (categories, intl). */
#define EZCORE_CORE_OPTIONS_VERSION 0x20000u

/* A deep-copied core option definition.  All char* fields are heap-owned
 * by the runtime; the values/labels arrays are NULL-terminated. */
struct ezcore_core_option {
  char *key;
  char *desc;
  char *value;          /* current value — a frontend-set selection    */
  char *default_value;  /* deep copy of the core's default_value       */
  char **values;        /* NULL-terminated array of deep-copied values */
  char **labels;        /* parallel array of labels (may hold NULL)    */
  unsigned num_values;  /* non-NULL entries in values/labels            */
};

/* A deep-copied retro_input_descriptor. */
struct ezcore_input_desc {
  unsigned port;
  unsigned device;
  unsigned index;
  unsigned id;
  char *description;
};

/* A deep-copied retro_controller_description. */
struct ezcore_controller_desc {
  char *desc;
  unsigned id;
};

/* One emulated input port with its supported device types. */
struct ezcore_controller_port {
  struct ezcore_controller_desc *types;  /* length == num_types           */
  unsigned num_types;
};

/* A deep-copied retro_memory_descriptor.  ptr is intentionally NOT
 * copied — it aliases core-owned memory valid for the session lifetime. */
struct ezcore_mem_desc {
  uint64_t flags;
  void *ptr;            /* core-owned — not freed by the runtime */
  size_t offset;
  size_t start;
  size_t select;
  size_t disconnect;
  size_t len;
  char *addrspace;      /* deep copy */
};

static char *ezcore_strdup(const char *s) {
  if (!s) return NULL;
  size_t len = strlen(s);
  char *copy = (char *)malloc(len + 1);
  if (copy) memcpy(copy, s, len + 1);
  return copy;
}

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
  void (*retro_reset)(void);
  /* Optional cheat entry points: NULL-checked at every call. */
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
  /* input state: per-port button bitmask (up to 4 ports) */
  uint32_t input_buttons[4];
  char name[128];
  char version[64];
  bool game_loaded;
  bool inited;
  /* --- Core options & capability surface (host-owned deep copies) --- */
  struct ezcore_core_option *core_options;
  unsigned num_core_options;
  struct ezcore_input_desc *input_descs;
  unsigned num_input_descs;
  struct ezcore_controller_port *controller_ports;
  unsigned num_controller_ports;
  struct ezcore_mem_desc *mem_descs;
  unsigned num_mem_descs;
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

/* --- Free deep-copied capability storage in a session --- */

static void ezcore_free_core_options(ezcore_session *s) {
  if (!s->core_options) return;
  for (unsigned i = 0; i < s->num_core_options; i++) {
    struct ezcore_core_option *co = &s->core_options[i];
    free(co->key);
    free(co->desc);
    free(co->value);
    free(co->default_value);
    if (co->values) {
      for (unsigned j = 0; j < co->num_values; j++) free(co->values[j]);
      free(co->values);
    }
    if (co->labels) {
      for (unsigned j = 0; j < co->num_values; j++) free(co->labels[j]);
      free(co->labels);
    }
  }
  free(s->core_options);
  s->core_options = NULL;
  s->num_core_options = 0;
}

static void ezcore_free_input_descs(ezcore_session *s) {
  if (!s->input_descs) return;
  for (unsigned i = 0; i < s->num_input_descs; i++)
    free(s->input_descs[i].description);
  free(s->input_descs);
  s->input_descs = NULL;
  s->num_input_descs = 0;
}

static void ezcore_free_controller_ports(ezcore_session *s) {
  if (!s->controller_ports) return;
  for (unsigned i = 0; i < s->num_controller_ports; i++) {
    struct ezcore_controller_port *p = &s->controller_ports[i];
    if (p->types) {
      for (unsigned j = 0; j < p->num_types; j++) free(p->types[j].desc);
      free(p->types);
    }
  }
  free(s->controller_ports);
  s->controller_ports = NULL;
  s->num_controller_ports = 0;
}

static void ezcore_free_mem_descs(ezcore_session *s) {
  if (!s->mem_descs) return;
  for (unsigned i = 0; i < s->num_mem_descs; i++)
    free(s->mem_descs[i].addrspace);
  free(s->mem_descs);
  s->mem_descs = NULL;
  s->num_mem_descs = 0;
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
    /* ---- P1b: core options & capability surface ---- */
    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION:
      /* Core asks the host which options API version it supports.
       * We report v2, enabling SET_CORE_OPTIONS_V2 / V2_INTL. */
      if (data) *(unsigned *)data = EZCORE_CORE_OPTIONS_VERSION;
      return true;
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2: {
      /* Deep-copy a v2 option set into the session.  The core retains
       * ownership of all strings; we duplicate them so they survive
       * beyond the env_cb call. */
      const struct retro_core_options_v2 *opts = data;
      if (!g_active) return false;
      ezcore_free_core_options(g_active);
      if (!opts || !opts->definitions) return true;
      /* definitions is terminated by a zeroed-out struct (key == NULL) */
      unsigned count = 0;
      while (count < 1024 && opts->definitions[count].key) count++;
      if (count == 0) return true;
      g_active->core_options =
          (struct ezcore_core_option *)calloc(count, sizeof(*g_active->core_options));
      if (!g_active->core_options) return false;
      g_active->num_core_options = count;
      for (unsigned i = 0; i < count; i++) {
        const struct retro_core_option_v2_definition *d = &opts->definitions[i];
        struct ezcore_core_option *co = &g_active->core_options[i];
        co->key = ezcore_strdup(d->key);
        co->desc = ezcore_strdup(d->desc);
        co->default_value = ezcore_strdup(d->default_value);
        co->value = ezcore_strdup(d->default_value); /* init current = default */
        /* values[] is terminated by { NULL, NULL } */
        unsigned nv = 0;
        while (nv < RETRO_NUM_CORE_OPTION_VALUES_MAX &&
               d->values[nv].value) nv++;
        co->num_values = nv;
        if (nv > 0) {
          co->values = (char **)calloc(nv + 1, sizeof(char *));
          co->labels = (char **)calloc(nv + 1, sizeof(char *));
          if (co->values && co->labels) {
            for (unsigned j = 0; j < nv; j++) {
              co->values[j] = ezcore_strdup(d->values[j].value);
              co->labels[j] = ezcore_strdup(d->values[j].label);
            }
          }
        }
      }
      return true;
    }
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: {
      /* v1 INTL variant.  We store the US (English) definitions using
       * the same internal representation as V2.  The translated `local`
       * set is intentionally not stored: the host option surface exposes
       * the canonical US strings so that option *keys* and *values*
       * (which must be language-independent) are queryable. */
      const struct retro_core_options_intl *opts_intl = data;
      if (!g_active) return false;
      ezcore_free_core_options(g_active);
      if (!opts_intl || !opts_intl->us) return true;
      /* us array is terminated by an entry with key == NULL */
      unsigned count = 0;
      while (count < 1024 && opts_intl->us[count].key) count++;
      if (count == 0) return true;
      g_active->core_options =
          (struct ezcore_core_option *)calloc(count, sizeof(*g_active->core_options));
      if (!g_active->core_options) return false;
      g_active->num_core_options = count;
      for (unsigned i = 0; i < count; i++) {
        const struct retro_core_option_definition *d = &opts_intl->us[i];
        struct ezcore_core_option *co = &g_active->core_options[i];
        co->key = ezcore_strdup(d->key);
        co->desc = ezcore_strdup(d->desc);
        co->default_value = ezcore_strdup(d->default_value);
        co->value = ezcore_strdup(d->default_value);
        unsigned nv = 0;
        while (nv < RETRO_NUM_CORE_OPTION_VALUES_MAX &&
               d->values[nv].value) nv++;
        co->num_values = nv;
        if (nv > 0) {
          co->values = (char **)calloc(nv + 1, sizeof(char *));
          co->labels = (char **)calloc(nv + 1, sizeof(char *));
          if (co->values && co->labels) {
            for (unsigned j = 0; j < nv; j++) {
              co->values[j] = ezcore_strdup(d->values[j].value);
              co->labels[j] = ezcore_strdup(d->values[j].label);
            }
          }
        }
      }
      return true;
    }
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS: {
      /* Array is terminated by a zeroed-out descriptor (description == NULL). */
      const struct retro_input_descriptor *descs = data;
      if (!g_active) return false;
      ezcore_free_input_descs(g_active);
      if (!descs) return true;
      unsigned count = 0;
      while (count < 1024 && descs[count].description) count++;
      if (count == 0) return true;
      g_active->input_descs =
          (struct ezcore_input_desc *)calloc(count, sizeof(*g_active->input_descs));
      if (!g_active->input_descs) return false;
      g_active->num_input_descs = count;
      for (unsigned i = 0; i < count; i++) {
        g_active->input_descs[i].port = descs[i].port;
        g_active->input_descs[i].device = descs[i].device;
        g_active->input_descs[i].index = descs[i].index;
        g_active->input_descs[i].id = descs[i].id;
        g_active->input_descs[i].description = ezcore_strdup(descs[i].description);
      }
      return true;
    }
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO: {
      /* Array is terminated by a zeroed-out entry. */
      const struct retro_controller_info *infos = data;
      if (!g_active) return false;
      ezcore_free_controller_ports(g_active);
      if (!infos) return true;
      unsigned count = 0;
      while (count < 1024 && (infos[count].types || infos[count].num_types))
        count++;
      if (count == 0) return true;
      g_active->controller_ports =
          (struct ezcore_controller_port *)calloc(count, sizeof(*g_active->controller_ports));
      if (!g_active->controller_ports) return false;
      g_active->num_controller_ports = count;
      for (unsigned i = 0; i < count; i++) {
        unsigned nt = infos[i].num_types;
        g_active->controller_ports[i].num_types = nt;
        if (nt > 0 && infos[i].types) {
          g_active->controller_ports[i].types =
              (struct ezcore_controller_desc *)calloc(nt, sizeof(struct ezcore_controller_desc));
          for (unsigned j = 0; j < nt; j++) {
            g_active->controller_ports[i].types[j].desc =
                ezcore_strdup(infos[i].types[j].desc);
            g_active->controller_ports[i].types[j].id = infos[i].types[j].id;
          }
        }
      }
      return true;
    }
    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS: {
      const struct retro_memory_map *map = data;
      if (!g_active) return false;
      ezcore_free_mem_descs(g_active);
      if (!map || !map->descriptors) return true;
      unsigned count = map->num_descriptors;
      if (count == 0) return true;
      g_active->mem_descs =
          (struct ezcore_mem_desc *)calloc(count, sizeof(*g_active->mem_descs));
      if (!g_active->mem_descs) return false;
      g_active->num_mem_descs = count;
      for (unsigned i = 0; i < count; i++) {
        const struct retro_memory_descriptor *md = &map->descriptors[i];
        g_active->mem_descs[i].flags = md->flags;
        /* ptr aliases core-owned memory; we store it but do NOT free it */
        g_active->mem_descs[i].ptr = md->ptr;
        g_active->mem_descs[i].offset = md->offset;
        g_active->mem_descs[i].start = md->start;
        g_active->mem_descs[i].select = md->select;
        g_active->mem_descs[i].disconnect = md->disconnect;
        g_active->mem_descs[i].len = md->len;
        g_active->mem_descs[i].addrspace = ezcore_strdup(md->addrspace);
      }
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

/* Reads from g_active->input_buttons[port] so the host can drive input. */
static int16_t input_state_cb(unsigned port, unsigned device,
                              unsigned index, unsigned id) {
  (void)index;
  if (!g_active || device != RETRO_DEVICE_JOYPAD || port >= 4) return 0;
  uint32_t mask = g_active->input_buttons[port];
  if (id < 16) return (int16_t)((mask >> id) & 1);
  /* RETRO_DEVICE_ID_JOYPAD_MASK: return full bitmask */
  if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t)mask;
  return 0;
}

/* ---- public API ---- */

int ezcore_abi_version(void) { return EZCORE_ABI_VERSION; }

#define LOAD_SYM(s, field, sym)                                  \
  do {                                                           \
    s->field = ez_dyn_sym(s->handle, sym);                       \
    if (!s->field) {                                             \
      snprintf(err, err_len, "core missing symbol: %s", sym);    \
      ez_dyn_close(s->handle);                                   \
      free(s);                                                   \
      return NULL;                                               \
    }                                                            \
  } while (0)

ezcore_session *ezcore_load(const char *core_path, char *err, size_t err_len) {
  ezcore_session *s = calloc(1, sizeof(*s));
  if (!s) return NULL;
  snprintf(s->core_path, sizeof(s->core_path), "%s", core_path);
  s->handle = ez_dyn_open(core_path, err, err_len);
  if (!s->handle) {
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
  LOAD_SYM(s, retro_reset, "retro_reset");
  /* Cheat entry points are core-optional; cores without cheat support still
   * need to load for video, audio, input, and save-state functionality. */
  s->retro_cheat_reset = ez_dyn_sym(s->handle, "retro_cheat_reset");
  s->retro_cheat_set = ez_dyn_sym(s->handle, "retro_cheat_set");
  /* Save-state entry points are core-optional (older cores may omit them). */
  s->retro_serialize_size = ez_dyn_sym(s->handle, "retro_serialize_size");
  s->retro_serialize = ez_dyn_sym(s->handle, "retro_serialize");
  s->retro_unserialize = ez_dyn_sym(s->handle, "retro_unserialize");

  if (s->retro_api_version() != 1) {
    snprintf(err, err_len, "unsupported libretro API version");
    ez_dyn_close(s->handle);
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
      ez_dyn_sym(s->handle, "retro_set_environment");
  void (*set_video)(retro_video_refresh_t) =
      ez_dyn_sym(s->handle, "retro_set_video_refresh");
  void (*set_audio)(retro_audio_sample_t) =
      ez_dyn_sym(s->handle, "retro_set_audio_sample");
  void (*set_audio_batch)(retro_audio_sample_batch_t) =
      ez_dyn_sym(s->handle, "retro_set_audio_sample_batch");
  void (*set_poll)(retro_input_poll_t) =
      ez_dyn_sym(s->handle, "retro_set_input_poll");
  void (*set_state)(retro_input_state_t) =
      ez_dyn_sym(s->handle, "retro_set_input_state");

  /* audio_cap is in FRAMES (stereo frame = 2 int16_t = 4 bytes).
   * Buffer bytes = audio_cap * 2 * sizeof(int16_t) = audio_cap * 4. */
  s->audio_cap = 8192;
  s->audio = malloc(s->audio_cap * 2 * sizeof(int16_t));
  if (!s->audio) {
    snprintf(err, err_len, "audio buffer alloc failed");
    ez_dyn_close(s->handle);
    free(s);
    return NULL;
  }
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
  if (s->inited) {
    s->retro_deinit();
    s->inited = false;
  }
  ezcore_free_core_options(s);
  ezcore_free_input_descs(s);
  ezcore_free_controller_ports(s);
  ezcore_free_mem_descs(s);
  ez_dyn_close(s->handle);
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

/* Reset the currently loaded game. Safe to call only after load_game. */
void ezcore_reset(ezcore_session *s) {
  if (!s || !s->game_loaded || !s->retro_reset) return;
  s->retro_reset();
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

/* Sample rate from AV timing (valid after load_game). Returns 0 if unavailable. */
double ezcore_sample_rate(ezcore_session *s) {
  if (!s || !s->game_loaded) return 0.0;
  struct retro_system_av_info av;
  memset(&av, 0, sizeof(av));
  s->retro_get_system_av_info(&av);
  return av.timing.sample_rate;
}

void ezcore_cheat_reset(ezcore_session *s) {
  if (s && s->retro_cheat_reset) s->retro_cheat_reset();
}

bool ezcore_cheat_set(ezcore_session *s, unsigned index, bool enabled,
                   const char *code) {
  if (!s || !code || !s->retro_cheat_set) return false;
  /* The libretro hook is void; true means dispatch was attempted, not that
   * the core validated the code. */
  s->retro_cheat_set(index, enabled, code);
  return true;
}

void ezcore_set_button(ezcore_session *s, unsigned port, unsigned button_id,
                    bool pressed) {
  if (!s || port >= 4 || button_id >= 16) return;
  if (pressed)
    s->input_buttons[port] |= (1u << button_id);
  else
    s->input_buttons[port] &= ~(1u << button_id);
}

/* Clear all buttons for a port. */
void ezcore_clear_buttons(ezcore_session *s, unsigned port) {
  if (!s || port >= 4) return;
  s->input_buttons[port] = 0;
}

/* --- Safe frame/audio access (copies) --- */

/* Copies the latest frame's pixels into `out` as RGBA bytes.
 * `out` must be at least width*height*4 bytes.
 * Returns the number of bytes copied (width*height*4), or 0 if no frame yet. */
size_t ezcore_frame_pixels_copy(ezcore_session *s, uint8_t *out,
                             size_t out_size) {
  if (!s || !out) return 0;
  size_t need = (size_t)s->frame_w * s->frame_h * 4;
  if (need == 0 || need > out_size) return 0;
  for (size_t i = 0; i < need / 4; ++i) {
    uint32_t pixel = s->frame[i];
    out[i * 4] = (uint8_t)(pixel >> 16);
    out[i * 4 + 1] = (uint8_t)(pixel >> 8);
    out[i * 4 + 2] = (uint8_t)pixel;
    out[i * 4 + 3] = 255;
  }
  return need;
}

/* Returns width/height of latest frame. 0 when no frame yet. */
void ezcore_frame_size(ezcore_session *s, unsigned *w, unsigned *h) {
  if (!s) { if (w) *w = 0; if (h) *h = 0; return; }
  if (w) *w = s->frame_w;
  if (h) *h = s->frame_h;
}

/* Returns a const pointer to the latest frame (XRGB8888). Use for fast access
 * when the frame is only read. Do NOT free. */
const uint32_t *ezcore_frame_pixels(ezcore_session *s, unsigned *w, unsigned *h) {
  if (!s) return NULL;
  if (w) *w = s->frame_w;
  if (h) *h = s->frame_h;
  return s->frame;
}

/* Audio: frames appended by the audio batch callback; drained by player. */
size_t ezcore_audio_drain(ezcore_session *s, int16_t *out, size_t frames) {
  if (!s || !out) return 0;
  size_t n = s->audio_len < frames ? s->audio_len : frames;
  memcpy(out, s->audio, n * 2 * sizeof(int16_t));
  memmove(s->audio, s->audio + n * 2,
          (s->audio_len - n) * 2 * sizeof(int16_t));
  s->audio_len -= n;
  return n;
}

/* Drains up to `max_frames` stereo s16 samples into `out`.
 * `out` must be at least max_frames * 2 * sizeof(int16_t) bytes.
 * Returns number of frames actually drained. */
size_t ezcore_audio_drain_copy(ezcore_session *s, int16_t *out,
                            size_t max_frames) {
  return ezcore_audio_drain(s, out, max_frames);
}

/* Current number of audio frames queued in the ring buffer. */
size_t ezcore_audio_pending(ezcore_session *s) {
  return s ? s->audio_len : 0;
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

/* ---- Core Options & Capability Surface ---- */

/* Returns the version that the host reported to the core via
 * RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION.  Stored by the core in its
 * library_version string at load time; callers verify it there. */

unsigned ezcore_get_core_option_count(ezcore_session *s) {
  return s ? s->num_core_options : 0;
}

bool ezcore_get_core_option(ezcore_session *s, unsigned index,
                            const char **key, const char **default_value,
                            const char **value) {
  if (!s || index >= s->num_core_options) return false;
  const struct ezcore_core_option *co = &s->core_options[index];
  if (key) *key = co->key;
  if (default_value) *default_value = co->default_value;
  if (value) *value = co->value;
  return true;
}

bool ezcore_set_core_option(ezcore_session *s, const char *key,
                            const char *value) {
  if (!s || !key) return false;
  for (unsigned i = 0; i < s->num_core_options; i++) {
    struct ezcore_core_option *co = &s->core_options[i];
    if (co->key && strcmp(co->key, key) == 0) {
      free(co->value);
      co->value = ezcore_strdup(value);
      return true;
    }
  }
  return false;
}

unsigned ezcore_get_input_descriptor_count(ezcore_session *s) {
  return s ? s->num_input_descs : 0;
}

bool ezcore_get_input_descriptor(ezcore_session *s, unsigned index,
                                 unsigned *port, unsigned *device,
                                 unsigned *desc_index, unsigned *id,
                                 const char **description) {
  if (!s || index >= s->num_input_descs) return false;
  const struct ezcore_input_desc *d = &s->input_descs[index];
  if (port) *port = d->port;
  if (device) *device = d->device;
  if (desc_index) *desc_index = d->index;
  if (id) *id = d->id;
  if (description) *description = d->description;
  return true;
}

unsigned ezcore_get_controller_port_count(ezcore_session *s) {
  return s ? s->num_controller_ports : 0;
}

unsigned ezcore_get_memory_descriptor_count(ezcore_session *s) {
  return s ? s->num_mem_descs : 0;
}

bool ezcore_get_memory_descriptor(ezcore_session *s, unsigned index,
                                  uint64_t *flags, void **ptr,
                                  size_t *offset, size_t *start,
                                  size_t *select, size_t *disconnect,
                                  size_t *len, const char **addrspace) {
  if (!s || index >= s->num_mem_descs) return false;
  const struct ezcore_mem_desc *md = &s->mem_descs[index];
  if (flags) *flags = md->flags;
  if (ptr) *ptr = md->ptr;
  if (offset) *offset = md->offset;
  if (start) *start = md->start;
  if (select) *select = md->select;
  if (disconnect) *disconnect = md->disconnect;
  if (len) *len = md->len;
  if (addrspace) *addrspace = md->addrspace;
  return true;
}

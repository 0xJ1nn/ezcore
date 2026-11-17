/* ezcore_engine_libretro.c — the default backend: the existing libretro
 * runtime behind the generic ezh_engine_vtable. Behaviour is the unchanged
 * ezcore_core_host behaviour; this file only re-points each op at the table.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ezcore_engine.h"
#include "ezcore_runtime.h"

typedef struct {
  ezcore_session *session;
} libretro_engine;

static ezh_engine *lr_create(void) {
  return (ezh_engine *)calloc(1, sizeof(libretro_engine));
}

static void lr_destroy(ezh_engine *e) {
  libretro_engine *lr = (libretro_engine *)e;
  if (!lr) return;
  if (lr->session) ezcore_unload(lr->session);
  free(lr);
}

static int lr_open(ezh_engine *e, const char *core, const char *sys,
                   const char *save, char *err, size_t errlen) {
  libretro_engine *lr = (libretro_engine *)e;
  ezcore_set_dirs(sys, save);
  lr->session = ezcore_load(core, err, errlen);
  if (!lr->session) {
    if (errlen && !err[0]) snprintf(err, errlen, "core failed to load");
    return 0;
  }
  if (!ezcore_init(lr->session)) {
    ezcore_unload(lr->session);
    lr->session = NULL;
    snprintf(err, errlen, "core initialization failed");
    return 0;
  }
  return 1;
}

static int lr_load_content(ezh_engine *e, const char *content, char *err,
                           size_t errlen) {
  libretro_engine *lr = (libretro_engine *)e;
  FILE *f = fopen(content, "rb");
  uint8_t *data = NULL;
  long size = 0;
  if (f) {
    fseek(f, 0, SEEK_END);
    size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size > 0) {
      data = malloc((size_t)size);
      if (data && fread(data, 1, (size_t)size, f) != (size_t)size) size = 0;
    }
    fclose(f);
  }
  int loaded = f && ezcore_load_game(lr->session, content, data,
                                     (size_t)(size > 0 ? size : 0));
  free(data);
  if (!f) {
    snprintf(err, errlen, "content file could not be read");
    return 0;
  }
  if (!loaded) {
    snprintf(err, errlen, "core rejected the content");
    return 0;
  }
  return 1;
}

static const char *lr_core_name(const ezh_engine *e) {
  const libretro_engine *lr = (const libretro_engine *)e;
  return ezcore_core_name(lr->session);
}
static void lr_geometry(const ezh_engine *e, unsigned *w, unsigned *h,
                        double *fps) {
  const libretro_engine *lr = (const libretro_engine *)e;
  ezcore_system_geometry(lr->session, w, h, fps);
}
static double lr_sample_rate(const ezh_engine *e) {
  const libretro_engine *lr = (const libretro_engine *)e;
  return ezcore_sample_rate(lr->session);
}
static void lr_run_frame(ezh_engine *e, unsigned count) {
  libretro_engine *lr = (libretro_engine *)e;
  for (unsigned i = 0; i < count; i++) ezcore_run_frame(lr->session);
}
static void lr_frame_size(const ezh_engine *e, unsigned *w, unsigned *h) {
  const libretro_engine *lr = (const libretro_engine *)e;
  ezcore_frame_size(lr->session, w, h);
}
static void lr_pixels_copy(const ezh_engine *e, void *dst, size_t n) {
  const libretro_engine *lr = (const libretro_engine *)e;
  ezcore_frame_pixels_copy(lr->session, dst, n);
}
static size_t lr_audio_drain(ezh_engine *e, int16_t *dst, size_t frames) {
  libretro_engine *lr = (libretro_engine *)e;
  return ezcore_audio_drain_copy(lr->session, dst, frames);
}
static void lr_pause(ezh_engine *e, int paused) {
  (void)e; (void)paused; /* the host gates FRAME while paused */
}
static void lr_reset(ezh_engine *e) {
  ezcore_reset(((libretro_engine *)e)->session);
}
static void lr_clear_buttons(ezh_engine *e, unsigned port) {
  ezcore_clear_buttons(((libretro_engine *)e)->session, port);
}
static void lr_set_button(ezh_engine *e, unsigned port, unsigned id,
                          int pressed) {
  ezcore_set_button(((libretro_engine *)e)->session, port, id, pressed != 0);
}
static void lr_set_analog(ezh_engine *e, unsigned port, unsigned stick,
                          unsigned axis, int value) {
  ezcore_set_analog(((libretro_engine *)e)->session, port, stick, axis,
                    (int16_t)value);
}
static void lr_mouse_move(ezh_engine *e, int dx, int dy) {
  ezcore_mouse_move(((libretro_engine *)e)->session, dx, dy);
}
static void lr_mouse_button(ezh_engine *e, unsigned id, int pressed) {
  ezcore_set_mouse_button(((libretro_engine *)e)->session, id, pressed != 0);
}
static void lr_key(ezh_engine *e, unsigned code, int pressed, unsigned ch,
                   unsigned mods) {
  ezcore_set_key(((libretro_engine *)e)->session, code, pressed != 0, ch,
                 (uint16_t)mods);
}
static void lr_pointer(ezh_engine *e, int x, int y, int pressed) {
  ezcore_set_pointer(((libretro_engine *)e)->session, (int16_t)x, (int16_t)y,
                     pressed != 0);
}
static size_t lr_serialize_size(const ezh_engine *e) {
  return ezcore_serialize_size(((const libretro_engine *)e)->session);
}
static int lr_serialize(ezh_engine *e, void *dst, size_t n) {
  return ezcore_serialize(((libretro_engine *)e)->session, dst, n) ? 1 : 0;
}
static int lr_unserialize(ezh_engine *e, const void *src, size_t n) {
  return ezcore_unserialize(((libretro_engine *)e)->session, src, n) ? 1 : 0;
}
static void lr_cheat_reset(ezh_engine *e) {
  ezcore_cheat_reset(((libretro_engine *)e)->session);
}
static int lr_cheat_set(ezh_engine *e, unsigned index, int enabled,
                        const char *code) {
  return ezcore_cheat_set(((libretro_engine *)e)->session, index,
                          enabled != 0, code) ? 1 : 0;
}
static unsigned lr_option_count(const ezh_engine *e) {
  return ezcore_get_core_option_count(((const libretro_engine *)e)->session);
}
static void lr_option_get(const ezh_engine *e, unsigned i, const char **key,
                          const char **def, const char **value) {
  ezcore_get_core_option(((const libretro_engine *)e)->session, i, key, def,
                         value);
}
static int lr_option_set(ezh_engine *e, const char *key, const char *value) {
  return ezcore_set_core_option(((libretro_engine *)e)->session, key, value)
             ? 1 : 0;
}

const ezh_engine_vtable ezh_engine_libretro = {
  "libretro",
  lr_create, lr_destroy, lr_open, lr_load_content, lr_core_name,
  lr_geometry, lr_sample_rate, lr_run_frame, lr_frame_size, lr_pixels_copy,
  lr_audio_drain, lr_pause, lr_reset, lr_clear_buttons, lr_set_button,
  lr_set_analog, lr_mouse_move, lr_mouse_button, lr_key, lr_pointer,
  lr_serialize_size, lr_serialize, lr_unserialize, lr_cheat_reset,
  lr_cheat_set, lr_option_count, lr_option_get, lr_option_set,
};

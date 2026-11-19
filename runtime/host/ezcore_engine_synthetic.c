/* ezcore_engine_synthetic.c — an ORIGINAL, CC0, non-libretro engine that
 * satisfies the generic host protocol. This is the concrete Tier-2 proof:
 * a standalone engine (no libretro, no core, no ROM, no BIOS) plugged behind
 * the same wire ops as the libretro backend, selected by --engine=synthetic.
 *
 * It "opens" a synthetic content id, renders a deterministic checker pattern,
 * forwards input into that pattern, and round-trips an opaque save state.
 * An optional EZCORE_CRASH_AFTER=N makes it fault on frame N so crash
 * containment can be proven against a real signal (mirrors crash_libretro).
 */
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ezcore_engine.h"

#define SYN_W 256
#define SYN_H 240
#define SYN_MAGIC 0x53594E54u /* "SYNT" */

typedef struct {
  uint32_t magic;
  uint32_t frame_no;
  uint8_t buttons[4][16];
  int16_t analog[4][2][2];
  int32_t mouse_x, mouse_y;
  uint8_t mouse_buttons[8];
  uint32_t key_last;
  int16_t pointer_x, pointer_y;
  uint32_t checksum;
} synth_state;

typedef struct {
  synth_state st;
  int pending_pcm;
  unsigned crash_after;
} synthetic_engine;

static ezh_engine *syn_create(void) {
  synthetic_engine *e = (synthetic_engine *)calloc(1, sizeof(synthetic_engine));
  if (!e) return NULL;
  e->st.magic = SYN_MAGIC;
  const char *env = getenv("EZCORE_CRASH_AFTER");
  if (env && *env) {
    char *end = NULL;
    long v = strtol(env, &end, 10);
    if (end && *end == '\0' && v > 0) e->crash_after = (unsigned)v;
  }
  return (ezh_engine *)e;
}

static void syn_destroy(ezh_engine *e) { free(e); }

static int syn_open(ezh_engine *e, const char *core, const char *sys,
                    const char *save, char *err, size_t errlen) {
  synthetic_engine *s = (synthetic_engine *)e;
  (void)sys; (void)save;
  if (!core || !*core) {
    snprintf(err, errlen, "synthetic engine needs a content id");
    return 0;
  }
  s->st.frame_no = 0;
  return 1;
}

static int syn_load_content(ezh_engine *e, const char *content, char *err,
                            size_t errlen) {
  (void)e; (void)content; (void)err; (void)errlen;
  return 1; /* the content id is data, not a file: no ROM required */
}

static const char *syn_core_name(const ezh_engine *e) {
  (void)e;
  return "Synthetic Tier-2 Engine";
}
static void syn_geometry(const ezh_engine *e, unsigned *w, unsigned *h,
                         double *fps) {
  (void)e;
  *w = SYN_W; *h = SYN_H; *fps = 60.0;
}
static double syn_sample_rate(const ezh_engine *e) {
  (void)e;
  return 48000.0;
}
static void syn_run_frame(ezh_engine *e, unsigned count) {
  synthetic_engine *s = (synthetic_engine *)e;
  for (unsigned i = 0; i < count; i++) {
    s->st.frame_no++;
    if (s->crash_after && s->st.frame_no == s->crash_after) raise(SIGSEGV);
  }
  s->pending_pcm = 1;
}
static void syn_frame_size(const ezh_engine *e, unsigned *w, unsigned *h) {
  (void)e;
  *w = SYN_W; *h = SYN_H;
}
static void syn_pixels_copy(const ezh_engine *e, void *dst, size_t n) {
  const synthetic_engine *s = (const synthetic_engine *)e;
  uint8_t *p = (uint8_t *)dst;
  size_t limit = n < (size_t)SYN_W * SYN_H * 4 ? n : (size_t)SYN_W * SYN_H * 4;
  int b0 = s->st.buttons[0][0] != 0;
  int b1 = s->st.buttons[0][1] != 0;
  for (size_t i = 0; i < limit; i += 4) {
    size_t px = (i / 4) % SYN_W, py = (i / 4) / SYN_W;
    uint8_t shade = (uint8_t)(((px / 16) + (py / 16)) * 16);
    if (b0) shade = (uint8_t)~shade;
    if (b1) shade = (uint8_t)(255 - shade);
    p[i] = shade; p[i + 1] = shade; p[i + 2] = shade; p[i + 3] = 255;
  }
}
static size_t syn_audio_drain(ezh_engine *e, int16_t *dst, size_t frames) {
  synthetic_engine *s = (synthetic_engine *)e;
  if (!s->pending_pcm) return 0;
  s->pending_pcm = 0;
  int16_t tone = s->st.buttons[0][0] ? 8000 : 4000;
  for (size_t i = 0; i < frames * 2; i++) dst[i] = tone;
  return frames;
}
static void syn_pause(ezh_engine *e, int paused) {
  (void)e; (void)paused; /* the host gates FRAME while paused */
}
static void syn_reset(ezh_engine *e) {
  synthetic_engine *s = (synthetic_engine *)e;
  memset(&s->st.buttons, 0, sizeof(s->st.buttons));
  memset(&s->st.analog, 0, sizeof(s->st.analog));
  s->st.frame_no = 0;
  s->pending_pcm = 0;
}
static void syn_clear_buttons(ezh_engine *e, unsigned port) {
  synthetic_engine *s = (synthetic_engine *)e;
  if (port < 4) memset(s->st.buttons[port], 0, sizeof(s->st.buttons[port]));
}
static void syn_set_button(ezh_engine *e, unsigned port, unsigned id,
                           int pressed) {
  synthetic_engine *s = (synthetic_engine *)e;
  if (port < 4 && id < 16) s->st.buttons[port][id] = pressed ? 1 : 0;
}
static void syn_set_analog(ezh_engine *e, unsigned port, unsigned stick,
                           unsigned axis, int value) {
  synthetic_engine *s = (synthetic_engine *)e;
  if (port < 4 && stick < 2 && axis < 2) s->st.analog[port][stick][axis] = (int16_t)value;
}
static void syn_mouse_move(ezh_engine *e, int dx, int dy) {
  synthetic_engine *s = (synthetic_engine *)e;
  s->st.mouse_x += dx; s->st.mouse_y += dy;
}
static void syn_mouse_button(ezh_engine *e, unsigned id, int pressed) {
  synthetic_engine *s = (synthetic_engine *)e;
  if (id < 8) s->st.mouse_buttons[id] = pressed ? 1 : 0;
}
static void syn_key(ezh_engine *e, unsigned code, int pressed, unsigned ch,
                    unsigned mods) {
  synthetic_engine *s = (synthetic_engine *)e;
  (void)ch; (void)mods;
  s->st.key_last = pressed ? code : 0;
}
static void syn_pointer(ezh_engine *e, int x, int y, int pressed) {
  synthetic_engine *s = (synthetic_engine *)e;
  (void)pressed;
  s->st.pointer_x = (int16_t)x; s->st.pointer_y = (int16_t)y;
}
static size_t syn_serialize_size(const ezh_engine *e) {
  (void)e;
  return sizeof(synth_state);
}
static uint32_t state_checksum(const synth_state *st) {
  const uint8_t *p = (const uint8_t *)st;
  uint32_t h = 2166136261u;
  for (size_t i = 0; i < offsetof(synth_state, checksum); i++) {
    h ^= p[i]; h *= 16777619u;
  }
  return h;
}
static int syn_serialize(ezh_engine *e, void *dst, size_t n) {
  synthetic_engine *s = (synthetic_engine *)e;
  if (n != sizeof(synth_state)) return 0;
  memcpy(dst, &s->st, sizeof(synth_state));
  ((synth_state *)dst)->checksum = state_checksum(&s->st);
  return 1;
}
static int syn_unserialize(ezh_engine *e, const void *src, size_t n) {
  synthetic_engine *s = (synthetic_engine *)e;
  if (n != sizeof(synth_state)) return 0;
  synth_state in;
  memcpy(&in, src, sizeof(in));
  if (in.magic != SYN_MAGIC || in.checksum != state_checksum(&in)) return 0;
  s->st = in;
  s->pending_pcm = 0;
  return 1;
}
static void syn_cheat_reset(ezh_engine *e) { (void)e; }
static int syn_cheat_set(ezh_engine *e, unsigned index, int enabled,
                         const char *code) {
  (void)e; (void)index; (void)enabled; (void)code;
  return 1;
}
static unsigned syn_option_count(const ezh_engine *e) {
  (void)e;
  return 1;
}
static void syn_option_get(const ezh_engine *e, unsigned i, const char **key,
                           const char **def, const char **value) {
  (void)e;
  if (i == 0) {
    *key = "pattern"; *def = "checker"; *value = "checker";
  } else {
    *key = *def = *value = "";
  }
}
static int syn_option_set(ezh_engine *e, const char *key, const char *value) {
  (void)e; (void)value;
  return key && strcmp(key, "pattern") == 0;
}

const ezh_engine_vtable ezh_engine_synthetic = {
  "synthetic",
  syn_create, syn_destroy, syn_open, syn_load_content, syn_core_name,
  syn_geometry, syn_sample_rate, syn_run_frame, syn_frame_size, syn_pixels_copy,
  syn_audio_drain, syn_pause, syn_reset, syn_clear_buttons, syn_set_button,
  syn_set_analog, syn_mouse_move, syn_mouse_button, syn_key, syn_pointer,
  syn_serialize_size, syn_serialize, syn_unserialize, syn_cheat_reset,
  syn_cheat_set, syn_option_count, syn_option_get, syn_option_set,
};

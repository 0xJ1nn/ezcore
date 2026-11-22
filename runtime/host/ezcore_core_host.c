// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* ezcore_core_host — runs ONE engine session in its own process
 * (P6 crash containment; Tier 2 engine hosting).
 *
 * The app starts this program, writes requests to its stdin and reads
 * responses from its stdout, per ezcore_core_host_protocol.h. This host owns
 * the wire protocol: framing, decoding, validation and encoding live here and
 * NEVER change when a new engine is added. What an engine does lives behind
 * ezh_engine_vtable (ezcore_engine.h): libretro is the default backend;
 * a non-libretro backend is selected with --engine=NAME. Adding a backend
 * changes no op and no byte on the wire.
 *
 * Two details carry the design:
 *  - The protocol owns the original stdout. Fd 1 is then pointed at stderr,
 *    because cores print freely (printf, puts) and one stray line on the
 *    protocol stream would desynchronise every message after it.
 *  - EOF on stdin means the app is gone: destroy and exit 0, so a host never
 *    outlives the app that started it.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#define dup _dup
#define dup2 _dup2
#define fileno _fileno
#else
#include <unistd.h>
#endif

#include "ezcore_core_host_protocol.h"
#include "ezcore_engine.h"

static FILE *g_in;
static FILE *g_out;
static ezh_engine *g_engine;
static const ezh_engine_vtable *E;
static int g_paused;

/* ---- reading a request ---- */

typedef struct {
  const uint8_t *p;
  size_t left;
  int bad; /* set when a read runs past the end; the request is then refused */
} reader_t;

static uint8_t rd_u8(reader_t *r) {
  if (r->left < 1) { r->bad = 1; return 0; }
  r->left--;
  return *r->p++;
}

static uint32_t rd_u32(reader_t *r) {
  if (r->left < 4) { r->bad = 1; r->left = 0; return 0; }
  uint32_t v = (uint32_t)r->p[0] | ((uint32_t)r->p[1] << 8) |
               ((uint32_t)r->p[2] << 16) | ((uint32_t)r->p[3] << 24);
  r->p += 4;
  r->left -= 4;
  return v;
}

/* Returns a malloc'd NUL-terminated copy (caller frees), or NULL when bad. */
static char *rd_str(reader_t *r) {
  uint32_t n = rd_u32(r);
  if (r->bad || n > r->left) { r->bad = 1; return NULL; }
  char *s = malloc((size_t)n + 1);
  if (!s) { r->bad = 1; return NULL; }
  memcpy(s, r->p, n);
  s[n] = '\0';
  r->p += n;
  r->left -= n;
  return s;
}

static const uint8_t *rd_blob(reader_t *r, uint32_t *len) {
  uint32_t n = rd_u32(r);
  if (r->bad || n > r->left) { r->bad = 1; return NULL; }
  const uint8_t *p = r->p;
  r->p += n;
  r->left -= n;
  *len = n;
  return p;
}

/* ---- building a response ---- */

typedef struct {
  uint8_t *buf;
  size_t len, cap;
} writer_t;

static int wr_reserve(writer_t *w, size_t more) {
  if (w->len + more <= w->cap) return 1;
  size_t cap = w->cap ? w->cap : 256;
  while (cap < w->len + more) cap *= 2;
  uint8_t *b = realloc(w->buf, cap);
  if (!b) return 0;
  w->buf = b;
  w->cap = cap;
  return 1;
}

static void wr_bytes(writer_t *w, const void *p, size_t n) {
  if (wr_reserve(w, n)) { memcpy(w->buf + w->len, p, n); w->len += n; }
}
static void wr_u8(writer_t *w, uint8_t v) { wr_bytes(w, &v, 1); }
static void wr_u32(writer_t *w, uint32_t v) {
  uint8_t b[4] = {(uint8_t)v, (uint8_t)(v >> 8), (uint8_t)(v >> 16),
                  (uint8_t)(v >> 24)};
  wr_bytes(w, b, 4);
}
static void wr_f64(writer_t *w, double v) {
  uint64_t u;
  memcpy(&u, &v, 8);
  for (int i = 0; i < 8; i++) wr_u8(w, (uint8_t)(u >> (8 * i)));
}
static void wr_str(writer_t *w, const char *s) {
  uint32_t n = s ? (uint32_t)strlen(s) : 0;
  wr_u32(w, n);
  if (n) wr_bytes(w, s, n);
}

static int send_body(const uint8_t *body, size_t n) {
  uint8_t hdr[4] = {(uint8_t)n, (uint8_t)(n >> 8), (uint8_t)(n >> 16),
                    (uint8_t)(n >> 24)};
  if (fwrite(hdr, 1, 4, g_out) != 4) return 0;
  if (n && fwrite(body, 1, n, g_out) != n) return 0;
  return fflush(g_out) == 0;
}

static int send_error(const char *msg) {
  writer_t w = {0};
  wr_u8(&w, EZH_ERROR);
  wr_bytes(&w, msg, strlen(msg));
  int ok = send_body(w.buf, w.len);
  free(w.buf);
  return ok;
}

/* ---- ops ---- */

static void release_all_buttons(void) {
  for (unsigned port = 0; port < 4; port++) E->clear_buttons(g_engine, port);
}

static int op_open(reader_t *r) {
  if (g_engine) return send_error("a session is already open");
  char *core = rd_str(r), *content = rd_str(r), *sys = rd_str(r),
       *save = rd_str(r);
  uint32_t n_opts = rd_u32(r);
  char **keys = NULL, **vals = NULL;
  if (!r->bad && n_opts <= 4096) {
    keys = calloc(n_opts ? n_opts : 1, sizeof(char *));
    vals = calloc(n_opts ? n_opts : 1, sizeof(char *));
    for (uint32_t i = 0; i < n_opts && !r->bad; i++) {
      keys[i] = rd_str(r);
      vals[i] = rd_str(r);
    }
  } else {
    r->bad = 1;
  }
  int ok = 0;
  writer_t w = {0};
  char err[1024] = {0};
  if (r->bad) {
    send_error("malformed OPEN request");
    goto done;
  }
  g_engine = E->create();
  if (!g_engine) {
    send_error("engine backend could not be created");
    goto done;
  }
  if (!E->open(g_engine, core, sys, save, err, sizeof(err))) {
    send_error(err[0] ? err : "engine failed to open");
    goto fail_destroy;
  }
  /* Options go in between open and load_content, the same point the
   * in-process path uses: many cores read them only inside retro_load_game. */
  wr_u8(&w, EZH_OK);
  wr_str(&w, E->core_name(g_engine));
  uint32_t n_rejected = 0;
  writer_t rej = {0};
  for (uint32_t i = 0; i < n_opts; i++) {
    if (!E->option_set(g_engine, keys[i], vals[i])) {
      wr_str(&rej, keys[i]);
      n_rejected++;
    }
  }
  if (!E->load_content(g_engine, content, err, sizeof(err))) {
    free(rej.buf);
    send_error(err[0] ? err : "engine rejected the content");
    goto fail_destroy;
  }
  unsigned gw = 0, gh = 0;
  double fps = 0;
  E->geometry(g_engine, &gw, &gh, &fps);
  wr_u32(&w, gw);
  wr_u32(&w, gh);
  wr_f64(&w, fps);
  wr_f64(&w, E->sample_rate(g_engine));
  wr_u32(&w, n_rejected);
  wr_bytes(&w, rej.buf, rej.len);
  free(rej.buf);
  /* Whether this core can serialize at all. Some cannot — an LCD-handheld
   * core returns 0 from retro_serialize_size — and the app must know before
   * it offers a snapshot, not learn it from a failed SAVE. */
  wr_u8(&w, E->serialize_size(g_engine) > 0 ? 1 : 0);
  ok = send_body(w.buf, w.len);
  goto done;
fail_destroy:
  E->destroy(g_engine);
  g_engine = NULL;
  ok = 1;
done:
  free(w.buf);
  for (uint32_t i = 0; keys && i < n_opts; i++) { free(keys[i]); free(vals[i]); }
  free(keys); free(vals);
  free(core); free(content); free(sys); free(save);
  /* A failed send means the app is unreachable; the next read sees EOF
   * and ends the loop, so keep going either way. */
  (void)ok;
  return 1;
}

static int op_frame(reader_t *r) {
  uint32_t count = rd_u32(r);
  if (r->bad || count < 1 || count > 8) return send_error("frame count must be 1..8");
  writer_t w = {0};
  wr_u8(&w, EZH_OK);
  if (g_paused) {
    wr_u8(&w, 0);
    int ok = send_body(w.buf, w.len);
    free(w.buf);
    return ok;
  }
  writer_t pcm = {0};
  int16_t chunk[4096];
  E->run_frame(g_engine, count);
  /* Fast-forward drains every frame's audio but keeps none of it, matching
   * the in-process worker. */
  size_t got;
  while ((got = E->audio_drain(g_engine, chunk, 2048)) > 0) {
    if (count == 1) wr_bytes(&pcm, chunk, got * 2 * sizeof(int16_t));
  }
  unsigned fw = 0, fh = 0;
  E->frame_size(g_engine, &fw, &fh);
  if (fw == 0 || fh == 0) {
    wr_u8(&w, 0);
  } else {
    size_t bytes = (size_t)fw * fh * 4;
    wr_u8(&w, 1);
    wr_u32(&w, fw);
    wr_u32(&w, fh);
    wr_u32(&w, (uint32_t)bytes);
    if (wr_reserve(&w, bytes)) {
      E->pixels_copy(g_engine, w.buf + w.len, bytes);
      w.len += bytes;
    }
    wr_u32(&w, (uint32_t)pcm.len);
    wr_bytes(&w, pcm.buf, pcm.len);
  }
  free(pcm.buf);
  int ok = send_body(w.buf, w.len);
  free(w.buf);
  return ok;
}

static int send_ok_empty(void) {
  uint8_t ok = EZH_OK;
  return send_body(&ok, 1);
}

static int op_save(void) {
  size_t n = E->serialize_size(g_engine);
  if (n == 0) return send_error("engine does not support save states");
  writer_t w = {0};
  wr_u8(&w, EZH_OK);
  wr_u32(&w, (uint32_t)n);
  if (!wr_reserve(&w, n) ||
      !E->serialize(g_engine, w.buf + w.len, n)) {
    free(w.buf);
    return send_error("save state failed");
  }
  w.len += n;
  int ok = send_body(w.buf, w.len);
  free(w.buf);
  return ok;
}

static int op_cheats(reader_t *r) {
  uint32_t n = rd_u32(r);
  if (r->bad || n > 100000) return send_error("malformed CHEATS request");
  E->cheat_reset(g_engine);
  writer_t failed = {0};
  uint32_t n_failed = 0;
  for (uint32_t i = 0; i < n && !r->bad; i++) {
    uint32_t index = rd_u32(r);
    uint8_t enabled = rd_u8(r);
    char *code = rd_str(r);
    if (code && code[strspn(code, " \t\r\n")] != '\0' &&
        !E->cheat_set(g_engine, index, enabled != 0, code)) {
      wr_u32(&failed, index);
      n_failed++;
    }
    free(code);
  }
  if (r->bad) { free(failed.buf); return send_error("malformed CHEATS request"); }
  writer_t w = {0};
  wr_u8(&w, EZH_OK);
  wr_u32(&w, n_failed);
  wr_bytes(&w, failed.buf, failed.len);
  free(failed.buf);
  int ok = send_body(w.buf, w.len);
  free(w.buf);
  return ok;
}

static int op_options(void) {
  writer_t w = {0};
  unsigned n = E->option_count(g_engine);
  wr_u8(&w, EZH_OK);
  wr_u32(&w, n);
  for (unsigned i = 0; i < n; i++) {
    const char *k = NULL, *d = NULL, *v = NULL;
    E->option_get(g_engine, i, &k, &d, &v);
    wr_str(&w, k);
    wr_str(&w, d);
    wr_str(&w, v);
  }
  int ok = send_body(w.buf, w.len);
  free(w.buf);
  return ok;
}

/* Returns 0 when the loop should stop (CLOSE, or the app is unreachable). */
static int dispatch(const uint8_t *body, size_t n) {
  reader_t r = {body, n, 0};
  uint8_t op = rd_u8(&r);
  if (op == EZH_OP_OPEN) return op_open(&r);
  if (op == EZH_OP_CLOSE) {
    if (g_engine) { E->destroy(g_engine); g_engine = NULL; }
    send_ok_empty();
    return 0;
  }
  if (!g_engine) {
    if ((op >= EZH_OP_FRAME && op <= EZH_OP_SET_OPTION) ||
        (op >= EZH_OP_ANALOG && op <= EZH_OP_POINTER))
      return send_error("no session is open");
    return send_error("unknown op");
  }
  switch (op) {
    case EZH_OP_FRAME: return op_frame(&r);
    case EZH_OP_PAUSE:
      g_paused = rd_u8(&r) != 0;
      /* A button held on any pad must not stay down across the pause. */
      if (g_paused) release_all_buttons();
      E->pause(g_engine, g_paused);
      return send_ok_empty();
    case EZH_OP_BUTTON: {
      uint32_t port = rd_u32(&r), id = rd_u32(&r);
      uint8_t pressed = rd_u8(&r);
      if (r.bad || port > 3 || id > 15) return send_error("bad button");
      E->set_button(g_engine, port, id, pressed != 0);
      return send_ok_empty();
    }
    case EZH_OP_SAVE: return op_save();
    case EZH_OP_RESTORE: {
      uint32_t len = 0;
      const uint8_t *state = rd_blob(&r, &len);
      if (!state) return send_error("malformed RESTORE request");
      if (!E->unserialize(g_engine, state, len))
        return send_error("engine rejected save state");
      return send_ok_empty();
    }
    case EZH_OP_CHEATS: return op_cheats(&r);
    case EZH_OP_RESET:
      E->reset(g_engine);
      return send_ok_empty();
    case EZH_OP_OPTIONS: return op_options();
    case EZH_OP_SET_OPTION: {
      char *k = rd_str(&r), *v = rd_str(&r);
      int ok;
      if (r.bad) {
        ok = send_error("malformed SET_OPTION request");
      } else {
        uint8_t body2[2] = {EZH_OK,
                            (uint8_t)(E->option_set(g_engine, k, v) ? 1 : 0)};
        ok = send_body(body2, 2);
      }
      free(k); free(v);
      return ok;
    }
    case EZH_OP_ANALOG: {
      uint32_t port = rd_u32(&r), stick = rd_u32(&r), axis = rd_u32(&r);
      int32_t value = (int32_t)rd_u32(&r);
      if (r.bad) return send_error("malformed ANALOG request");
      E->set_analog(g_engine, port, stick, axis,
                    (int16_t)(value > 32767 ? 32767 : value < -32768 ? -32768 : value));
      return send_ok_empty();
    }
    case EZH_OP_MOUSE_MOVE: {
      int32_t dx = (int32_t)rd_u32(&r), dy = (int32_t)rd_u32(&r);
      if (r.bad) return send_error("malformed MOUSE_MOVE request");
      E->mouse_move(g_engine, dx, dy);
      return send_ok_empty();
    }
    case EZH_OP_MOUSE_BTN: {
      uint32_t id = rd_u32(&r);
      uint8_t pressed = rd_u8(&r);
      if (r.bad) return send_error("malformed MOUSE_BTN request");
      E->mouse_button(g_engine, id, pressed != 0);
      return send_ok_empty();
    }
    case EZH_OP_KEY: {
      uint32_t code = rd_u32(&r);
      uint8_t pressed = rd_u8(&r);
      uint32_t ch = rd_u32(&r), mods = rd_u32(&r);
      if (r.bad) return send_error("malformed KEY request");
      E->key(g_engine, code, pressed != 0, ch, (uint16_t)mods);
      return send_ok_empty();
    }
    case EZH_OP_POINTER: {
      int32_t x = (int32_t)rd_u32(&r), y = (int32_t)rd_u32(&r);
      uint8_t pressed = rd_u8(&r);
      if (r.bad) return send_error("malformed POINTER request");
      E->pointer(g_engine,
                 (int16_t)(x > 32767 ? 32767 : x < -32767 ? -32767 : x),
                 (int16_t)(y > 32767 ? 32767 : y < -32767 ? -32767 : y),
                 pressed != 0);
      return send_ok_empty();
    }
    default: return send_error("unknown op");
  }
}

int main(int argc, char **argv) {
  /* Engine selection is data, not a protocol change: --engine=NAME, or the
   * EZCORE_ENGINE environment variable. libretro remains the default. */
  const char *name = getenv("EZCORE_ENGINE");
  for (int i = 1; i < argc; i++) {
    if (strncmp(argv[i], "--engine=", 9) == 0) name = argv[i] + 9;
  }
  if (!name || !*name) name = "libretro";
  ezh_engine_register(&ezh_engine_libretro);
  ezh_engine_register(&ezh_engine_synthetic);
  E = ezh_engine_find(name);
  if (!E) {
    char names[256];
    ezh_engine_names(names, sizeof(names));
    fprintf(stderr, "ezcore_core_host: unknown engine '%s' (available: %s)\n",
            name, names);
    return 2;
  }
#ifdef _WIN32
  _setmode(_fileno(stdin), _O_BINARY);
  _setmode(_fileno(stdout), _O_BINARY);
#endif
  /* Take the real stdout for the protocol, then aim fd 1 at stderr so a
   * core's printf can never land on the protocol stream. */
  int proto_fd = dup(fileno(stdout));
  fflush(stdout);
  dup2(fileno(stderr), fileno(stdout));
  g_in = stdin;
  g_out = fdopen(proto_fd, "wb");
  if (!g_out) return 3;

  for (;;) {
    uint8_t hdr[4];
    if (fread(hdr, 1, 4, g_in) != 4) break; /* EOF: the app is gone */
    uint32_t n = (uint32_t)hdr[0] | ((uint32_t)hdr[1] << 8) |
                 ((uint32_t)hdr[2] << 16) | ((uint32_t)hdr[3] << 24);
    if (n == 0 || n > EZH_MAX_REQUEST) break; /* desynchronised: stop safely */
    uint8_t *body = malloc(n);
    if (!body) break;
    if (fread(body, 1, n, g_in) != n) { free(body); break; }
    int keep_going = dispatch(body, n);
    free(body);
    if (!keep_going) break;
  }
  if (g_engine) E->destroy(g_engine);
  return 0;
}

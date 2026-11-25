// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* ezplay.c — run a play spec against one core and dump, and print a JSON result.
 *
 * Usage:
 *   ezplay --core <core.so> --content <dump> --system-dir <dir> \
 *          --save-dir <dir> --spec <spec.json> [--cheat <code>]
 *
 * The harness extends test_core_boot's exit-code table without changing any
 * existing meaning:
 *   0 = pass (every mandatory check PASS or SKIP)
 *   1 = load/init failed
 *   2 = load_game failed
 *   3 = no pixels after the configured frame count
 *   4 = save_state failed
 *   5 = load_state failed
 *   6 = restore did not reproduce the saved frame
 *   7 = frame capture could not be written          (only when requested)
 *   9 = crash (the core died; the harness forks so the caller survives)
 *  10 = bad arguments or an unreadable/invalid spec
 *  11 = a mandatory play check failed (the dump does not reach PLAYS)
 *  12 = content does not match the spec's system (foreign file)
 *
 * JSON is written to stdout and nothing else is; diagnostics go to stderr.
 * On POSIX the work runs in a forked child so a crashing core becomes exit 9
 * with a valid JSON error result rather than a silent signal death.
 */
#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#include <sys/wait.h>
#include <time.h>
#endif

#include "ezcore_runtime.h"
#include "libretro.h"

#define MAX_INPUTS 64
#define MAX_CHECKPOINTS 512
#define AUDIO_BUF_FRAMES 4096
#define SAVE_STATE_REPLAY_FRAMES 60
#define NOMINAL_FPS 60.0
#define MAX_SRAM_BYTES (16u * 1024u * 1024u)

/* ------------------------------------------------------------------ */
/* A small JSON reader. Play specs are plain objects/arrays/strings/numbers;
 * no external dependency is available on every target the runtime builds for.
 * ------------------------------------------------------------------ */
typedef enum { J_NULL, J_BOOL, J_NUM, J_STR, J_ARR, J_OBJ } jtype;

typedef struct jval jval;
struct jval {
  jtype type;
  bool b;
  double num;
  char *str;
  jval **items;
  size_t nitems;
  char **keys;
  jval **vals;
  size_t nprops;
};

static void jfree(jval *v) {
  if (!v) return;
  free(v->str);
  for (size_t i = 0; i < v->nitems; i++) jfree(v->items[i]);
  free(v->items);
  for (size_t i = 0; i < v->nprops; i++) {
    free(v->keys[i]);
    jfree(v->vals[i]);
  }
  free(v->keys);
  free(v->vals);
  free(v);
}

static void jws(const char **p) {
  while (**p && isspace((unsigned char)**p)) (*p)++;
}

static void jutf8(char *out, size_t *n, unsigned cp) {
  if (cp < 0x80) out[(*n)++] = (char)cp;
  else if (cp < 0x800) {
    out[(*n)++] = (char)(0xC0 | (cp >> 6));
    out[(*n)++] = (char)(0x80 | (cp & 0x3F));
  } else {
    out[(*n)++] = (char)(0xE0 | (cp >> 12));
    out[(*n)++] = (char)(0x80 | ((cp >> 6) & 0x3F));
    out[(*n)++] = (char)(0x80 | (cp & 0x3F));
  }
}

static char *jstring(const char **p) {
  if (**p != '"') return NULL;
  (*p)++;
  size_t cap = 64, n = 0;
  char *s = malloc(cap);
  if (!s) return NULL;
  while (**p && **p != '"') {
    unsigned char c = (unsigned char)*(*p)++;
    unsigned cp = c;
    if (c == '\\') {
      if (!**p) break;
      c = (unsigned char)*(*p)++;
      switch (c) {
        case 'n': cp = '\n'; break;
        case 'r': cp = '\r'; break;
        case 't': cp = '\t'; break;
        case 'b': cp = '\b'; break;
        case 'f': cp = '\f'; break;
        case 'u': {
          cp = 0;
          for (int k = 0; k < 4 && **p; k++) {
            char h = *(*p)++;
            cp = cp * 16 + (unsigned)(isdigit((unsigned char)h) ? h - '0'
                 : (tolower((unsigned char)h) - 'a' + 10));
          }
          break;
        }
        default: cp = c; break;
      }
    }
    if (n + 4 >= cap) {
      cap *= 2;
      char *tmp = realloc(s, cap);
      if (!tmp) { free(s); return NULL; }
      s = tmp;
    }
    jutf8(s, &n, cp);
  }
  if (**p == '"') (*p)++;
  s[n] = '\0';
  return s;
}

static jval *jparse_val(const char **p);

static jval *jnew(jtype t) {
  jval *v = calloc(1, sizeof(*v));
  if (v) v->type = t;
  return v;
}

static jval *jparse_val(const char **p) {
  jws(p);
  char c = **p;
  jval *v = NULL;
  if (c == '{') {
    v = jnew(J_OBJ);
    (*p)++;
    jws(p);
    if (**p == '}') { (*p)++; return v; }
    for (;;) {
      jws(p);
      char *k = jstring(p);
      if (!k) { jfree(v); return NULL; }
      jws(p);
      if (**p != ':') { free(k); jfree(v); return NULL; }
      (*p)++;
      jval *child = jparse_val(p);
      if (!child) { free(k); jfree(v); return NULL; }
      char **nk = realloc(v->keys, (v->nprops + 1) * sizeof(*v->keys));
      jval **nv = realloc(v->vals, (v->nprops + 1) * sizeof(*v->vals));
      if (!nk || !nv) { free(k); jfree(child); jfree(v); return NULL; }
      v->keys = nk; v->vals = nv;
      v->keys[v->nprops] = k;
      v->vals[v->nprops] = child;
      v->nprops++;
      jws(p);
      if (**p == ',') { (*p)++; continue; }
      if (**p == '}') { (*p)++; return v; }
      jfree(v);
      return NULL;
    }
  }
  if (c == '[') {
    v = jnew(J_ARR);
    (*p)++;
    jws(p);
    if (**p == ']') { (*p)++; return v; }
    for (;;) {
      jval *child = jparse_val(p);
      if (!child) { jfree(v); return NULL; }
      jval **n = realloc(v->items, (v->nitems + 1) * sizeof(*v->items));
      if (!n) { jfree(child); jfree(v); return NULL; }
      v->items = n;
      v->items[v->nitems++] = child;
      jws(p);
      if (**p == ',') { (*p)++; continue; }
      if (**p == ']') { (*p)++; return v; }
      jfree(v);
      return NULL;
    }
  }
  if (c == '"') {
    v = jnew(J_STR);
    v->str = jstring(p);
    if (!v->str) { jfree(v); return NULL; }
    return v;
  }
  if (!strncmp(*p, "true", 4)) {
    *p += 4;
    jval *b = jnew(J_BOOL);
    if (b) b->b = true;
    return b;
  }
  if (!strncmp(*p, "false", 5)) {
    *p += 5;
    jval *b = jnew(J_BOOL);
    if (b) b->b = false;
    return b;
  }
  if (!strncmp(*p, "null", 4)) {
    *p += 4;
    return jnew(J_NULL);
  }
  if (c == '-' || isdigit((unsigned char)c)) {
    char *end = NULL;
    double d = strtod(*p, &end);
    if (end == *p) return NULL;
    *p = end;
    jval *n = jnew(J_NUM);
    if (n) n->num = d;
    return n;
  }
  return NULL;
}

static jval *jget(const jval *obj, const char *key) {
  if (!obj || obj->type != J_OBJ) return NULL;
  for (size_t i = 0; i < obj->nprops; i++)
    if (!strcmp(obj->keys[i], key)) return obj->vals[i];
  return NULL;
}

static bool jas_bool(const jval *v, bool fallback) {
  return v && v->type == J_BOOL ? v->b : fallback;
}

static double jas_num(const jval *v, double fallback) {
  return v && v->type == J_NUM ? v->num : fallback;
}

static const char *jas_str(const jval *v, const char *fallback) {
  return v && v->type == J_STR ? v->str : fallback;
}

/* ------------------------------------------------------------------ */
/* SHA-256 over the RGBA bytes of a frame. Self-contained so the harness
 * produces the same digest on hosts without a crypto library. The frame
 * pointer is dense XRGB8888 (w*h pixels), so pitch padding is excluded. */
static uint32_t sha_rotr32(uint32_t x, unsigned n) {
  return (x >> n) | (x << (32 - n));
}

static void sha256_block(uint32_t h[8], const unsigned char b[64]) {
  static const uint32_t k[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u,
    0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
    0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
    0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
    0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u,
    0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u,
    0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
    0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};
  uint32_t w[64];
  for (unsigned i = 0; i < 16; i++)
    w[i] = ((uint32_t)b[i * 4] << 24) | ((uint32_t)b[i * 4 + 1] << 16) |
           ((uint32_t)b[i * 4 + 2] << 8) | (uint32_t)b[i * 4 + 3];
  for (unsigned i = 16; i < 64; i++) {
    uint32_t s0 = sha_rotr32(w[i - 15], 7) ^ sha_rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3);
    uint32_t s1 = sha_rotr32(w[i - 2], 17) ^ sha_rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  uint32_t a = h[0], bb = h[1], c = h[2], d = h[3];
  uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];
  for (unsigned i = 0; i < 64; i++) {
    uint32_t s1 = sha_rotr32(e, 6) ^ sha_rotr32(e, 11) ^ sha_rotr32(e, 25);
    uint32_t ch = (e & f) ^ ((~e) & g);
    uint32_t t1 = hh + s1 + ch + k[i] + w[i];
    uint32_t s0 = sha_rotr32(a, 2) ^ sha_rotr32(a, 13) ^ sha_rotr32(a, 22);
    uint32_t maj = (a & bb) ^ (a & c) ^ (bb & c);
    uint32_t t2 = s0 + maj;
    hh = g; g = f; f = e; e = d + t1;
    d = c; c = bb; bb = a; a = t1 + t2;
  }
  h[0] += a; h[1] += bb; h[2] += c; h[3] += d;
  h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

static void sha256_bytes(const unsigned char *data, size_t len, char out[65]) {
  uint32_t h[8] = {0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
                   0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};
  uint64_t bits = (uint64_t)len * 8;
  size_t pos = 0;
  while (len - pos >= 64) { sha256_block(h, data + pos); pos += 64; }
  unsigned char block[64] = {0};
  size_t rem = len - pos;
  memcpy(block, data + pos, rem);
  block[rem] = 0x80;
  if (rem >= 56) { sha256_block(h, block); memset(block, 0, sizeof(block)); }
  for (unsigned i = 0; i < 8; i++)
    block[56 + i] = (unsigned char)(bits >> (56 - 8 * i));
  sha256_block(h, block);
  for (unsigned i = 0; i < 8; i++)
    snprintf(out + i * 8, 9, "%08x", h[i]);
  out[64] = '\0';
}

static int cmp_u32(const void *a, const void *b) {
  uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
  return x < y ? -1 : x > y ? 1 : 0;
}

static int distinct_colours(const uint32_t *px, size_t n) {
  uint32_t *v = malloc(n * sizeof(*v));
  if (!v) return 0;
  for (size_t i = 0; i < n; i++)
    v[i] = ((px[i] >> 16) & 0xFFu) << 16 | ((px[i] >> 8) & 0xFFu) << 8 | (px[i] & 0xFFu);
  qsort(v, n, sizeof(*v), cmp_u32);
  int distinct = 0;
  for (size_t i = 0; i < n; i++)
    if (i == 0 || v[i] != v[i - 1]) distinct++;
  free(v);
  return distinct;
}

/* ------------------------------------------------------------------ */
/* Monotonic wall clock and pacing, shared by all five targets. */
static int64_t now_ns(void) {
#ifdef _WIN32
  LARGE_INTEGER f, t;
  QueryPerformanceFrequency(&f);
  QueryPerformanceCounter(&t);
  return (int64_t)(t.QuadPart * 1000000000LL / f.QuadPart);
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
}

static void sleep_ns(int64_t ns) {
  if (ns <= 0) return;
#ifdef _WIN32
  Sleep((DWORD)(ns / 1000000));
#else
  struct timespec ts = {ns / 1000000000LL, ns % 1000000000LL};
  nanosleep(&ts, NULL);
#endif
}

/* ------------------------------------------------------------------ */
/* Resolved play spec (overrides are applied by the workspace runner
 * before it writes the file passed here; extra keys are ignored). */
#define MAX_PRESS 8

typedef struct {
  int at, hold, port, npress;
  bool is_key[MAX_PRESS];
  unsigned id[MAX_PRESS];
  char name[40];
} input_event;

typedef struct {
  char system[32];
  int frames;
  input_event events[MAX_INPUTS];
  int nevents;
  bool video_changes;
  int min_colours;
  double audio_rms_min;
  bool audio_rms_na;
  double speed_min;
  bool save_state;
  bool save_state_na;
  bool battery_save;
  bool battery_na;
  double ff2, ff4;
  int cheat;              /* 0 skip, 1 optional, 2 mandatory */
  char cheat_code[128];
} spec_t;

typedef struct {
  int frame;
  char sha[65];
  int colours;
} checkpoint;

typedef struct {
  int at, hold;
  bool changed;
  int colours_before, colours_after;
} event_result;

typedef struct {
  char system[32], core[128], version[64];
  int frames;
  checkpoint cps[MAX_CHECKPOINTS];
  int ncps;
  char *all_frames;       /* frames * 65 bytes of SHA-256 */
  event_result events[MAX_INPUTS];
  int nevents;
  uint64_t audio_samples;
  double audio_rms;
  int audio_silent;
  double unpaced_fps, realtime_ratio, ff2, ff4;
  const char *save_verdict;
  size_t save_size;
  int save_frames, save_mismatches;
  const char *save_reason;
  const char *battery_verdict;
  size_t battery_bytes;
  const char *battery_reason;
  const char *cheat_verdict;
  int cheat_memory_written, cheat_frame_changed;
  const char *cheat_reason;
  char cheat_code[128];
  const char *v_video, *v_colours, *v_audio, *v_speed, *v_save, *v_battery,
              *v_ff, *v_cheat;
  const char *verdict;
  char error[512];
  int exit_code;
} result_t;

/* Button names in specs are lowercase libretro-style names. Keyboard aliases
 * are resolved to RETROK_* values and sent through ezcore_set_key; everything
 * else is a joypad button. */
static bool resolve_button(const char *name, bool *is_key, unsigned *id) {
  static const struct { const char *name; unsigned id; } map[] = {
    {"b", RETRO_DEVICE_ID_JOYPAD_B}, {"y", RETRO_DEVICE_ID_JOYPAD_Y},
    {"select", RETRO_DEVICE_ID_JOYPAD_SELECT}, {"start", RETRO_DEVICE_ID_JOYPAD_START},
    {"up", RETRO_DEVICE_ID_JOYPAD_UP}, {"down", RETRO_DEVICE_ID_JOYPAD_DOWN},
    {"left", RETRO_DEVICE_ID_JOYPAD_LEFT}, {"right", RETRO_DEVICE_ID_JOYPAD_RIGHT},
    {"a", RETRO_DEVICE_ID_JOYPAD_A}, {"x", RETRO_DEVICE_ID_JOYPAD_X},
    {"l", RETRO_DEVICE_ID_JOYPAD_L}, {"r", RETRO_DEVICE_ID_JOYPAD_R},
    {"l2", RETRO_DEVICE_ID_JOYPAD_L2}, {"r2", RETRO_DEVICE_ID_JOYPAD_R2},
    {"l3", RETRO_DEVICE_ID_JOYPAD_L3}, {"r3", RETRO_DEVICE_ID_JOYPAD_R3},
  };
  for (size_t i = 0; i < sizeof(map) / sizeof(map[0]); i++)
    if (!strcmp(name, map[i].name)) { *is_key = false; *id = map[i].id; return true; }
  if (!strcmp(name, "enter")) { *is_key = true; *id = RETROK_RETURN; return true; }
  if (!strcmp(name, "space")) { *is_key = true; *id = RETROK_SPACE; return true; }
  return false;
}

/* Content must match the system the spec describes. This is the harness's
 * cheap first line of defence against a foreign dump being scored by the
 * wrong spec; a core that accepts the wrong bytes still cannot pass the
 * video/audio checks that follow. */
static const char *content_extensions(const char *system) {
  if (!strcmp(system, "nes") || !strcmp(system, "fds")) return " nes ";
  if (!strcmp(system, "gb") || !strcmp(system, "gbc")) return " gb gbc ";
  if (!strcmp(system, "gba")) return " gba ";
  if (!strcmp(system, "synth")) return " synth ";
  if (!strcmp(system, "genesis")) return " md genesis bin ";
  if (!strcmp(system, "snes")) return " snes sfc smc ";
  if (!strcmp(system, "psx")) return " cue bin chd ";
  if (!strcmp(system, "n64")) return " n64 z64 v64 ";
  if (!strcmp(system, "nds")) return " nds ";
  if (!strcmp(system, "psp")) return " iso cso pbp ";
  if (!strcmp(system, "pce")) return " pce ";
  if (!strcmp(system, "atari2600")) return " bin a26 ";
  if (!strcmp(system, "dos")) return " exe zip com bat ";
  if (!strcmp(system, "scumm")) return " zip scumm ";
  if (!strcmp(system, "watara")) return " bin sv wav ";
  if (!strcmp(system, "lcdhandheld")) return " mgw ";
  return NULL;                             /* unknown system: no extension gate */
}

static void content_extension(const char *content, char *out, size_t len) {
  out[0] = '\0';
  const char *dot = strrchr(content, '.');
  if (!dot) return;
  size_t n = 0;
  for (const char *p = dot + 1; *p && n + 1 < len; p++)
    out[n++] = (char)tolower((unsigned char)*p);
  out[n] = '\0';
}

static void describe_extensions(const char *exts, char *out, size_t len) {
  out[0] = '\0';
  size_t used = 0;
  for (const char *p = exts; *p;) {
    while (*p == ' ') p++;
    if (!*p) break;
    const char *start = p;
    while (*p && *p != ' ') p++;
    int written = snprintf(out + used, len - used, "%s.%.*s",
                           used ? ", " : "", (int)(p - start), start);
    if (written < 0 || (size_t)written >= len - used) break;
    used += (size_t)written;
  }
}

static bool content_matches(const char *system, const char *content) {
  const char *exts = content_extensions(system);
  if (!exts) return true;
  char want[16];
  content_extension(content, want, sizeof(want));
  if (!want[0]) return false;
  char needle[24];
  snprintf(needle, sizeof(needle), " %s ", want);
  return strstr(exts, needle) != NULL;
}

static bool parse_spec(const char *path, spec_t *sp, char *err, size_t errlen) {
  memset(sp, 0, sizeof(*sp));
  FILE *f = fopen(path, "rb");
  if (!f) {
    snprintf(err, errlen, "cannot open spec '%s': %s", path, strerror(errno));
    return false;
  }
  fseek(f, 0, SEEK_END);
  long len = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (len <= 0 || len > 8 * 1024 * 1024) {
    fclose(f);
    snprintf(err, errlen, "spec '%s' is empty or too large", path);
    return false;
  }
  char *text = malloc((size_t)len + 1);
  if (!text) { fclose(f); snprintf(err, errlen, "out of memory reading spec"); return false; }
  if (fread(text, 1, (size_t)len, f) != (size_t)len) {
    free(text); fclose(f); snprintf(err, errlen, "short read of spec '%s'", path); return false;
  }
  text[len] = '\0';
  fclose(f);

  const char *p = text;
  jval *root = jparse_val(&p);
  free(text);
  if (!root || root->type != J_OBJ) {
    jfree(root);
    snprintf(err, errlen, "spec is not a JSON object");
    return false;
  }
  snprintf(sp->system, sizeof(sp->system), "%s", jas_str(jget(root, "system"), ""));
  sp->frames = (int)jas_num(jget(root, "frames"), 0);
  if (sp->frames < 2 || sp->frames > 100000) {
    snprintf(err, errlen, "spec frames must be between 2 and 100000");
    jfree(root);
    return false;
  }

  jval *inputs = jget(root, "input");
  if (inputs && inputs->type == J_ARR) {
    for (size_t i = 0; i < inputs->nitems && sp->nevents < MAX_INPUTS; i++) {
      jval *e = inputs->items[i];
      input_event *out = &sp->events[sp->nevents];
      out->at = (int)jas_num(jget(e, "at"), -1);
      out->hold = (int)jas_num(jget(e, "hold"), 0);
      jval *press = jget(e, "press");
      const char *name = press && press->nitems ? jas_str(press->items[0], "") : "";
      snprintf(out->name, sizeof(out->name), "%s", name);
      if (out->at < 0 || out->hold < 1 || out->at + out->hold > sp->frames ||
          !press || !press->nitems) {
        snprintf(err, errlen, "invalid input event %zu", i + 1);
        jfree(root);
        return false;
      }
      for (size_t b = 0; b < press->nitems && out->npress < MAX_PRESS; b++) {
        const char *button = jas_str(press->items[b], "");
        if (!resolve_button(button, &out->is_key[out->npress], &out->id[out->npress])) {
          snprintf(err, errlen, "unknown button '%s' in event %zu", button, i + 1);
          jfree(root);
          return false;
        }
        out->npress++;
      }
      sp->nevents++;
    }
  }

  jval *checks = jget(root, "checks");
  sp->video_changes = jas_bool(jget(checks, "video_changes_after_input"), false);
  sp->min_colours = (int)jas_num(jget(checks, "min_colours"), 1);
  jval *rms = jget(checks, "audio_rms_min");
  sp->audio_rms_na = !rms || (rms->type == J_STR && !strcmp(rms->str, "n/a"));
  sp->audio_rms_min = sp->audio_rms_na ? 0.0 : jas_num(rms, 0.0);
  sp->speed_min = jas_num(jget(checks, "speed_min"), 0.0);
  jval *ss = jget(checks, "save_state_roundtrip");
  sp->save_state_na = ss && ss->type == J_STR && !strcmp(ss->str, "n/a");
  sp->save_state = !sp->save_state_na && jas_bool(ss, false);
  jval *bs = jget(checks, "battery_save_roundtrip");
  sp->battery_na = bs && bs->type == J_STR && !strcmp(bs->str, "n/a");
  sp->battery_save = !sp->battery_na && jas_bool(bs, false);
  jval *ff = jget(checks, "fast_forward");
  sp->ff2 = jas_num(jget(ff, "2x"), 0.0);
  sp->ff4 = jas_num(jget(ff, "4x"), 0.0);
  jval *ch = jget(checks, "cheat");
  if (ch && ch->type == J_BOOL) sp->cheat = ch->b ? 2 : 0;
  else if (ch && ch->type == J_STR && !strcmp(ch->str, "optional")) sp->cheat = 1;
  /* false and "n/a" both leave cheat at 0 (skip). */

  jfree(root);
  return true;
}

#define MAX_KEYS 8

typedef struct { uint16_t btn[4]; unsigned key[MAX_KEYS]; } frame_input;

/* Expand the event list into a per-frame input mask. Later events add to,
 * rather than replace, earlier ones: the spec reader says there is no
 * implicit release. */
static frame_input *expand_input(const spec_t *sp) {
  frame_input *m = calloc((size_t)sp->frames, sizeof(*m));
  if (!m) return NULL;
  for (int e = 0; e < sp->nevents; e++) {
    const input_event *ev = &sp->events[e];
    for (int f = ev->at; f < ev->at + ev->hold; f++) {
      for (int b = 0; b < ev->npress; b++) {
        if (ev->is_key[b]) {
          for (int k = 0; k < MAX_KEYS; k++)
            if (!m[f].key[k]) { m[f].key[k] = ev->id[b]; break; }
        } else if (ev->id[b] < 16) {
          m[f].btn[ev->port] |= (uint16_t)(1u << ev->id[b]);
        }
      }
    }
  }
  return m;
}

static void apply_input(ezcore_session *s, const frame_input *in, unsigned *prev_keys) {
  for (unsigned port = 0; port < 4; port++) {
    ezcore_clear_buttons(s, port);
    for (unsigned b = 0; b < 16; b++)
      if (in->btn[port] & (1u << b)) ezcore_set_button(s, port, b, true);
  }
  for (int k = 0; k < MAX_KEYS; k++) {
    if (prev_keys[k] && prev_keys[k] != in->key[k])
      ezcore_set_key(s, prev_keys[k], false, 0, 0);
    if (in->key[k] && prev_keys[k] != in->key[k])
      ezcore_set_key(s, in->key[k], true, 0, 0);
    prev_keys[k] = in->key[k];
  }
}

typedef struct {
  const char *core_path;
  const char *content_path;
  void *content;
  size_t content_size;
  const spec_t *spec;
  frame_input *input;
} context_t;

static ezcore_session *open_session(const context_t *ctx, int *rc) {
  char err[1024] = {0};
  ezcore_session *s = ezcore_load(ctx->core_path, err, sizeof(err));
  if (!s) {
    fprintf(stderr, "ezplay: ezcore_load failed: %s\n", err);
    *rc = 1;
    return NULL;
  }
  if (!ezcore_init(s)) {
    fprintf(stderr, "ezplay: ezcore_init failed\n");
    ezcore_unload(s);
    *rc = 1;
    return NULL;
  }
  if (!ezcore_load_game(s, ctx->content_path, ctx->content, ctx->content_size)) {
    fprintf(stderr, "ezplay: load_game failed\n");
    ezcore_unload(s);
    *rc = 2;
    return NULL;
  }
  return s;
}

typedef struct { uint64_t samples; double sum_sq; int silent, longest; } audio_acc;

static void drain_audio(ezcore_session *s, audio_acc *a) {
  int16_t buf[AUDIO_BUF_FRAMES * 2];
  size_t n = ezcore_audio_drain(s, buf, AUDIO_BUF_FRAMES);
  if (!n) return;
  bool allzero = true;
  for (size_t i = 0; i < n * 2; i++) {
    double v = (double)buf[i] / 32768.0;
    a->sum_sq += v * v;
    if (buf[i]) allzero = false;
  }
  a->samples += n * 2;
  if (allzero) {
    a->silent++;
    if (a->silent > a->longest) a->longest = a->silent;
  } else {
    a->silent = 0;
  }
}

static bool frame_digest(ezcore_session *s, char sha[65], int *colours) {
  unsigned w = 0, h = 0;
  const uint32_t *px = ezcore_frame_pixels(s, &w, &h);
  if (!px || !w || !h) return false;
  sha256_bytes((const unsigned char *)px, (size_t)w * h * 4, sha);
  if (colours) *colours = distinct_colours(px, (size_t)w * h);
  return true;
}

/* Where the save-state replay starts: the release frame of the last input
 * event, or half the session when a spec has no input. */
static int save_frame(const spec_t *sp) {
  int f = sp->frames / 2;
  if (sp->nevents) {
    const input_event *e = &sp->events[sp->nevents - 1];
    f = e->at + e->hold;
  }
  return f < sp->frames ? f : sp->frames - 1;
}

static const char *ff_verdict(double v, double threshold) {
  return threshold > 0 && v >= threshold ? "PASS" : "FAIL";
}

/* The main session: one pass over the spec's frames, with frame hashes,
 * colour counts, audio statistics and the save-state round trip. */
static int run_main_session(const context_t *ctx, result_t *r) {
  const spec_t *sp = ctx->spec;
  int frames = sp->frames;
  char *all = malloc((size_t)frames * 65);
  int *cols = malloc((size_t)frames * sizeof(int));
  unsigned char *mark = calloc((size_t)frames, 1);
  frame_input *input = ctx->input;
  audio_acc acc = {0};
  if (!all || !cols || !mark) {
    free(all); free(cols); free(mark);
    snprintf(r->error, sizeof(r->error), "out of memory for frame evidence");
    return 10;
  }

  int rc = 0;
  ezcore_session *s = open_session(ctx, &rc);
  if (!s) { free(all); free(cols); free(mark); return rc; }

  const char *name = ezcore_core_name(s);
  const char *ver = ezcore_core_version(s);
  snprintf(r->core, sizeof(r->core), "%s", name ? name : "");
  snprintf(r->version, sizeof(r->version), "%s", ver ? ver : "");

  int F = save_frame(sp);
  int replay_end = F + SAVE_STATE_REPLAY_FRAMES;
  if (replay_end >= frames) replay_end = frames - 1;
  size_t snap_size = sp->save_state ? ezcore_serialize_size(s) : 0;
  void *snap = snap_size ? malloc(snap_size) : NULL;
  if (snap_size && !snap) {
    ezcore_unload(s); free(all); free(cols); free(mark);
    snprintf(r->error, sizeof(r->error), "out of memory for save state");
    return 10;
  }
  if (sp->save_state && snap_size == 0) {
    r->save_verdict = "FAIL";
    r->save_reason = "retro_serialize_size() returned 0";
  }

  unsigned prev_keys[MAX_KEYS] = {0};
  int64_t unpaced_start = 0, unpaced_end = 0;
  bool save_unavailable = false;
  for (int i = 0; i < frames; i++) {
    if (i == 60) unpaced_start = now_ns();
    apply_input(s, &input[i], prev_keys);
    ezcore_run_frame(s);
    /* The play spec measures audio from the last event's release frame, not
     * from boot/menu audio. Discard the earlier window at that boundary. */
    if (i == F) memset(&acc, 0, sizeof(acc));
    drain_audio(s, &acc);

    if (!frame_digest(s, all + (size_t)i * 65, &cols[i])) {
      if (i >= 30) {
        r->exit_code = 3;
        snprintf(r->error, sizeof(r->error), "no frame pixels at frame %d", i);
        goto done;
      }
      all[i * 65] = '\0';
      cols[i] = 0;
    }

    /* Serialize at F, run 60 frames, load and replay the same 60 frames
     * under the same input, then compare every replayed frame hash. */
    if (sp->save_state && snap_size && snap && i == F) {
      if (!ezcore_serialize(s, snap, snap_size)) {
        /* The save-state check fails, but the remaining frames and audio are
         * still valid evidence for the other checks. Keep running instead of
         * discarding the whole session. */
        r->save_verdict = "FAIL";
        r->save_reason = "retro_serialize() failed";
        save_unavailable = true;
      } else {
        r->save_size = snap_size;
      }
    }
    if (sp->save_state && snap_size && snap && !save_unavailable && i == replay_end) {
      if (!ezcore_unserialize(s, snap, snap_size)) {
        r->save_verdict = "FAIL";
        r->save_reason = "retro_unserialize() failed";
        r->exit_code = 5;
        goto done;
      }
      /* Rewind to F by replaying from the loaded state. The frames from F
       * to replay_end are overwritten; the originals are kept in a copy. */
      /* The snapshot is taken after frame F ran, so unserialize puts the
       * core at F: the first replayed retro_run produces frame F+1. Compare
       * against the original hashes from F+1 onward, 60 frames in total. */
      size_t window = (size_t)(replay_end - F);
      char *original = malloc(window * 65);
      memcpy(original, all + (size_t)(F + 1) * 65, window * 65);
      unsigned replay_keys[MAX_KEYS] = {0};
      int mismatches = 0;
      audio_acc replay_audio = {0};
      for (int f = F; f < replay_end; f++) {
        apply_input(s, &input[f], replay_keys);
        ezcore_run_frame(s);
        drain_audio(s, &replay_audio);
        char digest[65];
        if (!frame_digest(s, digest, NULL) ||
            strcmp(digest, original + (size_t)(f - F) * 65)) {
          mismatches++;
        }
      }
      free(original);
      r->save_frames = replay_end - F;
      r->save_mismatches = mismatches;
      r->save_verdict = mismatches ? "FAIL" : "PASS";
      if (mismatches) r->save_reason = "replayed frame hash differs from the first run";
      if (mismatches) r->exit_code = 6;
      i = replay_end;   /* the emulation state is back at replay_end */
    }
  }
  unpaced_end = now_ns();

  double seconds = (unpaced_end - unpaced_start) / 1e9;
  if (seconds > 0)
    r->unpaced_fps = (double)(frames - 60) / seconds;

  r->audio_samples = acc.samples;
  r->audio_rms = acc.samples ? sqrt(acc.sum_sq / (double)acc.samples) : 0.0;
  r->audio_silent = acc.longest;

  /* Checkpoints: frame 0, every 60th frame, both sides of every input event,
   * and the save/replay boundary. The selection is a view over `all`. */
  mark[0] = 1;
  for (int i = 0; i < frames; i += 60) mark[i] = 1;
  for (int e = 0; e < sp->nevents; e++) {
    int a = sp->events[e].at;
    int b = a + sp->events[e].hold + 1;
    if (a >= 0 && a < frames) mark[a] = 1;
    if (b >= 0 && b < frames) mark[b] = 1;
  }
  if (F >= 0 && F < frames) mark[F] = 1;
  if (replay_end >= 0 && replay_end < frames) mark[replay_end] = 1;

  for (int i = 0; i < frames && r->ncps < MAX_CHECKPOINTS; i++) {
    if (!mark[i]) continue;
    checkpoint *cp = &r->cps[r->ncps++];
    cp->frame = i;
    snprintf(cp->sha, sizeof(cp->sha), "%s", all + (size_t)i * 65);
    cp->colours = cols[i];
  }

  /* Input verdicts: frame at+hold+1 must differ from frame max(0,at-1) and
   * both must clear the colour floor. */
  for (int e = 0; e < sp->nevents && r->nevents < MAX_INPUTS; e++) {
    int a = sp->events[e].at;
    int before = a > 0 ? a - 1 : 0;
    int after = a + sp->events[e].hold + 1;
    event_result *er = &r->events[r->nevents++];
    er->at = a;
    er->hold = sp->events[e].hold;
    if (after >= frames || !all[before * 65] || !all[after * 65]) {
      er->changed = false;
    } else {
      er->changed = strcmp(all + (size_t)before * 65, all + (size_t)after * 65) != 0;
    }
    er->colours_before = cols[before];
    er->colours_after = after < frames ? cols[after] : 0;
  }

  r->all_frames = all;
  free(cols);
  free(mark);
  ezcore_unload(s);
  return r->exit_code;

done:
  if (snap) free(snap);
  free(all); free(cols); free(mark);
  ezcore_unload(s);
  return r->exit_code ? r->exit_code : rc;
}

/* One full pass with an optional pacing period. Used for the paced real-time
 * ratio and the two fast-forward legs. Wall time is measured from frame 60,
 * following the play-spec definition, so startup is excluded. */
static int run_timed(const context_t *ctx, double period_ns, double *ratio) {
  int rc = 0;
  ezcore_session *s = open_session(ctx, &rc);
  if (!s) return rc;
  unsigned prev_keys[MAX_KEYS] = {0};
  int64_t start = 0;
  for (int i = 0; i < ctx->spec->frames; i++) {
    if (i == 60) start = now_ns();
    if (period_ns > 0 && i >= 60) {
      int64_t target = start + (int64_t)((i - 60) * period_ns);
      sleep_ns(target - now_ns());
    }
    apply_input(s, &ctx->input[i], prev_keys);
    ezcore_run_frame(s);
    int16_t sink[AUDIO_BUF_FRAMES * 2];
    ezcore_audio_drain(s, sink, AUDIO_BUF_FRAMES);
  }
  int64_t elapsed = now_ns() - start;
  ezcore_unload(s);
  if (elapsed <= 0) { *ratio = 0.0; return 0; }
  *ratio = (double)(ctx->spec->frames - 60) * 1e9 / (elapsed * NOMINAL_FPS);
  return 0;
}

typedef struct { unsigned char *data; size_t len; } memblob;

static memblob collect_memory(ezcore_session *s, uint64_t want_flag) {
  memblob b = {0};
  unsigned n = ezcore_get_memory_descriptor_count(s);
  for (unsigned i = 0; i < n; i++) {
    uint64_t flags = 0;
    void *ptr = NULL;
    size_t len = 0;
    if (!ezcore_get_memory_descriptor(s, i, &flags, &ptr, NULL, NULL, NULL,
                                      NULL, &len, NULL)) continue;
    if (!(flags & want_flag) || !ptr || !len || len > MAX_SRAM_BYTES) continue;
    unsigned char *grow = realloc(b.data, b.len + len);
    if (!grow) break;
    b.data = grow;
    memcpy(b.data + b.len, ptr, len);
    b.len += len;
  }
  /* Many cores expose battery RAM only through the legacy libretro memory API
   * and either register no memory maps or leave SAVE_RAM unflagged. Use it as
   * a fallback, but never label a region battery-backed that the core does
   * not report as SAVE_RAM. */
  if (!b.len && want_flag == RETRO_MEMDESC_SAVE_RAM) {
    void *legacy = NULL;
    size_t legacy_len = 0;
    if (ezcore_get_legacy_memory(s, RETRO_MEMORY_SAVE_RAM, &legacy,
                                 &legacy_len) && legacy_len <= MAX_SRAM_BYTES) {
      b.data = malloc(legacy_len);
      if (b.data) {
        memcpy(b.data, legacy, legacy_len);
        b.len = legacy_len;
      }
    }
  }
  /* A uniform SRAM region is not proof that gameplay wrote battery memory.
   * Flash save memory is erased to 0xFF and RAM may start zeroed; both are
   * initial states, not a save. Require at least two distinct byte values. */
  if (want_flag == RETRO_MEMDESC_SAVE_RAM && b.len) {
    const unsigned char initial = b.data[0];
    bool varied = false;
    for (size_t i = 1; i < b.len; i++) {
      if (b.data[i] != initial) { varied = true; break; }
    }
    if (!varied) { free(b.data); b.data = NULL; b.len = 0; }
  }
  return b;
}

/* Battery save: run, unload (the runtime calls retro_unload_game, which
 * flushes SRAM), reload the same dump and compare the reloaded save memory. */
static int check_battery(const context_t *ctx, result_t *r) {
  if (!ctx->spec->battery_save) {
    r->battery_verdict = "SKIP";
    return 0;
  }
  int frames = ctx->spec->frames < 120 ? ctx->spec->frames : 120;
  int rc = 0;
  ezcore_session *s = open_session(ctx, &rc);
  if (!s) { r->battery_verdict = "FAIL"; r->battery_reason = "session could not be opened"; return rc; }
  unsigned prev_keys[MAX_KEYS] = {0};
  for (int i = 0; i < frames; i++) {
    apply_input(s, &ctx->input[i], prev_keys);
    ezcore_run_frame(s);
    int16_t sink[AUDIO_BUF_FRAMES * 2];
    ezcore_audio_drain(s, sink, AUDIO_BUF_FRAMES);
  }
  memblob first = collect_memory(s, RETRO_MEMDESC_SAVE_RAM);
  ezcore_unload(s);

  if (!first.len) {
    free(first.data);
    r->battery_verdict = "FAIL";
    r->battery_reason = "core exposes no written battery-backed save memory";
    return 0;
  }
  s = open_session(ctx, &rc);
  if (!s) { free(first.data); r->battery_verdict = "FAIL"; r->battery_reason = "reload failed"; return rc; }
  ezcore_run_frame(s);
  memblob second = collect_memory(s, RETRO_MEMDESC_SAVE_RAM);
  ezcore_unload(s);
  r->battery_bytes = first.len;
  bool same = second.len == first.len && !memcmp(first.data, second.data, first.len);
  r->battery_verdict = same ? "PASS" : "FAIL";
  if (!same) r->battery_reason = "save memory differs after unload and reload";
  free(first.data);
  free(second.data);
  return 0;
}

/* Cheat: apply one code through the runtime cheat API and prove the write
 * changed emulated state by comparing a fixed-index frame with a clean run. */
static int run_cheat_session(const context_t *ctx, bool cheated,
                             char digest[65], bool *memory_written) {
  int rc = 0;
  ezcore_session *s = open_session(ctx, &rc);
  if (!s) return rc;
  if (cheated) {
    ezcore_cheat_reset(s);
    if (!ezcore_cheat_set(s, 0, true, ctx->spec->cheat_code)) {
      ezcore_unload(s);
      return 13;
    }
  }
  memblob before = collect_memory(s, RETRO_MEMDESC_SAVE_RAM | RETRO_MEMDESC_SYSTEM_RAM);
  int frames = ctx->spec->frames < 120 ? ctx->spec->frames : 120;
  int probe = frames / 2;
  unsigned prev_keys[MAX_KEYS] = {0};
  char tmp[65] = {0};
  for (int i = 0; i < frames; i++) {
    apply_input(s, &ctx->input[i], prev_keys);
    ezcore_run_frame(s);
    int16_t sink[AUDIO_BUF_FRAMES * 2];
    ezcore_audio_drain(s, sink, AUDIO_BUF_FRAMES);
    if (i == probe) frame_digest(s, tmp, NULL);
  }
  memblob after = collect_memory(s, RETRO_MEMDESC_SAVE_RAM | RETRO_MEMDESC_SYSTEM_RAM);
  *memory_written = before.len != after.len ||
                    (before.len && memcmp(before.data, after.data, before.len));
  free(before.data);
  free(after.data);
  snprintf(digest, 65, "%s", tmp);
  ezcore_unload(s);
  return 0;
}

static int check_cheat(const context_t *ctx, result_t *r) {
  if (!ctx->spec->cheat) {
    r->cheat_verdict = "SKIP";
    return 0;
  }
  snprintf(r->cheat_code, sizeof(r->cheat_code), "%s", ctx->spec->cheat_code);
  if (!r->cheat_code[0]) {
    r->cheat_verdict = ctx->spec->cheat == 1 ? "SKIP" : "FAIL";
    r->cheat_reason = "no cheat code supplied";
    return 0;
  }
  char clean[65] = {0}, changed[65] = {0};
  bool ignored_before = false, ignored_after = false;
  int rc1 = run_cheat_session(ctx, false, clean, &ignored_before);
  int rc2 = run_cheat_session(ctx, true, changed, &ignored_after);
  if (rc2 == 13) {
    r->cheat_verdict = ctx->spec->cheat == 1 ? "SKIP" : "FAIL";
    r->cheat_reason = "core exposes no cheat interface";
    return 0;
  }
  if (rc1 || rc2) {
    r->cheat_verdict = "FAIL";
    r->cheat_reason = "cheat session failed to run";
    return rc1 ? rc1 : rc2;
  }
  r->cheat_frame_changed = clean[0] && changed[0] && strcmp(clean, changed) != 0;
  r->cheat_memory_written = ignored_after || ignored_before;
  bool proved = r->cheat_frame_changed;
  r->cheat_verdict = proved ? "PASS" :
                    (ctx->spec->cheat == 1 ? "SKIP" : "FAIL");
  if (!proved) r->cheat_reason = "cheat did not change the fixed-index frame";
  return 0;
}

static void compute_verdicts(const spec_t *sp, result_t *r) {
  /* README: every event must change the frame AND both frames around it must
   * clear the colour floor. */
  bool video = true;
  for (int i = 0; i < r->nevents; i++)
    if (!r->events[i].changed || r->events[i].colours_before < sp->min_colours ||
        r->events[i].colours_after < sp->min_colours) video = false;
  r->v_video = !sp->video_changes ? "SKIP" : video ? "PASS" : "FAIL";

  /* README: the floor is met when at least one sampled frame has that many
   * distinct colours; it fails only when EVERY sampled frame is below it. */
  int most_colours = 0;
  for (int i = 0; i < r->ncps; i++)
    if (r->cps[i].colours > most_colours) most_colours = r->cps[i].colours;
  r->v_colours = most_colours >= sp->min_colours ? "PASS" : "FAIL";

  r->v_audio = sp->audio_rms_na ? "SKIP" :
               r->audio_rms >= sp->audio_rms_min ? "PASS" : "FAIL";
  r->v_speed = sp->speed_min > 0 && r->realtime_ratio >= sp->speed_min ? "PASS" :
               sp->speed_min > 0 ? "FAIL" : "SKIP";
  r->v_save = r->save_verdict ? r->save_verdict : "SKIP";
  r->v_battery = r->battery_verdict ? r->battery_verdict : "SKIP";
  if (sp->ff2 <= 0 && sp->ff4 <= 0) r->v_ff = "SKIP";
  else r->v_ff = (!strcmp(ff_verdict(r->ff2, sp->ff2), "PASS") &&
                  !strcmp(ff_verdict(r->ff4, sp->ff4), "PASS")) ? "PASS" : "FAIL";
  r->v_cheat = r->cheat_verdict ? r->cheat_verdict : "SKIP";

  bool fail = false;
  const char *vs[] = {r->v_video, r->v_colours, r->v_audio, r->v_speed,
                      r->v_save, r->v_battery, r->v_ff, r->v_cheat};
  for (size_t i = 0; i < sizeof(vs) / sizeof(vs[0]); i++)
    if (vs[i] && !strcmp(vs[i], "FAIL")) fail = true;
  r->verdict = fail ? "FAIL" : "PASS";
  if (fail && !r->exit_code) r->exit_code = 11;
}

/* ------------------------------------------------------------------ */
/* JSON output. stdout carries the result and nothing else. */
static void jout_string(FILE *o, const char *s) {
  fputc('"', o);
  for (; s && *s; s++) {
    unsigned char c = (unsigned char)*s;
    if (c == '"' || c == '\\') fprintf(o, "\\%c", c);
    else if (c == '\n') fputs("\\n", o);
    else if (c == '\r') fputs("\\r", o);
    else if (c == '\t') fputs("\\t", o);
    else if (c < 0x20) fprintf(o, "\\u%04x", c);
    else fputc(c, o);
  }
  fputc('"', o);
}

static void jout(FILE *o, const char *key, const char *value) {
  jout_string(o, key);
  fputs(": ", o);
  jout_string(o, value);
}

static void print_result(FILE *o, const result_t *r) {
  fputs("{\n  \"schema\": 1, ", o);
  jout(o, "system", r->system);
  fputs(", ", o);
  jout(o, "core", r->core);
  fputs(", ", o);
  jout(o, "core_version", r->version);
  fprintf(o, ",\n  \"frames\": %d, ", r->frames);
  jout(o, "verdict", r->verdict);
  fprintf(o, ",\n  \"exit_code\": %d,\n", r->exit_code);

  fputs("  \"frame_checkpoints\": [", o);
  for (int i = 0; i < r->ncps; i++) {
    fprintf(o, "%s\n    {\"frame\": %d, ", i ? "," : "", r->cps[i].frame);
    jout(o, "sha256", r->cps[i].sha);
    fprintf(o, ", \"colours\": %d}", r->cps[i].colours);
  }
  fputs("\n  ],\n  \"input_events\": [", o);
  for (int i = 0; i < r->nevents; i++) {
    fprintf(o, "%s\n    {\"at\": %d, \"hold\": %d, \"changed\": %s, "
                "\"colours_before\": %d, \"colours_after\": %d}",
            i ? "," : "", r->events[i].at, r->events[i].hold,
            r->events[i].changed ? "true" : "false",
            r->events[i].colours_before, r->events[i].colours_after);
  }
  fprintf(o, "\n  ],\n  \"audio\": {\"total_samples\": %llu, \"rms\": %.8f, "
              "\"longest_silent_run\": %d},\n",
          (unsigned long long)r->audio_samples, r->audio_rms, r->audio_silent);
  fprintf(o, "  \"speed\": {\"unpaced_fps\": %.3f, \"realtime_ratio\": %.4f},\n",
          r->unpaced_fps, r->realtime_ratio);
  fputs("  \"save_state\": {\"verdict\": ", o);
  jout_string(o, r->save_verdict ? r->save_verdict : "SKIP");
  fprintf(o, ", \"size\": %zu, \"frames_compared\": %d, \"mismatches\": %d, \"reason\": ",
          r->save_size, r->save_frames, r->save_mismatches);
  jout_string(o, r->save_reason ? r->save_reason : "");
  fputs("},\n  \"battery_save\": {\"verdict\": ", o);
  jout_string(o, r->battery_verdict ? r->battery_verdict : "SKIP");
  fprintf(o, ", \"bytes\": %zu, \"reason\": ", r->battery_bytes);
  jout_string(o, r->battery_reason ? r->battery_reason : "");
  fputs("},\n  \"cheat\": {\"verdict\": ", o);
  jout_string(o, r->cheat_verdict ? r->cheat_verdict : "SKIP");
  fputs(", \"code\": ", o);
  jout_string(o, r->cheat_code);
  fprintf(o, ", \"memory_written\": %s, \"frame_changed\": %s, \"reason\": ",
          r->cheat_memory_written ? "true" : "false",
          r->cheat_frame_changed ? "true" : "false");
  jout_string(o, r->cheat_reason ? r->cheat_reason : "");
  fprintf(o, "},\n  \"fast_forward\": {\"2x\": %.4f, \"4x\": %.4f, \"verdict\": ",
          r->ff2, r->ff4);
  jout_string(o, r->v_ff ? r->v_ff : "SKIP");
  fputs("},\n  \"checks\": {", o);
  const char *names[] = {"video_changes_after_input", "min_colours", "audio_rms",
                         "speed", "save_state_roundtrip", "battery_save_roundtrip",
                         "fast_forward", "cheat"};
  const char *vals[] = {r->v_video, r->v_colours, r->v_audio, r->v_speed,
                        r->v_save, r->v_battery, r->v_ff, r->v_cheat};
  for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
    fprintf(o, "%s\n    ", i ? "," : "");
    jout(o, names[i], vals[i] ? vals[i] : "SKIP");
  }
  fputs("\n  },\n  \"error\": ", o);
  jout_string(o, r->error);
  fputs("\n}\n", o);
  fflush(o);
}

static int do_work(const context_t *ctx, result_t *r, FILE *out) {
  int rc = run_main_session(ctx, r);
  if (rc == 3 || rc == 10) {
    print_result(out, r);
    return rc;
  }
  if (ctx->spec->speed_min > 0 || ctx->spec->ff2 > 0 || ctx->spec->ff4 > 0) {
    double period = 1e9 / NOMINAL_FPS;
    run_timed(ctx, period, &r->realtime_ratio);
    run_timed(ctx, period / 2, &r->ff2);
    run_timed(ctx, period / 4, &r->ff4);
  }
  check_battery(ctx, r);
  check_cheat(ctx, r);
  compute_verdicts(ctx->spec, r);
  print_result(out, r);
  return r->exit_code;
}

static void usage(void) {
  fprintf(stderr, "usage: ezplay --core <core> --content <dump> --system-dir <dir> "
                  "--save-dir <dir> --spec <json> [--cheat <code>]\n");
}

int main(int argc, char **argv) {
  const char *core = NULL, *content = NULL, *sysdir = NULL, *savedir = NULL,
             *specpath = NULL, *cheat = NULL;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--core") && i + 1 < argc) core = argv[++i];
    else if (!strcmp(argv[i], "--content") && i + 1 < argc) content = argv[++i];
    else if (!strcmp(argv[i], "--system-dir") && i + 1 < argc) sysdir = argv[++i];
    else if (!strcmp(argv[i], "--save-dir") && i + 1 < argc) savedir = argv[++i];
    else if (!strcmp(argv[i], "--spec") && i + 1 < argc) specpath = argv[++i];
    else if (!strcmp(argv[i], "--cheat") && i + 1 < argc) cheat = argv[++i];
    else { usage(); return 10; }
  }
  if (!core || !content || !sysdir || !savedir || !specpath) {
    fprintf(stderr, "ezplay: missing required argument\n");
    usage();
    return 10;
  }

  spec_t sp;
  char err[512];
  if (!parse_spec(specpath, &sp, err, sizeof(err))) {
    fprintf(stderr, "ezplay: %s\n", err);
    return 10;
  }
  if (cheat) snprintf(sp.cheat_code, sizeof(sp.cheat_code), "%s", cheat);

  result_t result;
  memset(&result, 0, sizeof(result));
  snprintf(result.system, sizeof(result.system), "%s", sp.system);
  result.frames = sp.frames;
  result.save_verdict = sp.save_state_na ? "SKIP" : NULL;

  if (!content_matches(sp.system, content)) {
    const char *exts = content_extensions(sp.system);
    char ext[16] = "(none)", accepted[160];
    content_extension(content, ext, sizeof(ext));
    if (!ext[0]) snprintf(ext, sizeof(ext), "(none)");
    describe_extensions(exts ? exts : "", accepted, sizeof(accepted));
    if (exts)
      snprintf(result.error, sizeof(result.error),
               "unsupported content '.%s' for system '%s': expected %s; "
               "provide a compatible dump", ext, sp.system, accepted);
    else
      snprintf(result.error, sizeof(result.error),
               "unsupported content '.%s' for system '%s'", ext, sp.system);
    result.verdict = "FAIL";
    result.exit_code = 12;
    fprintf(stderr, "ezplay: %s\n", result.error);
    print_result(stdout, &result);
    return 12;
  }

  FILE *f = fopen(content, "rb");
  if (!f) {
    fprintf(stderr, "ezplay: cannot open content '%s': %s\n", content, strerror(errno));
    return 1;
  }
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (size <= 0) {
    fclose(f);
    fprintf(stderr, "ezplay: content '%s' is empty\n", content);
    return 2;
  }
  void *data = malloc((size_t)size);
  if (!data) { fclose(f); return 1; }
  if (fread(data, 1, (size_t)size, f) != (size_t)size) {
    free(data); fclose(f); return 1;
  }
  fclose(f);

  ezcore_set_dirs(sysdir, savedir);
  frame_input *input = expand_input(&sp);
  if (!input) { free(data); return 10; }
  context_t ctx = {core, content, data, (size_t)size, &sp, input};

#ifdef _WIN32
  int code = do_work(&ctx, &result, stdout);
  free(input);
  free(data);
  return code;
#else
  int fds[2];
  if (pipe(fds) != 0) { free(input); free(data); return 10; }
  pid_t pid = fork();
  if (pid < 0) { close(fds[0]); close(fds[1]); free(input); free(data); return 10; }
  if (pid == 0) {
    /* Cores frequently log to stdout. Keep the result on a private
     * descriptor and send the core's own writes to stderr, so stdout from
     * the caller is always a single clean JSON document. */
    int jsonfd = dup(fds[1]);
    FILE *json = fdopen(jsonfd, "w");
    close(fds[0]);
    close(fds[1]);
    dup2(STDERR_FILENO, STDOUT_FILENO);
    int code = do_work(&ctx, &result, json ? json : stdout);
    if (json) fclose(json);
    fflush(NULL);
    _exit(code);
  }
  close(fds[1]);
  size_t cap = 65536, used = 0;
  char *buf = malloc(cap);
  if (!buf) { close(fds[0]); waitpid(pid, NULL, 0); free(input); free(data); return 10; }
  for (;;) {
    if (used == cap) {
      cap *= 2;
      char *grow = realloc(buf, cap);
      if (!grow) break;
      buf = grow;
    }
    ssize_t n = read(fds[0], buf + used, cap - used);
    if (n < 0) { if (errno == EINTR) continue; break; }
    if (n == 0) break;
    used += (size_t)n;
  }
  close(fds[0]);
  int status = 0;
  waitpid(pid, &status, 0);
  if (WIFSIGNALED(status)) {
    result.verdict = "FAIL";
    result.exit_code = 9;
    snprintf(result.error, sizeof(result.error), "core crashed with signal %d",
             WTERMSIG(status));
    free(buf); free(input); free(data);
    print_result(stdout, &result);
    return 9;
  }
  fwrite(buf, 1, used, stdout);
  fflush(stdout);
  int code = WIFEXITED(status) ? WEXITSTATUS(status) : 1;
  free(buf); free(input); free(data);
  return code;
#endif
}

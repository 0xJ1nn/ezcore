// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* test_engine_host.c — failing-first proof of the GENERIC engine host.
 *
 * The question: can a NON-libretro engine satisfy the exact same wire
 * protocol as ezcore_core_host, selected by data (--engine=synthetic), with
 * no change to any op? This harness speaks the protocol as the app does and
 * checks, against the synthetic Tier-2 engine:
 *
 *   1. the host process launches with --engine=synthetic and opens a
 *      synthetic "content" id (no ROM, no file on disk);
 *   2. deterministic frames are produced, with real RGBA and PCM;
 *   3. a BUTTON reaches the engine and changes its rendered frame;
 *   4. SAVE / RESTORE round-trips byte-identically;
 *   5. an engine fault (EZCORE_CRASH_AFTER) kills only the host process;
 *      this harness observes the signal and carries on (containment);
 *   6. an external kill of the engine process is likewise reported as a
 *      crash while this process survives.
 *
 * POSIX-only (fork/exec/waitpid). Exit 0 pass, 1 a check failed, 9 usage.
 */
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#include "../host/ezcore_core_host_protocol.h"

#define CHECK(cond, msg)                                                       \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, "FAIL: %s\n", msg);                                      \
      return 1;                                                                \
    }                                                                          \
    printf("ok: %s\n", msg);                                                    \
  } while (0)

typedef struct {
  pid_t pid;
  int to_host;
  int from_host;
} host_t;

static int spawn_host(const char *host_path, const char *engine,
                      const char *crash_after, host_t *h) {
  int in[2], out[2];
  if (pipe(in) || pipe(out)) return -1;
  pid_t pid = fork();
  if (pid < 0) return -1;
  if (pid == 0) {
    dup2(in[0], 0);
    dup2(out[1], 1);
    close(in[0]); close(in[1]); close(out[0]); close(out[1]);
    if (crash_after) setenv("EZCORE_CRASH_AFTER", crash_after, 1);
    else unsetenv("EZCORE_CRASH_AFTER");
    execl(host_path, host_path, "--engine=synthetic", (char *)NULL);
    _exit(127);
  }
  close(in[0]);
  close(out[1]);
  h->pid = pid;
  h->to_host = in[1];
  h->from_host = out[0];
  return 0;
}

/* ---- little-endian wire helpers ---- */

typedef struct {
  uint8_t buf[1 << 16];
  size_t len;
} msg_t;

static void put_u8(msg_t *m, uint8_t v) { m->buf[m->len++] = v; }
static void put_u32(msg_t *m, uint32_t v) {
  for (int i = 0; i < 4; i++) m->buf[m->len++] = (uint8_t)(v >> (8 * i));
}
static void put_str(msg_t *m, const char *s) {
  uint32_t n = (uint32_t)strlen(s);
  put_u32(m, n);
  memcpy(m->buf + m->len, s, n);
  m->len += n;
}

static int write_all(int fd, const void *p, size_t n) {
  const uint8_t *b = p;
  while (n) {
    ssize_t w = write(fd, b, n);
    if (w < 0 && errno == EINTR) continue;
    if (w <= 0) return -1;
    b += w; n -= (size_t)w;
  }
  return 0;
}
static int read_all(int fd, void *p, size_t n) {
  uint8_t *b = p;
  while (n) {
    ssize_t r = read(fd, b, n);
    if (r < 0 && errno == EINTR) continue;
    if (r <= 0) return -1; /* EOF: the host is gone */
    b += r; n -= (size_t)r;
  }
  return 0;
}
static uint32_t get_u32(const uint8_t *p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
}

/* Returns status byte, or -1 if the host died before answering. */
static int call(host_t *h, const msg_t *req, uint8_t **resp, uint32_t *len) {
  uint8_t hdr[4];
  uint32_t n = (uint32_t)req->len;
  for (int i = 0; i < 4; i++) hdr[i] = (uint8_t)(n >> (8 * i));
  if (write_all(h->to_host, hdr, 4) || write_all(h->to_host, req->buf, n))
    return -1;
  if (read_all(h->from_host, hdr, 4)) return -1;
  uint32_t rn = get_u32(hdr);
  if (rn == 0) return -1;
  uint8_t *body = malloc(rn);
  if (!body || read_all(h->from_host, body, rn)) { free(body); return -1; }
  *resp = body;
  *len = rn;
  return body[0];
}

static int open_engine(host_t *h, uint8_t **resp, uint32_t *len) {
  msg_t m = {.len = 0};
  put_u8(&m, EZH_OP_OPEN);
  put_str(&m, "synthetic://tier2-proof"); /* engine-specific content id */
  put_str(&m, "/dev/null");                /* no content file — no ROM */
  put_str(&m, ".");
  put_str(&m, ".");
  put_u32(&m, 0);
  return call(h, &m, resp, len);
}

/* FNV-1a over a frame's RGBA, so a pattern change is one integer compare. */
static uint32_t frame_hash(const uint8_t *rgba, uint32_t n) {
  uint32_t h = 2166136261u;
  for (uint32_t i = 0; i < n; i++) { h ^= rgba[i]; h *= 16777619u; }
  return h;
}

static int get_frame(host_t *h, uint32_t *out_hash, uint32_t *out_pcm) {
  msg_t m = {.len = 0};
  put_u8(&m, EZH_OP_FRAME);
  put_u32(&m, 1);
  uint8_t *r = NULL;
  uint32_t n = 0;
  if (call(h, &m, &r, &n) != EZH_OK || n < 15 || r[1] != 1) { free(r); return 0; }
  uint32_t w = get_u32(r + 2), hgt = get_u32(r + 6), rgba = get_u32(r + 10);
  if (w != 256 || hgt != 240 || rgba != w * hgt * 4 ||
      n < 15 + rgba + 4) { free(r); return 0; }
  *out_hash = frame_hash(r + 15, rgba);
  *out_pcm = get_u32(r + 15 + rgba);
  free(r);
  return 1;
}

/* SAVE state bytes (malloc'd), length in *len. NULL on error. */
static uint8_t *do_save(host_t *h, uint32_t *len) {
  msg_t m = {.len = 0};
  put_u8(&m, EZH_OP_SAVE);
  uint8_t *r = NULL;
  uint32_t n = 0;
  if (call(h, &m, &r, &n) != EZH_OK || n < 5) { free(r); return 0; }
  uint32_t sl = get_u32(r + 1);
  if (sl == 0 || n != 1 + 4 + sl) { free(r); return 0; }
  uint8_t *state = malloc(sl);
  memcpy(state, r + 5, sl);
  *len = sl;
  free(r);
  return state;
}

static int do_restore(host_t *h, const uint8_t *state, uint32_t len) {
  msg_t m = {.len = 0};
  put_u8(&m, EZH_OP_RESTORE);
  put_u32(&m, len);
  memcpy(m.buf + m.len, state, len);
  m.len += len;
  uint8_t *r = NULL;
  uint32_t n = 0;
  int st = call(h, &m, &r, &n);
  free(r);
  return st == EZH_OK;
}

static int send_button(host_t *h, uint32_t id, uint8_t pressed) {
  msg_t m = {.len = 0};
  put_u8(&m, EZH_OP_BUTTON);
  put_u32(&m, 0); put_u32(&m, id); put_u8(&m, pressed);
  uint8_t *r = NULL; uint32_t n = 0;
  int st = call(h, &m, &r, &n);
  free(r);
  return st == EZH_OK;
}

static int test_engine_end_to_end(const char *host) {
  host_t h;
  CHECK(spawn_host(host, "synthetic", NULL, &h) == 0,
        "engine host launched with --engine=synthetic");
  uint8_t *r = NULL; uint32_t n = 0;
  CHECK(open_engine(&h, &r, &n) == EZH_OK, "synthetic content opened");
  CHECK(n > 1 && get_u32(r + 1) > 0, "engine reported a name");
  free(r);

  uint32_t hash_a = 0, pcm = 0;
  CHECK(get_frame(&h, &hash_a, &pcm), "frame produced with 256x240 RGBA");
  CHECK(pcm > 0, "PCM came back with the frame");

  uint32_t state_len = 0;
  uint8_t *s1 = do_save(&h, &state_len);
  CHECK(s1 != NULL, "save state captured");

  CHECK(send_button(&h, 0, 1), "BUTTON forwarded to the engine");
  uint32_t hash_b = 0;
  CHECK(get_frame(&h, &hash_b, &pcm), "frame after BUTTON produced");
  CHECK(hash_b != hash_a, "BUTTON changed the rendered frame");

  uint8_t *s2 = do_save(&h, &state_len);
  CHECK(s2 != NULL && memcmp(s1, s2, state_len) != 0,
        "BUTTON reached engine state (saved bytes changed)");

  CHECK(do_restore(&h, s1, state_len), "RESTORE accepted the earlier state");
  uint8_t *s3 = do_save(&h, &state_len);
  CHECK(s3 != NULL && memcmp(s1, s3, state_len) == 0,
        "SAVE/RESTORE round-trips byte-identically");
  uint32_t hash_c = 0;
  CHECK(get_frame(&h, &hash_c, &pcm), "frame after RESTORE produced");
  CHECK(hash_c == hash_a, "RESTORE restored the pre-BUTTON rendered pattern");

  free(s1); free(s2); free(s3);

  msg_t req_close = {.len = 0};
  put_u8(&req_close, EZH_OP_CLOSE);
  r = NULL; n = 0;
  CHECK(call(&h, &req_close, &r, &n) == EZH_OK, "CLOSE acknowledged");
  free(r);
  int status = 0;
  waitpid(h.pid, &status, 0);
  CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0, "host exits 0 on CLOSE");
  close(h.to_host); close(h.from_host);
  return 0;
}

static int test_engine_crash_contained(const char *host) {
  host_t h;
  CHECK(spawn_host(host, "synthetic", "2", &h) == 0,
        "engine host launched with crash-after set");
  uint8_t *r = NULL; uint32_t n = 0;
  CHECK(open_engine(&h, &r, &n) == EZH_OK, "crashing engine opens cleanly");
  free(r);
  uint32_t hash = 0, pcm = 0;
  CHECK(get_frame(&h, &hash, &pcm), "first frame before the fault");

  int died = 0;
  for (int i = 0; i < 6; i++) {
    uint32_t h2 = 0, p2 = 0;
    if (!get_frame(&h, &h2, &p2)) { died = i + 1; break; }
  }
  CHECK(died == 1, "engine faulted on the expected frame");
  int status = 0;
  waitpid(h.pid, &status, 0);
  CHECK(WIFSIGNALED(status), "engine/host death is a signal death");
  printf("ok: this process is still running after the engine crashed\n");
  close(h.to_host); close(h.from_host);
  return 0;
}

static int test_external_kill_contained(const char *host) {
  host_t h;
  CHECK(spawn_host(host, "synthetic", NULL, &h) == 0,
        "engine host launched for external-kill check");
  uint8_t *r = NULL; uint32_t n = 0;
  CHECK(open_engine(&h, &r, &n) == EZH_OK, "engine opened before kill");
  free(r);
  kill(h.pid, SIGKILL);
  int status = 0;
  waitpid(h.pid, &status, 0);
  CHECK(WIFSIGNALED(status),
        "a killed engine process is reported as a crash, not a clean exit");
  printf("ok: this process survived an external engine kill\n");
  close(h.to_host); close(h.from_host);
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: test_engine_host <host-binary>\n");
    return 9;
  }
  signal(SIGPIPE, SIG_IGN); /* a dead host must surface as EOF, not kill us */
  if (test_engine_end_to_end(argv[1])) return 1;
  if (test_engine_crash_contained(argv[1])) return 1;
  if (test_external_kill_contained(argv[1])) return 1;
  printf("PASS\n");
  return 0;
}

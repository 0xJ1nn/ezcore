/* test_core_host.c — drives ezcore_core_host over its pipe protocol (P6).
 *
 * The question this answers is the one ADR-015 exists for: when a core
 * crashes, does only the process hosting it die? The test spawns the host as
 * a child, talks to it exactly as the app will (length-prefixed frames on its
 * stdin/stdout), and checks three things:
 *
 *   1. A well-behaved core (synth) works end to end through the protocol:
 *      open, frames with real pixels and audio, a held button, save/restore,
 *      option read-back, and a clean close (exit 0).
 *   2. A core that faults mid-frame (crash_libretro, EZCORE_CRASH_AFTER=3)
 *      kills the HOST, which this process observes as EOF on the pipe and a
 *      signal death from waitpid -- while this process carries on. That
 *      survival is the containment property.
 *   3. If the app goes away (its end of the pipe closes) the host exits by
 *      itself instead of lingering as an orphan.
 *
 * POSIX-only (fork/exec/waitpid). Exit: 0 pass, 1 a check failed, 9 usage.
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
    } else {                                                                   \
      printf("ok: %s\n", msg);                                                 \
    }                                                                          \
  } while (0)

typedef struct {
  pid_t pid;
  int to_host;   /* write end: the host's stdin */
  int from_host; /* read end: the host's protocol output */
} host_t;

static int spawn_host(const char *host_path, const char *crash_after,
                      host_t *h) {
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
    execl(host_path, host_path, (char *)NULL);
    _exit(127);
  }
  close(in[0]);
  close(out[1]);
  h->pid = pid;
  h->to_host = in[1];
  h->from_host = out[0];
  return 0;
}

/* ---- tiny little-endian message builder / reader ---- */

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

/* Sends one request; reads one response into *resp (malloc'd, caller frees).
 * Returns the status byte, or -1 if the host died before answering. */
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

static int open_core(host_t *h, const char *core, uint8_t **resp,
                     uint32_t *len) {
  msg_t m = {.len = 0};
  put_u8(&m, EZH_OP_OPEN);
  put_str(&m, core);
  put_str(&m, "/dev/null"); /* content: synthetic cores need none */
  put_str(&m, ".");
  put_str(&m, ".");
  put_u32(&m, 0); /* no options */
  return call(h, &m, resp, len);
}

static int test_good_core(const char *host, const char *synth) {
  host_t h;
  CHECK(spawn_host(host, NULL, &h) == 0, "host spawned");
  uint8_t *r = NULL;
  uint32_t n = 0;

  CHECK(open_core(&h, synth, &r, &n) == EZH_OK, "open synth core");
  free(r);

  msg_t m = {.len = 0};
  put_u8(&m, EZH_OP_FRAME);
  put_u32(&m, 1);
  CHECK(call(&h, &m, &r, &n) == EZH_OK, "frame request answered");
  CHECK(n >= 1 + 1 + 4 + 4 + 4 && r[1] == 1, "a frame came back");
  uint32_t w = get_u32(r + 2), hgt = get_u32(r + 6), rgba = get_u32(r + 10);
  CHECK(w == 256 && hgt == 240, "geometry is the synth core's 256x240");
  CHECK(rgba == w * hgt * 4, "rgba payload is width*height*4 bytes");
  uint32_t pcm = get_u32(r + 14 + rgba);
  CHECK(pcm > 0, "audio came back with the frame");
  free(r);

  m.len = 0;
  put_u8(&m, EZH_OP_BUTTON);
  put_u32(&m, 0); put_u32(&m, 0); put_u8(&m, 1);
  CHECK(call(&h, &m, &r, &n) == EZH_OK, "button accepted");
  free(r);

  m.len = 0;
  put_u8(&m, EZH_OP_SAVE);
  CHECK(call(&h, &m, &r, &n) == EZH_OK, "save state taken");
  uint32_t state_len = get_u32(r + 1);
  CHECK(state_len > 0 && n == 1 + 4 + state_len, "state bytes returned");
  msg_t rs = {.len = 0};
  put_u8(&rs, EZH_OP_RESTORE);
  put_u32(&rs, state_len);
  memcpy(rs.buf + rs.len, r + 5, state_len);
  rs.len += state_len;
  free(r);
  CHECK(call(&h, &rs, &r, &n) == EZH_OK, "state restored");
  free(r);

  m.len = 0;
  put_u8(&m, EZH_OP_OPTIONS);
  CHECK(call(&h, &m, &r, &n) == EZH_OK, "options read back");
  free(r);

  m.len = 0;
  put_u8(&m, EZH_OP_BOGUS_FOR_TEST);
  CHECK(call(&h, &m, &r, &n) == EZH_ERROR, "unknown op is an error, not a crash");
  free(r);

  m.len = 0;
  put_u8(&m, EZH_OP_CLOSE);
  CHECK(call(&h, &m, &r, &n) == EZH_OK, "close acknowledged");
  free(r);
  int status = 0;
  waitpid(h.pid, &status, 0);
  CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0, "host exits 0 on close");
  close(h.to_host);
  close(h.from_host);
  return 0;
}

static int test_crashing_core(const char *host, const char *crash) {
  host_t h;
  CHECK(spawn_host(host, "3", &h) == 0, "host spawned for crash core");
  uint8_t *r = NULL;
  uint32_t n = 0;
  CHECK(open_core(&h, crash, &r, &n) == EZH_OK, "crash core opens cleanly");
  free(r);

  int died_at = 0;
  for (int i = 1; i <= 10; i++) {
    msg_t m = {.len = 0};
    put_u8(&m, EZH_OP_FRAME);
    put_u32(&m, 1);
    int st = call(&h, &m, &r, &n);
    if (st < 0) { died_at = i; break; }
    free(r);
  }
  CHECK(died_at == 3, "host died on exactly the frame the core faults");
  int status = 0;
  waitpid(h.pid, &status, 0);
  CHECK(WIFSIGNALED(status), "host death is a signal death");
  CHECK(WTERMSIG(status) == SIGSEGV, "the signal is the core's SIGSEGV");
  printf("ok: this process is still running after the core crashed\n");
  close(h.to_host);
  close(h.from_host);
  return 0;
}

static int test_parent_gone(const char *host, const char *synth) {
  host_t h;
  CHECK(spawn_host(host, NULL, &h) == 0, "host spawned for orphan check");
  uint8_t *r = NULL;
  uint32_t n = 0;
  CHECK(open_core(&h, synth, &r, &n) == EZH_OK, "open before parent leaves");
  free(r);
  close(h.to_host); /* the app vanished */
  int status = 0;
  waitpid(h.pid, &status, 0);
  CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0,
        "host exits cleanly when its input closes");
  close(h.from_host);
  return 0;
}

int main(int argc, char **argv) {
  if (argc < 4) {
    fprintf(stderr, "usage: test_core_host <host> <synth_core> <crash_core>\n");
    return 9;
  }
  signal(SIGPIPE, SIG_IGN); /* a dead host must surface as EOF, not kill us */
  if (test_good_core(argv[1], argv[2])) return 1;
  if (test_crashing_core(argv[1], argv[3])) return 1;
  if (test_parent_gone(argv[1], argv[2])) return 1;
  printf("PASS\n");
  return 0;
}

/* probe3: probe2 + the bridge's exact callback set. Bisects the mGBA
 * segfault down to a specific callback or setter call. */
#include <dlfcn.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "libretro.h"

#define STEP(name, expr)                          \
  do {                                            \
    printf("step: %s\n", name);                   \
    fflush(stdout);                               \
    expr;                                         \
    printf("ok: %s\n", name);                     \
    fflush(stdout);                               \
  } while (0)

static enum retro_pixel_format g_fmt = RETRO_PIXEL_FORMAT_0RGB1555;

static void bridge_log(enum retro_log_level level, const char *fmt, ...) {
  (void)level;
  va_list args;
  va_start(args, fmt);
  vfprintf(stderr, fmt, args);
  va_end(args);
}

static bool env_cb(unsigned cmd, void *data) {
  switch (cmd) {
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
      enum retro_pixel_format fmt = *(const enum retro_pixel_format *)data;
      if (fmt != RETRO_PIXEL_FORMAT_0RGB1555 &&
          fmt != RETRO_PIXEL_FORMAT_XRGB8888 &&
          fmt != RETRO_PIXEL_FORMAT_RGB565) {
        return false;
      }
      g_fmt = fmt;
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

static void video_cb(const void *d, unsigned w, unsigned h, size_t p) {
  (void)d;
  (void)w;
  (void)h;
  (void)p;
}
static void audio_cb(int16_t l, int16_t r) {
  (void)l;
  (void)r;
}
static size_t audio_batch_cb(const int16_t *d, size_t f) {
  (void)d;
  return f;
}
static void poll_cb(void) {}
static int16_t state_cb(unsigned a, unsigned b, unsigned c, unsigned d) {
  (void)a;
  (void)b;
  (void)c;
  (void)d;
  return 0;
}

int main(int argc, char **argv) {
  void *h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  printf("dlopen=%p\n", h);
  fflush(stdout);
  if (!h) return 1;
  void (*init)(void);
  STEP("setenv", ((void (*)(bool (*)(unsigned, void *)))dlsym(
                      h, "retro_set_environment"))(env_cb));
  STEP("setvideo", ((void (*)(retro_video_refresh_t))dlsym(
                        h, "retro_set_video_refresh"))(video_cb));
  STEP("setaudio", ((void (*)(retro_audio_sample_t))dlsym(
                        h, "retro_set_audio_sample"))(audio_cb));
  STEP("setaudiobatch", ((void (*)(retro_audio_sample_batch_t))dlsym(
                             h, "retro_set_audio_sample_batch"))(
                             audio_batch_cb));
  STEP("setpoll", ((void (*)(retro_input_poll_t))dlsym(
                       h, "retro_set_input_poll"))(poll_cb));
  STEP("setstate", ((void (*)(retro_input_state_t))dlsym(
                        h, "retro_set_input_state"))(state_cb));
  STEP("dlsym init", init = dlsym(h, "retro_init"));
  STEP("call init", init());
  printf("ALL DONE fmt=%d\n", (int)g_fmt);
  return 0;
}

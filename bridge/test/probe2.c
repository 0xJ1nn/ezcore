/* Replicates huh_load step by step with checkpoints. */
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>

#include "libretro.h"

static bool env_cb(unsigned cmd, void *data) {
  (void)cmd;
  (void)data;
  return false;
}
static void video_cb(const void *d, unsigned w, unsigned h, size_t p) {
  (void)d;
  (void)w;
  (void)h;
  (void)p;
}

#define STEP(name, expr)                         \
  do {                                           \
    printf("step: %s\n", name);                  \
    fflush(stdout);                              \
    expr;                                        \
    printf("ok: %s\n", name);                    \
    fflush(stdout);                              \
  } while (0)

int main(int argc, char **argv) {
  void *h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  printf("dlopen=%p\n", h);
  if (!h) return 1;

  unsigned (*api)(void);
  void (*getinfo)(struct retro_system_info *);
  void (*init)(void);
  STEP("dlsym api", api = dlsym(h, "retro_api_version"));
  STEP("call api", printf("ver=%u\n", api()));
  STEP("dlsym getinfo", getinfo = dlsym(h, "retro_get_system_info"));
  STEP("call getinfo", {
    struct retro_system_info info = {0};
    getinfo(&info);
    printf("name=%s ver=%s exts=%s\n", info.library_name,
           info.library_version, info.valid_extensions);
  });
  void (*setenv)(bool (*)(unsigned, void *));
  void (*setvideo)(void (*)(const void *, unsigned, unsigned, size_t));
  STEP("dlsym setters", {
    setenv = dlsym(h, "retro_set_environment");
    setvideo = dlsym(h, "retro_set_video_refresh");
  });
  STEP("call setenv", setenv(env_cb));
  STEP("call setvideo", setvideo(video_cb));
  STEP("dlsym init", init = dlsym(h, "retro_init"));
  STEP("call init", init());
  printf("ALL DONE\n");
  return 0;
}

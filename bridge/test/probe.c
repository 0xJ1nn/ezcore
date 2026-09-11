/* Bisect probe: dlopen a core and call entry points one at a time. */
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>

static bool env_cb(unsigned cmd, void *data) {
  (void)cmd;
  (void)data;
  return false;
}

int main(int argc, char **argv) {
  void *h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  printf("dlopen=%p err=%s\n", h, h ? "-" : dlerror());
  if (!h) return 1;
  unsigned (*api)(void) = dlsym(h, "retro_api_version");
  printf("api=%p\n", (void *)api);
  if (api) printf("api_version=%u\n", api());
  void *getinfo = dlsym(h, "retro_get_system_info");
  printf("getinfo=%p\n", getinfo);
  void (*setenv)(bool (*)(unsigned, void *)) =
      dlsym(h, "retro_set_environment");
  printf("setenv=%p\n", (void *)setenv);
  if (setenv) {
    setenv(env_cb);
    printf("setenv called\n");
  }
  void (*init)(void) = dlsym(h, "retro_init");
  printf("init=%p -- calling\n", (void *)init);
  fflush(stdout);
  if (init) init();
  printf("init returned\n");
  return 0;
}

/* probe4: is retro_deinit (no game ever loaded) the crasher? */
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
  printf("dlopen=%p\n", h);
  fflush(stdout);
  if (!h) return 1;
  void (*setenv)(bool (*)(unsigned, void *)) =
      dlsym(h, "retro_set_environment");
  if (setenv) setenv(env_cb);
  void (*init)(void) = dlsym(h, "retro_init");
  printf("calling init\n");
  fflush(stdout);
  if (init) init();
  printf("init ok; calling deinit\n");
  fflush(stdout);
  void (*deinit)(void) = dlsym(h, "retro_deinit");
  if (deinit) deinit();
  printf("deinit ok; dlclose\n");
  fflush(stdout);
  dlclose(h);
  printf("ALL DONE\n");
  return 0;
}

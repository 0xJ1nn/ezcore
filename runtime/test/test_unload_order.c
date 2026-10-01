/* test_unload_order.c — libretro teardown order (and that it happens).
 *
 * libretro's order is: retro_unload_game, then the frontend calls the core's
 * hw context_destroy while the context still exists, then retro_deinit, and
 * only then is the context destroyed. The runtime used to destroy the
 * context first, null out the core's context_destroy instead of calling it,
 * and never call retro_unload_game at all -- so cores could not flush battery
 * saves or caches, and Mupen64Plus-Next crashed writing its shader cache
 * into a dead context.
 *
 * synth_hw_core appends each step to EZCORE_SYNTH_ORDER_FILE; this test reads
 * the order back after unload. Skips without a GPU context.
 * Exit: 0 pass/skip, 1 fail, 9 usage. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ezcore_runtime.h"

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "usage: test_unload_order <core> <tmpfile>\n"); return 9; }
  remove(argv[2]);
  setenv("EZCORE_SYNTH_ORDER_FILE", argv[2], 1);
  char err[256] = {0};
  ezcore_session *s = ezcore_load(argv[1], err, sizeof(err));
  if (!s || !ezcore_init(s)) { fprintf(stderr, "FAIL: load/init\n"); return 1; }
  if (!ezcore_load_game(s, "x.probe", "x", 1)) {
    printf("skip: no GPU context on this host\n");
    ezcore_unload(s);
    return 0;
  }
  ezcore_run_frame(s);
  ezcore_unload(s);

  char got[256] = {0};
  FILE *f = fopen(argv[2], "r");
  if (f) {
    size_t n = fread(got, 1, sizeof(got) - 1, f);
    got[n] = 0;
    fclose(f);
  }
  const char *want = "unload_game\ncontext_destroy\ndeinit\n";
  printf("order seen by the core:\n%s", got);
  if (strcmp(got, want) != 0) {
    fprintf(stderr, "FAIL: expected unload_game, context_destroy, deinit\n");
    return 1;
  }
  printf("ok: unload_game, then context_destroy, then deinit\nPASS\n");
  return 0;
}

/* test_unload_order.c — libretro teardown order (and that it happens).
 *
 * The order, as RetroArch's core_unload_game does it (cores are written
 * against it): the core's hw context_destroy while the context still exists,
 * then retro_unload_game, then retro_deinit, and only then is the context
 * destroyed. PPSSPP deletes its graphics context object in retro_unload_game,
 * so calling context_destroy after it crashed. Before that the runtime
 * destroyed the context first, nulled out context_destroy instead of calling
 * it, and never called retro_unload_game -- so cores could not flush battery
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
  const char *want = "context_destroy\nunload_game\ndeinit\n";
  printf("order seen by the core:\n%s", got);
  if (strcmp(got, want) != 0) {
    fprintf(stderr, "FAIL: expected context_destroy, unload_game, deinit\n");
    return 1;
  }
  printf("ok: context_destroy, then unload_game, then deinit\n");

  /* A core that asked for a context but failed its load was never given
   * that context (context_reset), so it must not be told to destroy it. */
  remove(argv[2]);
  setenv("EZCORE_SYNTH_FAIL_LOAD", "1", 1);
  s = ezcore_load(argv[1], err, sizeof(err));
  if (!s || !ezcore_init(s)) { fprintf(stderr, "FAIL: reload/init\n"); return 1; }
  if (ezcore_load_game(s, "x.probe", "x", 1)) {
    fprintf(stderr, "FAIL: the failing-load hook did not fail\n");
    return 1;
  }
  ezcore_unload(s);
  memset(got, 0, sizeof(got));
  f = fopen(argv[2], "r");
  if (f) {
    size_t n = fread(got, 1, sizeof(got) - 1, f);
    got[n] = 0;
    fclose(f);
  }
  printf("after a failed load the core saw:\n%s", got);
  if (strcmp(got, "deinit\n") != 0) {
    fprintf(stderr, "FAIL: a core whose load failed got more than deinit\n");
    return 1;
  }
  printf("ok: a failed load is not told to destroy a context it never had\nPASS\n");
  return 0;
}

/* Regression test: a libretro core may omit optional cheat entry points. */
#include <stdbool.h>
#include <stdio.h>

#include "ezcore_runtime.h"

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: test_optional_cheats <core-library>\n");
    return 2;
  }

  char err[1024] = {0};
  ezcore_session *session = ezcore_load(argv[1], err, sizeof(err));
  if (!session) {
    fprintf(stderr, "core without cheat symbols failed to load: %s\n", err);
    return 1;
  }

  if (!ezcore_init(session)) {
    fprintf(stderr, "init failed\n");
    ezcore_unload(session);
    return 1;
  }

  /* Both calls must be safe when the core does not export the symbols. */
  ezcore_cheat_reset(session);
  if (ezcore_cheat_set(session, 0, true, "0101ABCD")) {
    fprintf(stderr, "unsupported cheat set unexpectedly succeeded\n");
    ezcore_unload(session);
    return 1;
  }

  ezcore_unload(session);
  return 0;
}

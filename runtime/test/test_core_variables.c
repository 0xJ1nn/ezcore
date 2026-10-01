/* test_core_variables.c — regression test: core option values must reach
 * the core.
 *
 * Bug: the runtime stored the options a core declared (SET_CORE_OPTIONS_V2)
 * and let the host change them (ezcore_set_core_option), but env_cb never
 * answered RETRO_ENVIRONMENT_GET_VARIABLE or GET_VARIABLE_UPDATE. Those are
 * the only two ways a libretro core reads an option, so every core ran on
 * its built-in defaults no matter what the user picked in Settings, and the
 * host-side store looked correct while doing nothing.
 *
 * This test observes the core's own view (synth_variables_core.c echoes it
 * into the audio stream) instead of reading the runtime's stored copy back,
 * because reading the copy back is exactly the check that passed while the
 * bug was live.
 *
 * Exit: 0 = pass, 1 = a check failed, 9 = usage.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ezcore_runtime.h"

#define SEEN_NO_ANSWER ((int16_t)0x2000)
#define SEEN_A ((int16_t)0x2001)
#define SEEN_B ((int16_t)0x2002)
#define NOT_UPDATED ((int16_t)0x3000)
#define UPDATED ((int16_t)0x3001)

#define CHECK(cond, msg)                                                       \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, "FAIL: %s\n", msg);                                      \
      return 1;                                                                \
    } else {                                                                   \
      printf("ok: %s\n", msg);                                                 \
    }                                                                          \
  } while (0)

/* Runs one frame; returns its first stereo frame (value, update flag). */
static void run_frame(ezcore_session *s, int16_t *value, int16_t *update) {
  int16_t buf[4096];
  while (ezcore_audio_pending(s) > 0) ezcore_audio_drain(s, buf, 2048);
  ezcore_run_frame(s);
  memset(buf, 0, sizeof(buf));
  size_t got = ezcore_audio_drain(s, buf, 2048);
  *value = got ? buf[0] : 0;
  *update = got ? buf[1] : 0;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: test_core_variables <synth_variables_core>\n");
    return 9;
  }
  char err[1024] = {0};
  ezcore_session *s = ezcore_load(argv[1], err, sizeof(err));
  CHECK(s != NULL, "variables core loaded");
  CHECK(ezcore_init(s), "init ok");
  CHECK(ezcore_load_game(s, "/dev/null", NULL, 0), "load_game ok");
  CHECK(ezcore_get_core_option_count(s) == 1, "core declared one option");

  int16_t value = 0, update = 0;

  /* 1. Before the host touches anything the core must see its default. */
  run_frame(s, &value, &update);
  CHECK(value != SEEN_NO_ANSWER, "GET_VARIABLE is answered");
  CHECK(value == SEEN_A, "core sees its default value 'a'");
  CHECK(update == NOT_UPDATED, "no update reported before any change");

  /* 2. The host changes the option: the next frame reports exactly one
   *    update and the core re-reads the new value. */
  CHECK(ezcore_set_core_option(s, "synth_mode", "b"), "host sets 'b'");
  run_frame(s, &value, &update);
  CHECK(update == UPDATED, "GET_VARIABLE_UPDATE reports the change");
  CHECK(value == SEEN_B, "core sees the host's value 'b'");

  /* 3. The update flag is consumed by reading it: it must not stay raised,
   *    or a core would re-apply its options (often a full reconfigure)
   *    every single frame. */
  run_frame(s, &value, &update);
  CHECK(update == NOT_UPDATED, "update flag clears after being read");
  CHECK(value == SEEN_B, "value persists across frames");

  /* 4. Setting the same value again is not a change. */
  CHECK(ezcore_set_core_option(s, "synth_mode", "b"), "host re-sets 'b'");
  run_frame(s, &value, &update);
  CHECK(update == NOT_UPDATED, "re-setting the current value is not an update");

  /* 5. An unknown key changes nothing and raises no update. */
  CHECK(!ezcore_set_core_option(s, "no_such_key", "x"), "unknown key refused");
  run_frame(s, &value, &update);
  CHECK(update == NOT_UPDATED, "a refused set raises no update");

  ezcore_unload(s);
  printf("PASS\n");
  return 0;
}

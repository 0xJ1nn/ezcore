/* test_input_devices.c — analog, mouse, keyboard and pointer reach a core
 * (P3). Drives synth_input_core.c, which echoes what it read through audio,
 * so every check is the core's own view.
 * Exit: 0 pass, 1 a check failed, 9 usage. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "libretro.h"
#include "ezcore_runtime.h"

#define CHECK(cond, msg)                                                       \
  do {                                                                         \
    if (!(cond)) { fprintf(stderr, "FAIL: %s\n", msg); return 1; }             \
    printf("ok: %s\n", msg);                                                   \
  } while (0)

static int16_t v[16];

static void frame(ezcore_session *s) {
  int16_t buf[4096];
  while (ezcore_audio_pending(s) > 0) ezcore_audio_drain(s, buf, 2048);
  ezcore_run_frame(s);
  memset(v, 0, sizeof(v));
  size_t got = ezcore_audio_drain(s, buf, 2048);
  if (got >= 8) memcpy(v, buf, sizeof(v));
}

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: test_input_devices <core>\n"); return 9; }
  char err[512] = {0};
  ezcore_session *s = ezcore_load(argv[1], err, sizeof(err));
  CHECK(s != NULL, "input core loaded");
  CHECK(ezcore_init(s), "init");
  CHECK(ezcore_load_game(s, "/dev/null", NULL, 0), "load_game");

  frame(s);
  CHECK(v[15] == 1, "GET_INPUT_BITMASKS is answered");
  CHECK(v[0] == 0 && v[1] == 0 && v[4] == 0 && v[7] == 0 && v[10] == 0,
        "everything idle at start");

  /* Analog sticks, per port and per stick. */
  ezcore_set_analog(s, 0, RETRO_DEVICE_INDEX_ANALOG_LEFT, RETRO_DEVICE_ID_ANALOG_X, 12000);
  ezcore_set_analog(s, 0, RETRO_DEVICE_INDEX_ANALOG_LEFT, RETRO_DEVICE_ID_ANALOG_Y, -32767);
  ezcore_set_analog(s, 1, RETRO_DEVICE_INDEX_ANALOG_RIGHT, RETRO_DEVICE_ID_ANALOG_X, 500);
  /* An analog trigger read follows the digital button when no value is set. */
  ezcore_set_button(s, 0, RETRO_DEVICE_ID_JOYPAD_R2, true);
  frame(s);
  CHECK(v[0] == 12000 && v[1] == -32767, "left stick reaches port 0");
  CHECK(v[2] == 500, "right stick reaches port 1");
  CHECK(v[3] == 0x7fff, "a pressed R2 reads fully pulled as an analog button");

  /* Mouse: deltas accumulate between frames, are the same for every read
   * within one frame, and are consumed by the frame. */
  ezcore_mouse_move(s, 3, -2);
  ezcore_mouse_move(s, 4, 1);
  ezcore_set_mouse_button(s, RETRO_DEVICE_ID_MOUSE_LEFT, true);
  frame(s);
  CHECK(v[4] == 7 && v[5] == -1, "mouse deltas accumulate until the frame");
  CHECK(v[14] == v[4], "a second read in the same frame sees the same delta");
  CHECK(v[6] == 1, "mouse left button");
  frame(s);
  CHECK(v[4] == 0 && v[5] == 0, "deltas are consumed by the frame");
  CHECK(v[6] == 1, "a held mouse button stays held");

  /* Keyboard: polled state and the core's event callback. */
  ezcore_set_key(s, RETROK_a, true, 'a', 0);
  frame(s);
  CHECK(v[7] == 1, "a held key reads as pressed");
  CHECK(v[11] == 1 && v[12] == RETROK_a && v[13] == 1,
        "the core's keyboard callback got the key-down event");
  ezcore_set_key(s, RETROK_a, false, 0, 0);
  frame(s);
  CHECK(v[7] == 0 && v[11] == 0 && v[13] == 1, "key-up reaches both paths");
  ezcore_set_key(s, 99999, true, 0, 0); /* out of range: ignored */
  frame(s);
  CHECK(v[13] == 0, "an out-of-range keycode is ignored");

  /* Pointer (touchscreen). */
  ezcore_set_pointer(s, -16000, 20000, true);
  frame(s);
  CHECK(v[8] == -16000 && v[9] == 20000 && v[10] == 1, "pointer position and press");

  /* A reset releases everything the player might be holding. */
  ezcore_reset(s);
  frame(s);
  CHECK(v[0] == 0 && v[2] == 0 && v[3] == 0 && v[6] == 0 && v[10] == 0,
        "reset releases sticks, mouse buttons and the pointer");

  ezcore_unload(s);
  printf("PASS\n");
  return 0;
}

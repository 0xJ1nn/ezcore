/* test_input_reset.c — regression test for the stuck-input bug.
 *
 * Bug: ezcore_reset() only called retro_reset(). A button still held by the
 * player at the instant reset was pressed stayed latched in the session's
 * input_buttons, so the core read 1 for that bit on every frame afterwards
 * and the character kept moving. ezcore_reset() now releases all four ports
 * before dispatching retro_reset().
 *
 * This test drives the real input path rather than inspecting the session
 * struct: it sets a button on all four ports, lets the synthetic core echo
 * the resulting port mask into an audio sample, calls ezcore_reset(), and
 * requires the very next frame to report every port released.
 *
 * It uses the EZCORE_SYNTH_ALL_PORTS build of the synthetic core, which polls
 * buttons 0 and 9 on all four ports and packs "which are held" into a byte
 * XORed into the audio sample: bit N = port N button 0, bit 4+N = port N
 * button 9. So:
 *   nothing held                      -> 0x1000
 *   port 0 button 0 held              -> 0x1001
 *   all four ports' button 0 held     -> 0x100F
 *   ports 0+1 button 0, port 1 b9     -> 0x1013
 *
 * Against the unfixed runtime the post-reset sample still carries the held
 * bits and the "all ports released after reset" check fails.
 *
 * Exit: 0 = pass, 1-9 = step that failed.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ezcore_runtime.h"

/* Sample values produced by the EZCORE_SYNTH_ALL_PORTS synthetic core. */
#define SAMPLE_IDLE ((int16_t)0x1000)
#define SAMPLE_ALL_PORTS ((int16_t)0x100F) /* 0x1000 ^ 0b1111 */

#define CHECK(cond, msg)                                                       \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, "FAIL: %s\n", msg);                                      \
      return 1;                                                                \
    } else {                                                                   \
      printf("ok: %s\n", msg);                                                 \
    }                                                                          \
  } while (0)

/* Runs one frame and returns the first audio sample it produced. The synth
 * core emits a constant sample for the whole frame, so sample 0 is the
 * frame's button state. */
static int16_t run_frame_sample(ezcore_session *s, int16_t *buf, size_t cap) {
  size_t pending = ezcore_audio_pending(s);
  while (pending > 0) {
    pending -= ezcore_audio_drain(s, buf, cap);
  }
  ezcore_run_frame(s);
  memset(buf, 0, cap * sizeof(int16_t));
  size_t got = ezcore_audio_drain(s, buf, cap);
  if (got == 0) return (int16_t)0;
  return buf[0];
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: test_input_reset <synth_libretro.dylib>\n");
    return 9;
  }

  const char *core_path = argv[1];

  /* --- Load + init + load_game (reset is a no-op without a game) --- */
  char err[1024] = {0};
  ezcore_session *s = ezcore_load(core_path, err, sizeof(err));
  CHECK(s != NULL, "core loaded");
  CHECK(ezcore_init(s), "init ok");
  CHECK(ezcore_load_game(s, "/dev/null", NULL, 0), "load_game ok");

  int16_t buf[2048];

  /* Baseline: nothing held, the core must read a clean pad. */
  int16_t idle = run_frame_sample(s, buf, 2048);
  CHECK(idle == SAMPLE_IDLE, "idle sample is 0x1000 (no button held)");

  /* --- Hold button 0 on all four ports at once --- */
  for (unsigned port = 0; port < 4; port++) {
    ezcore_set_button(s, port, 0, true);
  }
  int16_t held = run_frame_sample(s, buf, 2048);
  CHECK(held == SAMPLE_ALL_PORTS,
        "all four ports read back as held before reset (0x100F)");

  /* --- THE REGRESSION: reset must release every port --- */
  ezcore_reset(s);
  int16_t after = run_frame_sample(s, buf, 2048);
  if (after != SAMPLE_IDLE) {
    fprintf(stderr,
            "stuck input after reset: sample 0x%04X (expected 0x1000) — "
            "a port is still latched held\n",
            (unsigned)(uint16_t)after);
  }
  CHECK(after == SAMPLE_IDLE, "all four ports released by ezcore_reset");

  /* --- A port held again after reset still works (clear isn't sticky) --- */
  ezcore_set_button(s, 2, 0, true);
  int16_t reheld = run_frame_sample(s, buf, 2048);
  CHECK(reheld == (int16_t)(0x1000 ^ 0x04),
        "port 2 re-presses cleanly after reset");
  ezcore_clear_buttons(s, 2);
  int16_t reidle = run_frame_sample(s, buf, 2048);
  CHECK(reidle == SAMPLE_IDLE, "explicit clear still works after reset");

  /* --- Only one port held, reset releases just that one --- */
  ezcore_set_button(s, 1, 0, true);
  held = run_frame_sample(s, buf, 2048);
  CHECK(held == (int16_t)(0x1000 ^ 0x02), "port 1 held before second reset");
  ezcore_reset(s);
  after = run_frame_sample(s, buf, 2048);
  CHECK(after == SAMPLE_IDLE, "single held port released by ezcore_reset");

  /* --- Higher button ids (above the low nibble) are cleared too --- */
  ezcore_set_button(s, 0, 9, true); /* bit 4 in the packed byte */
  ezcore_set_button(s, 1, 9, true); /* bit 5 */
  held = run_frame_sample(s, buf, 2048);
  CHECK(held == (int16_t)(0x1000 ^ 0x30), "ports 0+1 button 9 held pre-reset");
  ezcore_reset(s);
  after = run_frame_sample(s, buf, 2048);
  CHECK(after == SAMPLE_IDLE, "high button ids released by ezcore_reset");

  ezcore_unload(s);

  printf("\n✅ ALL INPUT RESET TESTS PASSED\n");
  return 0;
}

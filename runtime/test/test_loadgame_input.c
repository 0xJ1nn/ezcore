/* test_loadgame_input.c — regression test for the stuck-input bug at the
 * game boundary.
 *
 * Bug: ezcore_load_game() never touched the session's input_buttons. Loading
 * a second game into an already-live session (no unload in between) carried
 * every button the player was holding across the boundary, so the newly
 * loaded core read 1 for those bits on its first frames — phantom input held
 * before the player touched anything. This is the same bug class already
 * fixed in ezcore_reset(), in the sibling function.
 *
 * This test drives the real input path rather than inspecting the session
 * struct: it holds buttons across a second ezcore_load_game() and requires
 * the very next frame to report every port released.
 *
 * It also pins the placement decision documented in runtime.c: the clear
 * happens only on a *successful* load, because a failed load leaves the
 * session still running the previous game and its held buttons are live
 * player input. A content-less load is rejected by the
 * EZCORE_SYNTH_FAIL_LOAD build of the synthetic core; after such a failure
 * the core must still see the buttons it saw before.
 *
 * It uses the EZCORE_SYNTH_ALL_PORTS build of the synthetic core, which polls
 * buttons 0 and 9 on all four ports and packs "which are held" into a byte
 * XORed into the audio sample: bit N = port N button 0, bit 4+N = port N
 * button 9. So:
 *   nothing held                            -> 0x1000
 *   port 0 button 0 held                    -> 0x1001
 *   ports 0+1 button 0, ports 1+2 button 9  -> 0x1063
 *   port 0 button 0, port 1 button 9        -> 0x1021
 *
 * Against the unfixed runtime the post-load sample still carries the held
 * bits and the "all ports released after load_game" check fails.
 *
 * usage: test_loadgame_input <synth_all_ports.dylib> <synth_all_ports_fail_load.dylib>
 *
 * Exit: 0 = pass, 1 = failed check, 9 = bad usage.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ezcore_runtime.h"

/* Sample values produced by the EZCORE_SYNTH_ALL_PORTS synthetic core. */
#define SAMPLE_IDLE ((int16_t)0x1000)
/* ports 0+1 button 0 (bits 0,1) and ports 1+2 button 9 (bits 5,6) */
#define SAMPLE_HELD_MULTI ((int16_t)(0x1000 ^ 0x63))
/* port 0 button 0 (bit 0) and port 1 button 9 (bit 5) */
#define SAMPLE_HELD_PAIR ((int16_t)(0x1000 ^ 0x21))
/* port 3 button 0 (bit 3) */
#define SAMPLE_PORT3 ((int16_t)(0x1000 ^ 0x08))

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
  if (argc < 3) {
    fprintf(stderr,
            "usage: test_loadgame_input <synth_all_ports_libretro.dylib> "
            "<synth_all_ports_fail_load_libretro.dylib>\n");
    return 9;
  }

  const char *core_path = argv[1];
  const char *fail_core_path = argv[2];

  int16_t buf[2048];

  /* ============ Part 1: a successful load clears held buttons ============ */

  /* --- Load + init + a first game, as any frontend would --- */
  char err[1024] = {0};
  ezcore_session *s = ezcore_load(core_path, err, sizeof(err));
  CHECK(s != NULL, "core loaded");
  CHECK(ezcore_init(s), "init ok");
  static const uint8_t first_game[64] = {0};
  CHECK(ezcore_load_game(s, "game1.rom", first_game, sizeof(first_game)),
        "first load_game ok");

  /* Baseline: nothing held, the core must read a clean pad. */
  int16_t idle = run_frame_sample(s, buf, 2048);
  CHECK(idle == SAMPLE_IDLE, "idle sample is 0x1000 (no button held)");

  /* --- Hold buttons on three ports across the game boundary --- */
  ezcore_set_button(s, 0, 0, true); /* bit 0  */
  ezcore_set_button(s, 1, 0, true); /* bit 1  */
  ezcore_set_button(s, 1, 9, true); /* bit 5  */
  ezcore_set_button(s, 2, 9, true); /* bit 6  */
  int16_t held = run_frame_sample(s, buf, 2048);
  CHECK(held == SAMPLE_HELD_MULTI,
        "three ports read back as held before the second load (0x1063)");

  /* --- THE REGRESSION: loading a second game releases every port --- */
  static const uint8_t second_game[96] = {0};
  CHECK(ezcore_load_game(s, "game2.rom", second_game, sizeof(second_game)),
        "second load_game into the live session ok");
  int16_t after = run_frame_sample(s, buf, 2048);
  if (after != SAMPLE_IDLE) {
    fprintf(stderr,
            "stuck input after load_game: sample 0x%04X (expected 0x1000) — "
            "a port is still latched held across the game boundary\n",
            (unsigned)(uint16_t)after);
  }
  CHECK(after == SAMPLE_IDLE, "all ports released by ezcore_load_game");

  /* --- A port held after the load still works (the clear isn't sticky) --- */
  ezcore_set_button(s, 3, 0, true);
  int16_t reheld = run_frame_sample(s, buf, 2048);
  CHECK(reheld == SAMPLE_PORT3, "port 3 presses cleanly after load_game");
  ezcore_clear_buttons(s, 3);
  CHECK(run_frame_sample(s, buf, 2048) == SAMPLE_IDLE,
        "explicit clear still works after load_game");

  ezcore_unload(s);

  /* ============ Part 2: a FAILED load leaves input untouched ============ */

  /* Same core, plus EZCORE_SYNTH_FAIL_LOAD: it rejects a content-less load. */
  ezcore_session *f = ezcore_load(fail_core_path, err, sizeof(err));
  CHECK(f != NULL, "fail-load core loaded");
  CHECK(ezcore_init(f), "fail-load core init ok");
  CHECK(ezcore_load_game(f, "game1.rom", first_game, sizeof(first_game)),
        "fail-load core first load_game ok");

  ezcore_set_button(f, 0, 0, true); /* bit 0 */
  ezcore_set_button(f, 1, 9, true); /* bit 5 */
  held = run_frame_sample(f, buf, 2048);
  CHECK(held == SAMPLE_HELD_PAIR,
        "two ports read back as held before the failed load (0x1021)");

  /* The core rejects this load (NULL rom path). The session is still running
   * game1, so its held buttons are live player input and must survive. */
  if (ezcore_load_game(f, NULL, NULL, 0)) {
    fprintf(stderr, "FAIL: content-less load_game unexpectedly succeeded\n");
    return 1;
  }
  printf("ok: content-less load_game rejected by the core\n");

  int16_t survived = run_frame_sample(f, buf, 2048);
  if (survived != SAMPLE_HELD_PAIR) {
    fprintf(stderr,
            "failed load dropped held input: sample 0x%04X (expected 0x1021) "
            "— the still-running previous game lost live input\n",
            (unsigned)(uint16_t)survived);
  }
  CHECK(survived == SAMPLE_HELD_PAIR,
        "failed load leaves input_buttons unchanged");

  /* --- And a later successful load still clears, as before --- */
  CHECK(ezcore_load_game(f, "game2.rom", second_game, sizeof(second_game)),
        "fail-load core second load_game ok");
  CHECK(run_frame_sample(f, buf, 2048) == SAMPLE_IDLE,
        "successful load after a failed one still releases every port");

  ezcore_unload(f);

  printf("\n✅ ALL LOADGAME INPUT TESTS PASSED\n");
  return 0;
}

// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* test_target_sample_rate.c — the host must answer GET_TARGET_SAMPLE_RATE.
 *
 * A core with its own resampler asks the frontend what rate the audio device
 * runs at. libretro.h lets the frontend refuse, and a refusal is not neutral:
 * the core then reports the rate its own crystal produces. The colour
 * handheld core does this, and the unanswered value is 2097152 Hz -- roughly
 * 35 000 stereo frames for every emulated frame, against a ring that holds
 * 8192, and outside the 8000..192000 range every platform sink in the app
 * accepts.
 *
 * The fixture here is the same shape with invented numbers: it asks at load
 * time and falls back to its clock rate when it gets nothing. Both directions
 * are checked, because a host that answers with a wrong value is no better
 * than one that stays silent.
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "ezcore_runtime.h"

#define CHECK(cond, msg)                                                       \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, "FAIL: %s\n", msg);                                      \
      return 1;                                                                \
    }                                                                          \
    printf("ok: %s\n", msg);                                                   \
  } while (0)

static ezcore_session *open_with(const char *core, char *err, size_t err_len) {
  ezcore_session *s = ezcore_load(core, err, err_len);
  if (!s) return NULL;
  if (!ezcore_init(s)) {
    ezcore_unload(s);
    return NULL;
  }
  if (!ezcore_load_game(s, "/dev/null", NULL, 0)) {
    ezcore_unload(s);
    return NULL;
  }
  return s;
}

int main(int argc, char **argv) {
  if (argc < 3) {
    fprintf(stderr,
            "usage: test_target_sample_rate <synth_target_rate core> "
            "<plain synth core>\n");
    return 9;
  }
  char err[512] = {0};

  /* 1. The default is a rate a device will open, not a placeholder. */
  CHECK(ezcore_target_sample_rate() == 48000u,
        "target rate defaults to 48000 Hz");

  /* 2. A core that asks at load time receives it and reports it back through
   *    AV timing. This is the whole defect: before the case existed the core
   *    kept its clock rate and the runtime reported 2097152 Hz. */
  {
    ezcore_session *s = open_with(argv[1], err, sizeof(err));
    CHECK(s != NULL, "core that asks for the target rate loads");
    double rate = ezcore_sample_rate(s);
    printf("    reported rate with an answer: %.0f Hz\n", rate);
    CHECK(rate == 48000.0, "answering the query gives the core 48000 Hz");
    ezcore_unload(s);
  }

  /* 3. Changing the answer changes what the core reports: proof the value is
   *    read from the host, not hardcoded inside the fixture. */
  CHECK(ezcore_set_target_sample_rate(44100u), "44100 Hz is accepted");
  CHECK(ezcore_target_sample_rate() == 44100u, "the new rate is stored");
  {
    ezcore_session *s = open_with(argv[1], err, sizeof(err));
    CHECK(s != NULL, "core reloads after a rate change");
    CHECK(ezcore_sample_rate(s) == 44100.0,
          "the core reports the host's new rate");
    ezcore_unload(s);
  }

  /* 4. A rate no device opens is refused, and the previous value survives.
   *    Clamping would be worse than failing: it would report success. */
  CHECK(!ezcore_set_target_sample_rate(0u), "0 Hz is refused");
  CHECK(!ezcore_set_target_sample_rate(4000000u), "4 MHz is refused");
  CHECK(!ezcore_set_target_sample_rate(7999u), "just below the floor is refused");
  CHECK(!ezcore_set_target_sample_rate(192001u), "just above the ceiling is refused");
  CHECK(ezcore_target_sample_rate() == 44100u,
        "a refused rate leaves the previous one in place");
  CHECK(ezcore_set_target_sample_rate(192000u), "the ceiling itself is accepted");
  CHECK(ezcore_set_target_sample_rate(48000u), "48000 Hz is restored");

  /* 5. A core that never asks is unaffected: it keeps reporting its own rate,
   *    which for most cores is already a normal one. Answering the query must
   *    not overwrite the AV timing of cores that did not query. */
  {
    ezcore_session *s = open_with(argv[2], err, sizeof(err));
    CHECK(s != NULL, "core that never asks still loads");
    CHECK(ezcore_sample_rate(s) == 44100.0,
          "a core that does not ask keeps its own rate");
    ezcore_unload(s);
  }

  printf("PASS: target sample rate\n");
  return 0;
}

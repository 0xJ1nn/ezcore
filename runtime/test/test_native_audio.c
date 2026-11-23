// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* test_native_audio.c — native audio path with a real device driver and no sound card.
 *
 * Opens the miniaudio null backend at 48 kHz, runs the synthetic libretro core
 * through the runtime so its retro_audio_sample_batch callback feeds the audio
 * ring, and pumps ten seconds of device time. The test reports the audio
 * counters as JSON and fails on any underrun, timeout or missing samples.
 * The synthetic core is deterministic and ships no game content.
 */
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "ezcore_runtime.h"

#define OUTPUT_RATE 48000u
#define CORE_RATE 44100u
#define RING_FRAMES 16384u
#define TARGET_FRAMES (10u * OUTPUT_RATE)
#define TIMEOUT_SECONDS 25.0

#define CHECK(cond, msg)                                                       \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, "FAIL: %s\n", msg);                                      \
      return 1;                                                                \
    }                                                                          \
    printf("ok: %s\n", msg);                                                   \
  } while (0)

#define REQUIRE(cond, msg)                                                     \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, "FAIL: %s\n", msg);                                      \
      return 1;                                                                \
    }                                                                          \
  } while (0)

static double now_seconds(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void nap_ms(long ms) {
  struct timespec ts;
  ts.tv_sec = ms / 1000;
  ts.tv_nsec = (ms % 1000) * 1000000L;
  nanosleep(&ts, NULL);
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: test_native_audio <synth_libretro library>\n");
    return 9;
  }

  char err[512] = {0};
  ezcore_session *session = ezcore_load(argv[1], err, sizeof(err));
  CHECK(session != NULL, "synthetic core loaded");
  CHECK(ezcore_init(session), "core initialised");
  CHECK(ezcore_load_game(session, "/dev/null", NULL, 0), "game loaded");
  CHECK(ezcore_sample_rate(session) == (double)CORE_RATE, "core reports 44100 Hz");

  ezcore_audio_config cfg;
  memset(&cfg, 0, sizeof(cfg));
  cfg.input_sample_rate = (uint32_t)ezcore_sample_rate(session);
  cfg.output_sample_rate = OUTPUT_RATE;
  cfg.channels = 2;
  cfg.ring_frames = RING_FRAMES;
  cfg.volume = 1.0f;
  cfg.muted = false;
  cfg.backend = EZCORE_AUDIO_BACKEND_NULL;

  ezcore_audio *audio = ezcore_audio_open(&cfg, err, sizeof(err));
  if (!audio) {
    fprintf(stderr, "FAIL: open null-backend audio: %s\n", err);
    return 1;
  }
  printf("ok: null-backend audio device opened\n");

  ezcore_audio_statistics st;
  CHECK(ezcore_audio_stats(audio, &st), "stats available");
  CHECK(st.device_running, "device started");
  CHECK(fabs(st.rate_ratio - (double)CORE_RATE / OUTPUT_RATE) < 0.01,
        "resampler ratio reflects the core and device rates");

  ezcore_audio_set_volume(audio, 0.5f);
  ezcore_audio_set_muted(audio, true);
  CHECK(ezcore_audio_stats(audio, &st) && fabsf(st.volume - 0.5f) < 0.001f && st.muted,
        "volume and mute reach the device");
  ezcore_audio_set_muted(audio, false);
  ezcore_audio_set_volume(audio, 1.0f);

  const double start = now_seconds();
  for (;;) {
    REQUIRE(ezcore_audio_stats(audio, &st), "stats during playback");
    if (st.frames_played >= TARGET_FRAMES) break;
    if (now_seconds() - start > TIMEOUT_SECONDS) {
      fprintf(stderr, "FAIL: timed out after %.1f s with %llu of %u frames played\n",
              TIMEOUT_SECONDS, (unsigned long long)st.frames_played, TARGET_FRAMES);
      return 2;
    }
    /* Keep the buffer near half full: enough slack for scheduling jitter,
     * never so much that the synthetic core overruns it. */
    if (st.buffered_frames < RING_FRAMES / 2)
      ezcore_run_frame(session);
    else
      nap_ms(1);
  }

  printf("counters: written=%llu played=%llu underruns=%llu overruns=%llu "
         "fill=%.3f ratio=%.6f\n",
         (unsigned long long)st.frames_written,
         (unsigned long long)st.frames_played,
         (unsigned long long)st.underruns,
         (unsigned long long)st.overruns,
         st.fill_fraction, st.rate_ratio);

  ezcore_audio_close(audio);
  ezcore_unload(session);

  CHECK(st.underruns == 0, "zero underruns over 10 s at 48 kHz");
  CHECK(st.frames_written > 0, "core audio reached the ring buffer");
  CHECK(st.frames_played >= TARGET_FRAMES, "device played ten seconds of audio");
  CHECK(st.buffered_frames <= RING_FRAMES, "ring stayed within capacity");

  printf("{\"backend\":\"null\",\"output_rate\":%u,\"core_rate\":%u,"
         "\"frames_written\":%llu,\"frames_played\":%llu,"
         "\"underruns\":%llu,\"overruns\":%llu,\"rate_ratio\":%.6f,"
         "\"seconds\":%.3f}\n",
         OUTPUT_RATE, CORE_RATE,
         (unsigned long long)st.frames_written,
         (unsigned long long)st.frames_played,
         (unsigned long long)st.underruns,
         (unsigned long long)st.overruns,
         st.rate_ratio, now_seconds() - start);
  return 0;
}

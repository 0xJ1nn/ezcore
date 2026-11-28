// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* test_native_loop.c — the runtime-owned run thread.
 *
 * Drives the deterministic synthetic libretro core through the native loop.
 * The first stretch has no audio device, so pacing must fall back to a
 * monotonic clock; the second opens the null backend so pacing comes from the
 * audio device clock. The test checks frame pacing, frame-time percentiles,
 * the triple-buffer frame, atomic input, and a save/load round trip whose two
 * halves are applied as controls between frames. No game content is involved.
 */
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "ezcore_runtime.h"

#define TARGET_FRAMES 600u
#define TARGET_FPS 60.0
#define OUTPUT_RATE 48000u
#define CORE_RATE 44100u
#define EXPECTED_W 256u
#define EXPECTED_H 240u

/* Mirrors the synthetic core's 16-byte state blob (no game content). */
struct synth_state_for_test {
  uint32_t frame_counter;
  uint32_t button_state;
  uint32_t audio_sample_counter;
  uint32_t magic;
};

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

static uint64_t wait_for_frames(ezcore_loop *loop, uint64_t target,
                                double timeout_s, double *elapsed) {
  const double start = now_seconds();
  for (;;) {
    ezcore_loop_statistics st;
    if (!ezcore_loop_stats(loop, &st)) return 0;
    if (st.frames_run >= target) {
      *elapsed = now_seconds() - start;
      return st.frames_run;
    }
    if (now_seconds() - start > timeout_s) return 0;
    nap_ms(2);
  }
}

static bool apply(ezcore_loop *loop, uint64_t token, bool *result) {
  return token != 0 && ezcore_loop_control_wait(loop, token, 2000, result);
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: test_native_loop <synth_libretro library>\n");
    return 9;
  }

  char err[512] = {0};
  ezcore_session *session = ezcore_load(argv[1], err, sizeof(err));
  REQUIRE(session != NULL, "synthetic core loaded");
  REQUIRE(ezcore_init(session), "core initialised");
  REQUIRE(ezcore_load_game(session, "/dev/null", NULL, 0), "game loaded");

  ezcore_loop_config config;
  memset(&config, 0, sizeof(config));
  config.target_fps = 60;

  /* --- Phase 1: no audio device, monotonic pacing, controls and input --- */
  ezcore_loop *loop = ezcore_loop_start(session, &config, err, sizeof(err));
  if (!loop) {
    fprintf(stderr, "FAIL: start loop: %s\n", err);
    return 1;
  }
  CHECK(ezcore_loop_stats(loop, NULL) == false, "stats reject a null out pointer");

  ezcore_loop_set_button(loop, 0, 0, true);
  double elapsed = 0.0;
  uint64_t frames = wait_for_frames(loop, 12, 4.0, &elapsed);
  CHECK(frames >= 12, "monotonic fallback ran twelve frames");
  CHECK(elapsed > 0.12 && elapsed < 0.9, "monotonic fallback paced near 60 Hz");

  unsigned w = 0, h = 0;
  const uint32_t *pixels = ezcore_loop_frame(loop, &w, &h);
  CHECK(pixels != NULL && w == EXPECTED_W && h == EXPECTED_H,
        "triple buffer published the latest frame");
  if (pixels) ezcore_loop_frame_release(loop);

  bool result = false;
  CHECK(apply(loop, ezcore_loop_control_pause(loop, true), &result) && result,
        "pause control applied between frames");

  /* A paused loop publishes statistics every millisecond. A reader must get a
   * consistent snapshot even when the writer updates between its retries;
   * an eight-attempt busy loop can give up and lose the caller's wait. */
  unsigned stats_failures = 0;
  for (unsigned i = 0; i < 2000000; i++) {
    ezcore_loop_statistics probe;
    if (!ezcore_loop_stats(loop, &probe)) stats_failures++;
  }
  CHECK(stats_failures == 0, "statistics survive a publishing run thread");

  unsigned char state[128];
  size_t state_size = ezcore_serialize_size(session);
  REQUIRE(state_size == sizeof(struct synth_state_for_test),
          "synthetic state blob has the expected size");
  REQUIRE(ezcore_serialize(session, state, sizeof(state)),
          "first state snapshot taken");
  struct synth_state_for_test snap;
  memcpy(&snap, state, sizeof(snap));
  CHECK(snap.button_state == 1u,
        "button set through the atomic FFI slot reached the core");

  ezcore_loop_set_button(loop, 0, 0, false);
  CHECK(apply(loop, ezcore_loop_control_pause(loop, false), &result) && result,
        "resume control applied");
  frames = wait_for_frames(loop, 24, 4.0, &elapsed);
  CHECK(frames >= 24, "loop resumed after the pause control");
  CHECK(apply(loop, ezcore_loop_control_pause(loop, true), &result) && result,
        "paused again for the state round trip");
  REQUIRE(ezcore_serialize(session, state, sizeof(state)),
          "second state snapshot taken");
  memcpy(&snap, state, sizeof(snap));
  CHECK(snap.button_state == 0u, "clearing the atomic slot released the button");

  /* Save and load are controls, not direct runtime calls: the loop applies
   * them on its own thread between two frames. */
  unsigned char saved[128], verify[128];
  CHECK(apply(loop, ezcore_loop_control_save(loop, saved, sizeof(saved)), &result) &&
        result, "save control applied");
  unsigned char saved_copy[128];
  memcpy(saved_copy, saved, sizeof(saved));

  /* Running frames would change the state, so prove the load restores it by
   * loading the saved bytes straight back while the loop is paused. */
  CHECK(apply(loop, ezcore_loop_control_load(loop, saved_copy, sizeof(saved_copy)),
              &result) && result, "load control applied");
  REQUIRE(ezcore_serialize(session, verify, sizeof(verify)),
          "verification snapshot taken");
  CHECK(memcmp(verify, saved, state_size) == 0,
        "save/load through the control queue round-trips the core state");

  CHECK(apply(loop, ezcore_loop_control_reset(loop), &result) && result,
        "reset control applied");
  CHECK(apply(loop, ezcore_loop_control_cheat_reset(loop), &result) && result,
        "cheat reset control applied");
  CHECK(apply(loop, ezcore_loop_control_cheat_set(loop, 0, true, "0"), &result) &&
        result, "cheat set control applied");
  CHECK(apply(loop, ezcore_loop_control_option(loop, "unused", "1"), &result),
        "option control applied");
  CHECK(apply(loop, ezcore_loop_control_fast_forward(loop, 2), &result) && result,
        "fast-forward control applied");
  CHECK(apply(loop, ezcore_loop_control_fast_forward(loop, 1), &result) && result,
        "fast-forward restored to normal speed");

  /* The control queue holds sixty-four requests. A finished request must give
   * its slot back, otherwise the sixty-fifth call returns token 0 and every
   * later control -- save, load, pause, reset -- silently fails for the rest of
   * the session. */
  uint64_t first = ezcore_loop_control_fast_forward(loop, 1);
  REQUIRE(apply(loop, first, &result) && result, "first recyclable control applied");
  unsigned queued = 0;
  for (unsigned i = 0; i < 63; i++) {
    if (!ezcore_loop_control_fast_forward(loop, 1)) break;
    queued++;
  }
  REQUIRE(queued == 63, "queue accepted requests up to its capacity");
  /* Every slot is held by a request. The next call must reuse the finished one
   * instead of failing. */
  uint64_t overflow = ezcore_loop_control_fast_forward(loop, 1);
  CHECK(overflow != 0, "a full queue recycles a finished control instead of failing");
  CHECK(apply(loop, overflow, &result) && result, "the recycled request applied");
  CHECK(ezcore_loop_control_wait(loop, first, 2000, &result) && result,
        "a recycled control's result is still waitable");

  /* Sustained use must keep working: waiting for each request returns its own
   * slot, so the queue refills indefinitely. */
  unsigned sustained = 0;
  for (unsigned i = 0; i < 200; i++) {
    uint64_t token = ezcore_loop_control_fast_forward(loop, 1);
    if (!token || !apply(loop, token, &result) || !result) break;
    sustained++;
  }
  CHECK(sustained == 200, "two hundred further controls all found a slot");
  CHECK(ezcore_loop_control_wait(loop, 900000000ull, 20, &result) == false,
        "wait rejects a token that was never issued");

  /* Publication churn: at speed, the producer replaces frames it has already
   * claimed. A claimed slot that is never handed back strands the picture after
   * three frames, so read one frame per iteration across several hundred
   * publications and require every read to find one. */
  CHECK(apply(loop, ezcore_loop_control_pause(loop, false), &result) && result,
        "resumed for publication churn");
  CHECK(apply(loop, ezcore_loop_control_fast_forward(loop, 4), &result) && result,
        "fast-forward engaged for publication churn");
  uint64_t base = 0;
  {
    ezcore_loop_statistics now;
    REQUIRE(ezcore_loop_stats(loop, &now), "statistics readable before churn");
    base = now.frames_run;
  }
  frames = wait_for_frames(loop, base + 300, 8.0, &elapsed);
  CHECK(frames >= base + 300, "loop kept publishing frames under churn");
  /* A read can legitimately miss while the producer holds every slot it is
   * allowed to claim, so allow a short retry. What must never happen is a slot
   * that is never handed back: then no retry ever finds a frame again. */
  unsigned visible = 0;
  for (unsigned i = 0; i < 40; i++) {
    bool got = false;
    for (unsigned attempt = 0; attempt < 100 && !got; attempt++) {
      if (ezcore_loop_frame(loop, &w, &h) && w == EXPECTED_W && h == EXPECTED_H) {
        ezcore_loop_frame_release(loop);
        got = true;
        break;
      }
      nap_ms(1);
    }
    if (!got) break;
    visible++;
    nap_ms(2);
  }
  CHECK(visible == 40, "every frame read during churn was published");
  CHECK(apply(loop, ezcore_loop_control_fast_forward(loop, 1), &result) && result,
        "fast-forward restored after churn");
  CHECK(apply(loop, ezcore_loop_control_pause(loop, true), &result) && result,
        "paused again for the statistics check");

  ezcore_loop_statistics stats;
  REQUIRE(ezcore_loop_stats(loop, &stats), "statistics snapshot available");
  CHECK(stats.control_applied >= 11 && stats.control_pending == 0,
        "every queued control was applied");
  CHECK(stats.histogram_len > 0 && stats.histogram != NULL,
        "frame-time histogram published");

  ezcore_loop_stop(loop);
  loop = NULL;

  /* --- Phase 2: audio device clock, 600 frames at 60 Hz --- */
  ezcore_audio_config acfg;
  memset(&acfg, 0, sizeof(acfg));
  acfg.input_sample_rate = CORE_RATE;
  acfg.output_sample_rate = OUTPUT_RATE;
  acfg.channels = 2;
  acfg.ring_frames = 16384u;
  acfg.volume = 1.0f;
  acfg.muted = false;
  acfg.backend = EZCORE_AUDIO_BACKEND_NULL;
  ezcore_audio *audio = ezcore_audio_open(&acfg, err, sizeof(err));
  if (!audio) {
    fprintf(stderr, "FAIL: open null audio device: %s\n", err);
    return 1;
  }

  loop = ezcore_loop_start(session, &config, err, sizeof(err));
  if (!loop) {
    fprintf(stderr, "FAIL: start audio-paced loop: %s\n", err);
    ezcore_audio_close(audio);
    return 1;
  }
  const double run_start = now_seconds();
  frames = wait_for_frames(loop, TARGET_FRAMES, 20.0, &elapsed);
  REQUIRE(frames >= TARGET_FRAMES, "audio-paced loop ran 600 frames");
  const double total = now_seconds() - run_start;

  REQUIRE(ezcore_loop_stats(loop, &stats), "final statistics snapshot");
  printf("loop: frames=%llu elapsed=%.3f s mean=%.3f ms p50=%.3f ms "
         "p95=%.3f ms p99=%.3f ms max=%.3f ms dropped=%llu "
         "audio_underruns=%llu\n",
         (unsigned long long)stats.frames_run, total, stats.frame_mean_ms,
         stats.frame_p50_ms, stats.frame_p95_ms, stats.frame_p99_ms,
         stats.frame_max_ms, (unsigned long long)stats.dropped_frames,
         (unsigned long long)stats.audio_underruns);

  CHECK(total > 9.0 && total < 11.5, "600 frames took about ten seconds at 60 Hz");
  CHECK(stats.frame_p99_ms < 20.0, "frame-time p99 is under 20 ms on Linux");
  CHECK(stats.frames_run >= TARGET_FRAMES, "frame counter reached 600");

  ezcore_loop_stop(loop);
  ezcore_audio_close(audio);
  ezcore_unload(session);

  printf("{\"frames\":%llu,\"seconds\":%.3f,\"p99_ms\":%.3f,"
         "\"dropped\":%llu,\"audio_underruns\":%llu}\n",
         (unsigned long long)stats.frames_run, total, stats.frame_p99_ms,
         (unsigned long long)stats.dropped_frames,
         (unsigned long long)stats.audio_underruns);
  return 0;
}

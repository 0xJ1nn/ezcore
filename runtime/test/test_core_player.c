/* test_core_player.c — exercises the runtime's player capabilities.
 *
 * Uses the synthetic libretro core (deterministic, no copyrighted content).
 * Failing-first: verifies input, reset, sample rate, frame/audio copy,
 * serialize round-trip, and lifecycle correctness.
 *
 * Exit: 0 = pass, 1-9 = step that failed.
 */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ezcore_runtime.h"

#define CHECK(cond, msg)                                                       \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, "FAIL: %s\n", msg);                                      \
      return 1;                                                                \
    } else {                                                                   \
      printf("ok: %s\n", msg);                                                 \
    }                                                                          \
  } while (0)

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: test_core_player <synth_libretro.dylib>\n");
    return 9;
  }

  const char *core_path = argv[1];

  /* --- ABI version --- */
  CHECK(ezcore_abi_version() == 1, "ABI version is 1");

  /* --- Load + Init --- */
  char err[1024] = {0};
  ezcore_session *s = ezcore_load(core_path, err, sizeof(err));
  CHECK(s != NULL, "core loaded");
  CHECK(ezcore_init(s), "init ok");
  CHECK(strcmp(ezcore_core_name(s), "ezTest Synth") == 0, "core name");
  CHECK(strcmp(ezcore_core_version(s), "1.0.0") == 0, "core version");

  /* --- Load game (synthetic core accepts anything) --- */
  CHECK(ezcore_load_game(s, "/dev/null", NULL, 0), "load_game ok");

  /* --- Geometry + Sample rate --- */
  unsigned w = 0, h = 0;
  double fps = 0;
  ezcore_system_geometry(s, &w, &h, &fps);
  CHECK(w == 256, "frame width 256");
  CHECK(h == 240, "frame height 240");
  CHECK(fps == 60.0, "fps 60");
  CHECK(ezcore_sample_rate(s) == 44100.0, "sample rate 44100");

  /* --- Run frames and get frame pixels --- */
  for (int i = 0; i < 10; i++) ezcore_run_frame(s);
  unsigned fw = 0, fh = 0;
  const uint32_t *px = ezcore_frame_pixels(s, &fw, &fh);
  CHECK(px != NULL, "frame pixels non-NULL");
  CHECK(fw == 256 && fh == 240, "frame dimensions");

  uint64_t sum = 0;
  for (unsigned i = 0; i < fw * fh; i++) sum += px[i];
  CHECK(sum > 0, "frame pixels non-zero");

  /* Frame changes across runs: R channel increments each frame */
  uint32_t pixel_before = px[0];

  /* --- Frame copy --- */
  size_t frame_bytes = (size_t)fw * fh * 4;
  uint8_t *frame_copy = malloc(frame_bytes);
  CHECK(frame_copy != NULL, "frame_copy malloc");
  size_t copied = ezcore_frame_pixels_copy(s, frame_copy, frame_bytes);
  CHECK(copied == frame_bytes, "frame copy size matches");

  uint32_t word0 = px[0];
  uint8_t raw_r = (uint8_t)((word0 >> 16) & 0xFF);
  uint8_t raw_g = (uint8_t)((word0 >> 8) & 0xFF);
  uint8_t raw_b = (uint8_t)((word0 >> 0) & 0xFF);
  CHECK(frame_copy[0] == raw_r, "frame copy byte 0 = R");
  CHECK(frame_copy[1] == raw_g, "frame copy byte 1 = G");
  CHECK(frame_copy[2] == raw_b, "frame copy byte 2 = B");
  CHECK(frame_copy[3] == 255, "frame copy alpha is opaque");
  free(frame_copy);

  /* --- Audio drain --- */
  size_t pending = ezcore_audio_pending(s);
  CHECK(pending > 0, "audio pending after frames");

  int16_t audio_buf[4096];
  size_t drained = ezcore_audio_drain(s, audio_buf, 2048);
  CHECK(drained > 0, "audio drained");
  CHECK(drained == 2048, "drain count is 2048");
  size_t pending2 = ezcore_audio_pending(s);
  CHECK(pending2 == pending - drained, "pending decreases by drain count");

  /* --- Audio drain_copy (copy variant) --- */
  size_t dc = ezcore_audio_drain_copy(s, audio_buf, 512);
  CHECK(dc == 512, "audio drain_copy returns 512");
  CHECK(ezcore_audio_pending(s) == pending2 - 512, "pending after drain_copy");

  /* --- Input test: set button B (id 0) and verify echo in audio --- */
  while (ezcore_audio_pending(s) > 0) {
    ezcore_audio_drain(s, audio_buf, 2048);
  }

  ezcore_set_button(s, 0, 0, true); /* B pressed */
  ezcore_run_frame(s);
  int16_t ab_b[1024] = {0};
  size_t got_b = ezcore_audio_drain(s, ab_b, 480);
  CHECK(got_b > 0, "audio after B pressed");
  CHECK(ab_b[0] == (int16_t)0x1001, "audio sample = 0x1001 when B pressed");

  /* Release B → sample back to 0x1000 */
  ezcore_set_button(s, 0, 0, false);
  ezcore_run_frame(s);
  int16_t ab_none[1024] = {0};
  ezcore_audio_drain(s, ab_none, 480);
  CHECK(ab_none[0] == (int16_t)0x1000, "audio sample = 0x1000 when B released");

  /* B + Y (bit 1) → sample = 0x1000 ^ 0x03 = 0x1003 */
  ezcore_set_button(s, 0, 0, true); /* B = bit 0 */
  ezcore_set_button(s, 0, 1, true); /* Y = bit 1 → 0x02 */
  ezcore_run_frame(s);
  int16_t ab_a[1024] = {0};
  ezcore_audio_drain(s, ab_a, 480);
  CHECK(ab_a[0] == (int16_t)(0x1003), "audio sample = 0x1003 when B+Y pressed");

  ezcore_clear_buttons(s, 0);
  ezcore_run_frame(s);
  int16_t ab_clear[1024] = {0};
  ezcore_audio_drain(s, ab_clear, 480);
  CHECK(ab_clear[0] == (int16_t)0x1000, "audio sample = 0x1000 after clear_buttons");

  /* --- Reset test --- */
  /* After running more frames, pixel changes. After reset, pixel should
   * revert to a value close to 0 (frame_counter resets to 0, R=0 or 1). */
  uint32_t pixel_after_frames = px[0];
  (void)pixel_after_frames; /* we just need the core to keep running */

  for (int i = 0; i < 60; i++) ezcore_run_frame(s);
  ezcore_audio_drain(s, audio_buf, 2048);

  ezcore_run_frame(s); /* one more frame to capture pixel */
  px = ezcore_frame_pixels(s, &fw, &fh);
  uint32_t pixel_before_reset = px[0];

  ezcore_reset(s);
  ezcore_run_frame(s);
  px = ezcore_frame_pixels(s, &fw, &fh);
  CHECK(px != NULL, "frame after reset");

  uint32_t pixel_after_reset = px[0];
  /* After reset, R should be very small (0 or 1). Before, it was large. */
  uint8_t r_before = (uint8_t)((pixel_before_reset >> 16) & 0xFF);
  uint8_t r_after = (uint8_t)((pixel_after_reset >> 16) & 0xFF);
  CHECK(r_after < r_before, "R channel smaller after reset");
  CHECK(r_after <= 2, "R channel near zero after reset");

  /* --- Serialize round-trip --- */
  for (int i = 0; i < 10; i++) ezcore_run_frame(s);
  ezcore_audio_drain(s, audio_buf, 2048);

  size_t snap_size = ezcore_serialize_size(s);
  CHECK(snap_size > 0, "serialize_size > 0");
  void *snap = malloc(snap_size);
  CHECK(snap != NULL, "snap malloc");
  CHECK(ezcore_serialize(s, snap, snap_size), "serialize ok");

  /* Capture frame before divergence */
  ezcore_run_frame(s);
  px = ezcore_frame_pixels(s, &fw, &fh);
  uint32_t pixel_before_diverge = px[0];

  /* Run 20 frames to diverge */
  for (int i = 0; i < 20; i++) ezcore_run_frame(s);
  ezcore_audio_drain(s, audio_buf, 2048);

  px = ezcore_frame_pixels(s, &fw, &fh);
  uint32_t pixel_after_diverge = px[0];
  CHECK(pixel_after_diverge != pixel_before_diverge, "frame diverges over time");

  /* Restore and verify */
  CHECK(ezcore_unserialize(s, snap, snap_size), "unserialize ok");
  ezcore_run_frame(s);
  px = ezcore_frame_pixels(s, &fw, &fh);
  uint32_t pixel_after_restore = px[0];
  /* After restore, pixel should be close to pre-divergence value (within
   * one frame's worth of R increment). */
  uint8_t r_restore = (uint8_t)((pixel_after_restore >> 16) & 0xFF);
  uint8_t r_pre = (uint8_t)((pixel_before_diverge >> 16) & 0xFF);
  int8_t r_diff = (int8_t)((int16_t)r_restore - (int16_t)r_pre);
  CHECK(r_diff >= 0 && r_diff <= 2, "frame counter restored near pre-diverge value");
  free(snap);

  /* --- Lifecycle: load → init → load_game → run → unload → re-load --- */
  ezcore_unload(s);
  s = NULL;

  s = ezcore_load(core_path, err, sizeof(err));
  CHECK(s != NULL, "re-load ok");
  CHECK(ezcore_init(s), "re-init ok");
  CHECK(ezcore_load_game(s, "/dev/null", NULL, 0), "re-load_game ok");
  ezcore_run_frame(s);
  px = ezcore_frame_pixels(s, &fw, &fh);
  CHECK(px != NULL, "frame after re-load");
  ezcore_unload(s);

  printf("\n✅ ALL CORE PLAYER TESTS PASSED\n");
  return 0;
}

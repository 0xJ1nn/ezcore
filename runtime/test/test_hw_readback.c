/* test_hw_readback.c — a GPU-rendered frame reaches the host (P8).
 *
 * A core that renders with OpenGL signals a finished frame by passing
 * RETRO_HW_FRAME_BUFFER_VALID ((void *)-1) to video_cb instead of pixels.
 * Before readback, the runtime treated that sentinel as a pixel pointer and
 * copied from address -1. This drives synth_hw_draw (red with a green top
 * half, bottom-left GL origin) and checks the frame the host sees: the right
 * size, the right colours, and the right way up.
 *
 * Skips (exit 0, printed reason) where no GPU context can be created.
 * Exit: 0 pass/skip, 1 a check failed, 9 usage. */
#include <stdint.h>
#include <stdio.h>

#include "ezcore_runtime.h"

#define CHECK(cond, msg)                                                       \
  do {                                                                         \
    if (!(cond)) { fprintf(stderr, "FAIL: %s\n", msg); return 1; }             \
    printf("ok: %s\n", msg);                                                   \
  } while (0)

int main(int argc, char **argv) {
  if (argc < 2) { fprintf(stderr, "usage: test_hw_readback <core>\n"); return 9; }
  char err[256] = {0};
  ezcore_session *s = ezcore_load(argv[1], err, sizeof(err));
  CHECK(s != NULL, "drawing GPU core loaded");
  CHECK(ezcore_init(s), "init");
  if (!ezcore_load_game(s, "x.probe", "x", 1)) {
    printf("skip: no GPU context on this host, so the core refused to load\n");
    ezcore_unload(s);
    return 0;
  }
  for (int i = 0; i < 3; i++) ezcore_run_frame(s);
  unsigned w = 0, h = 0;
  const uint32_t *px = ezcore_frame_pixels(s, &w, &h);
  CHECK(px != NULL && w == 64 && h == 64, "the GPU frame was read back at 64x64");
  uint32_t top = px[0] & 0x00FFFFFF, bottom = px[(h - 1) * w] & 0x00FFFFFF;
  printf("  top-left 0x%06x  bottom-left 0x%06x\n", top, bottom);
  CHECK(top == 0x00FF00, "the top row is green (picture is the right way up)");
  CHECK(bottom == 0xFF0000, "the bottom row is red");
  ezcore_unload(s);
  printf("PASS\n");
  return 0;
}

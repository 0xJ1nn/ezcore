// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* Video texture bridge: pure blit and state validation.
 *
 * The Android window itself needs an emulator to exercise, but the pixel copy
 * and the attach/state contract are platform-neutral and run on every host.
 * No ROM or core is involved: the frame is a fixed XRGB8888 pattern. */
#include "ezcore_runtime.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

#define CHECK(cond, msg)                                                       \
  do {                                                                         \
    if (!(cond)) {                                                             \
      printf("FAIL: %s\n", msg);                                               \
      failures++;                                                              \
    }                                                                          \
  } while (0)

static void test_blit_rows(void) {
  /* Two XRGB8888 pixels: red (0x00FF0000) and blue (0x000000FF). */
  const uint32_t src[4] = {
      0x00FF0000u, 0x000000FFu,
      0x0000FF00u, 0xFFFFFFFFu,
  };
  uint8_t rgba[24];
  uint8_t bgra[24];
  memset(rgba, 0xAA, sizeof(rgba));
  memset(bgra, 0xAA, sizeof(bgra));

  /* Row stride is wider than the 2*4 bytes of pixels, so any row overflow
   * overwrites the guard bytes and fails below. */
  CHECK(ezcore_video_blit_rows(rgba, 12, src, 2, 2, false), "rgba blit accepted");
  CHECK(rgba[0] == 0xFF && rgba[1] == 0x00 && rgba[2] == 0x00 && rgba[3] == 0xFF,
        "red becomes RGBA");
  CHECK(rgba[4] == 0x00 && rgba[5] == 0x00 && rgba[6] == 0xFF && rgba[7] == 0xFF,
        "blue becomes RGBA");
  CHECK(rgba[8] == 0xAA && rgba[9] == 0xAA && rgba[10] == 0xAA && rgba[11] == 0xAA,
        "row stride padding is untouched");
  CHECK(rgba[12] == 0x00 && rgba[13] == 0xFF && rgba[14] == 0x00 && rgba[15] == 0xFF,
        "second row green becomes RGBA");

  CHECK(ezcore_video_blit_rows(bgra, 12, src, 2, 2, true), "bgra blit accepted");
  CHECK(bgra[0] == 0x00 && bgra[1] == 0x00 && bgra[2] == 0xFF && bgra[3] == 0xFF,
        "red becomes BGRA");
  CHECK(bgra[4] == 0xFF && bgra[5] == 0x00 && bgra[6] == 0x00 && bgra[7] == 0xFF,
        "blue becomes BGRA");

  CHECK(!ezcore_video_blit_rows(NULL, 12, src, 2, 2, false), "null dst rejected");
  CHECK(!ezcore_video_blit_rows(rgba, 12, NULL, 2, 2, false), "null src rejected");
  CHECK(!ezcore_video_blit_rows(rgba, 7, src, 2, 2, false), "short stride rejected");
  CHECK(!ezcore_video_blit_rows(rgba, 12, src, 0, 2, false), "zero width rejected");
}

static void test_stats(void) {
  ezcore_video_statistics stats;
  memset(&stats, 0x7F, sizeof(stats));
  CHECK(!ezcore_video_stats(NULL, &stats), "stats need a session");
  CHECK(!ezcore_video_attach(NULL, (void *)1, 240, 160), "attach needs a session");
  CHECK(!ezcore_video_attach((ezcore_session *)1, NULL, 240, 160),
        "attach needs a window");
  CHECK(!ezcore_video_attach((ezcore_session *)1, (void *)1, 0, 160),
        "attach needs a positive width");
  CHECK(!ezcore_video_present(NULL), "present needs a session");
  /* Detach of an unattached session is a safe no-op. */
  ezcore_video_detach((ezcore_session *)1);
}

int main(void) {
  test_blit_rows();
  test_stats();
  if (failures) {
    printf("video blit: %d failure(s)\n", failures);
    return 1;
  }
  printf("ok: RGBA and BGRA row blits respect stride\n");
  printf("ok: attach, present and stats reject invalid arguments\n");
  return 0;
}

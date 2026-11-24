// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* test_video_texture_bridge.c — measured regression test for the frame
 * snapshots handed to the desktop Flutter texture callbacks.
 *
 * The texture callback runs on the render thread while the core keeps
 * running. A single frame buffer cannot serve both without tearing, so the
 * bridge keeps three snapshots: the callback holds one until the next
 * callback, and publication never overwrites a held snapshot. This test
 * measures that behaviour and the exact RGBA bytes that reach the surface.
 *
 * Exit: 0 = pass, 1-9 = step that failed.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ezcore_runtime.h"
#include "ezcore_video_texture.h"

#define CHECK(cond, msg)                                                       \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, "FAIL: %s\n", msg);                                      \
      return 1;                                                                \
    }                                                                          \
    printf("ok: %s\n", msg);                                                   \
  } while (0)

/* 2x1 RGBA frames with opaque alpha, small enough to inspect byte for byte. */
static const uint8_t kFrameA[] = {
    11, 22, 33, 255, 44, 55, 66, 255,
    77, 88, 99, 255, 111, 122, 133, 255,
};
static const uint8_t kFrameB[] = {
    1, 2, 3, 255, 4, 5, 6, 255,
    7, 8, 9, 255, 10, 11, 12, 255,
};

static int check_bytes(const uint8_t *got, const uint8_t *want, size_t n,
                       const char *msg) {
  if (memcmp(got, want, n) != 0) {
    fprintf(stderr, "FAIL: %s\n", msg);
    for (size_t i = 0; i < n; ++i) {
      fprintf(stderr, "%02x%s", got[i], (i + 1) % 16 ? " " : "\n");
    }
    return 1;
  }
  printf("ok: %s\n", msg);
  return 0;
}

int main(int argc, char **argv) {
  ezcore_video_texture *texture = ezcore_video_texture_create();
  CHECK(texture != NULL, "texture bridge created");

  uint32_t w = 0, h = 0;
  const uint8_t *pixels = ezcore_video_texture_pixels(texture, &w, &h);
  CHECK(pixels == NULL, "no frame before the first publication");
  CHECK(w == 0 && h == 0, "empty frame reports zero dimensions");

  ezcore_video_texture_stats stats;
  ezcore_video_texture_stats_get(texture, &stats);
  CHECK(stats.frames_published == 0 && stats.buffer_growths == 0,
        "empty bridge has zero counters");

  CHECK(ezcore_video_texture_publish(texture, kFrameA, 2, 2),
        "first snapshot published");
  pixels = ezcore_video_texture_pixels(texture, &w, &h);
  CHECK(pixels != NULL, "published snapshot is readable");
  CHECK(w == 2 && h == 2, "snapshot has the published dimensions");
  CHECK(check_bytes(pixels, kFrameA, sizeof(kFrameA),
                    "snapshot contains the exact RGBA bytes") == 0,
        "exact RGBA bytes");
  const uint8_t *held = pixels;

  ezcore_video_texture_stats_get(texture, &stats);
  CHECK(stats.frames_published == 1, "one frame published");
  CHECK(stats.buffer_growths == 1, "first allocation counted");
  CHECK(stats.width == 2 && stats.height == 2, "stats carry the frame size");

  /* The renderer may still be reading the buffer after copy_pixels returns.
   * Advancing the core three frames must leave that snapshot untouched. */
  CHECK(ezcore_video_texture_publish(texture, kFrameB, 2, 2),
        "second snapshot published while the first is held");
  CHECK(ezcore_video_texture_publish(texture, kFrameA, 2, 2),
        "third snapshot published while the first is held");
  CHECK(ezcore_video_texture_publish(texture, kFrameB, 2, 2),
        "fourth snapshot published while the first is held");
  pixels = ezcore_video_texture_pixels(texture, &w, &h);
  CHECK(pixels == held, "held snapshot keeps its address while rendering");
  CHECK(check_bytes(pixels, kFrameA, sizeof(kFrameA),
                    "held snapshot was not overwritten by later frames") == 0,
        "held snapshot is tear-free");

  pixels = ezcore_video_texture_pixels(texture, &w, &h);
  CHECK(pixels != NULL, "next callback releases the held snapshot");
  CHECK(check_bytes(pixels, kFrameB, sizeof(kFrameB),
                    "next callback sees the newest published frame") == 0,
        "newest frame is published");

  /* A geometry change must resize exactly once and keep the new pixels. */
  uint8_t wide[4 * 4 * 4];
  for (size_t i = 0; i < sizeof(wide); ++i) wide[i] = (uint8_t)(i + 1);
  CHECK(ezcore_video_texture_publish(texture, wide, 4, 4),
        "larger frame published");
  ezcore_video_texture_stats_get(texture, &stats);
  CHECK(stats.buffer_growths == 2, "geometry change grows the buffer once");
  pixels = ezcore_video_texture_pixels(texture, &w, &h);
  CHECK(w == 4 && h == 4, "new geometry reaches the callback");
  CHECK(check_bytes(pixels, wide, sizeof(wide),
                    "larger frame is intact") == 0,
        "larger frame bytes intact");

  CHECK(ezcore_video_texture_publish(texture, kFrameA, 2, 2),
        "smaller frame published");
  ezcore_video_texture_stats_get(texture, &stats);
  CHECK(stats.buffer_growths == 2, "shrinking reuses the allocated buffer");
  pixels = ezcore_video_texture_pixels(texture, &w, &h);
  CHECK(w == 2 && h == 2, "shrink changes the reported dimensions");
  CHECK(check_bytes(pixels, kFrameA, sizeof(kFrameA),
                    "shrunk frame is intact") == 0,
        "shrunk frame bytes intact");

  /* The real path: a hardware-capable core's latest frame comes from the
   * runtime's video callback and is read through the same snapshot API. */
  if (argc >= 2) {
    char err[1024] = {0};
    ezcore_session *session = ezcore_load(argv[1], err, sizeof(err));
    CHECK(session != NULL, "synthetic core loaded for the live frame check");
    CHECK(ezcore_init(session), "synthetic core initialized");
    CHECK(ezcore_load_game(session, "/dev/null", NULL, 0),
          "synthetic content loaded");
    ezcore_run_frame(session);
    printf("ok: synthetic frame rendered\n");

    CHECK(ezcore_video_texture_publish_session(texture, session),
          "runtime frame published to the texture bridge");
    pixels = ezcore_video_texture_pixels(texture, &w, &h);
    CHECK(pixels != NULL, "runtime snapshot is readable");
    CHECK(w == 256 && h == 240, "runtime snapshot has the core geometry");

    uint8_t *direct = malloc((size_t)w * h * 4);
    CHECK(direct != NULL, "direct copy buffer allocated");
    size_t copied = ezcore_frame_pixels_copy(session, direct, (size_t)w * h * 4);
    CHECK(copied == (size_t)w * h * 4, "direct frame copy succeeded");
    CHECK(check_bytes(pixels, direct, copied,
                      "bridge publishes the same RGBA bytes as the runtime") == 0,
          "bridge matches the runtime frame copy");
    CHECK(pixels[3] == 255, "published alpha is opaque");
    free(direct);
    ezcore_unload(session);
  }

  ezcore_video_texture_destroy(texture);
  printf("PASS: video texture bridge\n");
  return 0;
}

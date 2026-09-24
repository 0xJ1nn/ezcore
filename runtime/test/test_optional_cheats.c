/* Regression test: libretro cheat entry points are independently optional. */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ezcore_runtime.h"

#define TEST_FRAME_WIDTH 256u
#define TEST_FRAME_HEIGHT 240u
#define CHEAT_MARKER_MASK 0xC0u

static int run_case(const char *core_path, unsigned expected_markers,
                    bool expected_dispatch) {
  char err[1024] = {0};
  ezcore_session *session = ezcore_load(core_path, err, sizeof(err));
  if (!session) {
    fprintf(stderr, "core %s failed to load: %s\n", core_path, err);
    return 1;
  }

  void *snapshot = NULL;
  int result = 1;
  if (!ezcore_init(session)) {
    fprintf(stderr, "init failed for %s\n", core_path);
    goto done;
  }
  if (!ezcore_load_game(session, "synthetic", NULL, 0)) {
    fprintf(stderr, "load_game failed for %s\n", core_path);
    goto done;
  }

  /* The fixture exposes the high green bits when each hook is received. */
  ezcore_cheat_reset(session);
  bool dispatched = ezcore_cheat_set(session, 0, true, "0101ABCD");
  if (dispatched != expected_dispatch) {
    fprintf(stderr, "%s dispatch=%d, expected=%d\n", core_path,
            dispatched ? 1 : 0, expected_dispatch ? 1 : 0);
    goto done;
  }

  ezcore_run_frame(session);
  unsigned width = 0, height = 0;
  const uint32_t *pixels = ezcore_frame_pixels(session, &width, &height);
  unsigned markers = 0;
  if (pixels) markers = (unsigned)((pixels[0] >> 8) & CHEAT_MARKER_MASK);
  if (!pixels || width != TEST_FRAME_WIDTH || height != TEST_FRAME_HEIGHT ||
      markers != expected_markers) {
    fprintf(stderr,
            "%s frame/hooks invalid: %ux%u markers=%u, expected=%u\n",
            core_path, width, height, markers, expected_markers);
    goto done;
  }

  int16_t audio[16] = {0};
  if (ezcore_audio_drain(session, audio, 8) == 0) {
    fprintf(stderr, "%s produced no audio after a frame\n", core_path);
    goto done;
  }

  size_t snapshot_size = ezcore_serialize_size(session);
  if (snapshot_size == 0) {
    fprintf(stderr, "%s has no save-state size\n", core_path);
    goto done;
  }
  snapshot = malloc(snapshot_size);
  if (!snapshot || !ezcore_serialize(session, snapshot, snapshot_size)) {
    fprintf(stderr, "%s save-state serialization failed\n", core_path);
    goto done;
  }
  ezcore_run_frame(session);
  if (!ezcore_unserialize(session, snapshot, snapshot_size)) {
    fprintf(stderr, "%s save-state restore failed\n", core_path);
    goto done;
  }

  result = 0;

done:
  free(snapshot);
  ezcore_unload(session);
  return result;
}

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr,
            "usage: test_optional_cheats <core-library> <markers> <dispatch>\n");
    return 2;
  }

  char *end = NULL;
  unsigned long markers = strtoul(argv[2], &end, 0);
  if (!end || *end != '\0' ||
      (markers & ~((unsigned long)CHEAT_MARKER_MASK)) != 0 ||
      (strcmp(argv[3], "0") != 0 && strcmp(argv[3], "1") != 0)) {
    fprintf(stderr, "markers must be 0..192 and dispatch must be 0 or 1\n");
    return 2;
  }

  return run_case(argv[1], (unsigned)markers, strcmp(argv[3], "1") == 0);
}

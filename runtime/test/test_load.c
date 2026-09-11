/* SmokeLoad: dlopen a built core through the ezCore runtime, init it, print
 * identity. Proves build -> verify -> load -> init with no ROM needed. */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ezcore_runtime.h"

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: test_load <core.dylib>\n");
    return 2;
  }
  char err[1024] = {0};
  ezcore_session *s = ezcore_load(argv[1], err, sizeof(err));
  if (!s) {
    fprintf(stderr, "LOAD FAIL: %s\n", err);
    return 1;
  }
  if (!ezcore_init(s)) {
    fprintf(stderr, "INIT FAIL\n");
    return 1;
  }
  /* Optional ROM: first non-flag arg after the core path. Geometry is
   * queried after load (several cores crash on pre-load AV queries). */
  const char *rom_path = NULL;
  bool fullpath = false;
  int frames = 0;
  for (int i = 2; i < argc; i++) {
    if (strcmp(argv[i], "--frames") == 0 && i + 1 < argc) {
      frames = atoi(argv[++i]);
    } else if (strcmp(argv[i], "--fullpath") == 0) {
      fullpath = true;
    } else if (argv[i][0] != '-') {
      rom_path = argv[i];
    }
  }
  if (rom_path) {
    FILE *f = fopen(rom_path, "rb");
    if (!f) {
      fprintf(stderr, "ROM OPEN FAIL: %s\n", rom_path);
      return 1;
    }
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *data = NULL;
    size_t got = 0;
    size_t size = fsize > 0 ? (size_t)fsize : 0;
    if (!fullpath) {
      data = malloc(size > 0 ? size : 1);
      got = data ? fread(data, 1, size, f) : 0;
    }
    fclose(f);
    /* need_fullpath cores (e.g. Gambatte) load from disk: pass path only. */
    const void *payload = fullpath ? NULL : data;
    size_t payload_size = fullpath ? 0 : size;
    if ((!fullpath && (!data || got != size)) ||
        !ezcore_load_game(s, rom_path, payload, payload_size)) {
      fprintf(stderr, "ROM LOAD FAIL: %s\n", rom_path);
      free(data);
      return 1;
    }
    printf("ROM loaded: %s (%ld bytes%s)\n", rom_path, (long)size,
           fullpath ? ", fullpath" : "");
    free(data);
  }
  unsigned w = 0, h = 0;
  double fps = 0;
  ezcore_system_geometry(s, &w, &h, &fps);
  printf("STATUS core='%s' version='%s' geometry=%ux%u@%.2ffps\n",
         ezcore_core_name(s), ezcore_core_version(s), w, h, fps);
  fflush(stdout);
  if (frames > 0) {
    for (int i = 0; i < frames; i++) ezcore_run_frame(s);
    unsigned fw = 0, fh = 0;
    const uint32_t *px = ezcore_frame_pixels(s, &fw, &fh);
    uint64_t sum = 0;
    size_t total = (size_t)fw * fh;
    for (size_t i = 0; i < total; i++) sum += px[i];
    int16_t abuf[4096];
    size_t got = ezcore_audio_drain(s, abuf, 2048);
    int64_t asum = 0;
    for (size_t i = 0; i < got * 2; i++) asum += abuf[i] > 0 ? abuf[i] : -abuf[i];
    printf("FRAMES ran=%d frame=%ux%u pixelsum=%llu audioframes=%zu audioabs=%lld\n",
           frames, fw, fh, (unsigned long long)sum, got, (long long)asum);
  }
  ezcore_unload(s);
  return 0;
}

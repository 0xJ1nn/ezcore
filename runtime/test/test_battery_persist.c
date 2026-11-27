// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* test_battery_persist.c — battery saves reach the disk and come back.
 *
 * libretro puts battery files on the frontend: a core exposes its save RAM
 * through retro_get_memory_data and has nowhere to write it itself. A host
 * that only reads that region proves a save exists and then loses it when the
 * process exits -- the runtime used to do exactly that.
 *
 * The check walks the whole contract against the legacy-SRAM fixture core:
 *   1. a session that writes save RAM leaves a .srm in the save directory,
 *      named after the content, holding the core's own bytes;
 *   2. a later session whose save file has been replaced with a different
 *      pattern sees that pattern in the core's save RAM, i.e. the restore ran
 *      before the first frame rather than after it;
 *   3. a save file of the wrong size is ignored rather than half-copied;
 *   4. with no save directory there is no file at all -- the runtime does not
 *      guess a location.
 *
 * Exit: 0 pass, 1 fail, 9 usage. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <direct.h>
#define MAKE_DIR(p) _mkdir(p)
#else
#include <sys/stat.h>
#define MAKE_DIR(p) mkdir(p, 0755)
#endif

#include "ezcore_runtime.h"
#include "libretro.h"

static char g_err[1024];

static ezcore_session *open_with(const char *core, const char *sysdir,
                                 const char *savedir) {
  ezcore_set_dirs(sysdir, savedir);
  ezcore_session *s = ezcore_load(core, g_err, sizeof(g_err));
  if (!s) {
    fprintf(stderr, "FAIL: load %s: %s\n", core, g_err);
    return NULL;
  }
  if (!ezcore_init(s)) {
    fprintf(stderr, "FAIL: init %s\n", core);
    ezcore_unload(s);
    return NULL;
  }
  return s;
}

static int play(ezcore_session *s, const char *content) {
  FILE *f = fopen(content, "rb");
  if (!f) {
    fprintf(stderr, "FAIL: cannot open %s\n", content);
    return 1;
  }
  char data[256];
  size_t n = fread(data, 1, sizeof(data), f);
  fclose(f);
  if (!ezcore_load_game(s, content, data, n)) {
    fprintf(stderr, "FAIL: load_game %s\n", content);
    return 1;
  }
  ezcore_run_frame(s);
  return 0;
}

static int write_file(const char *path, const char *text) {
  FILE *f = fopen(path, "wb");
  if (!f) return 1;
  size_t len = strlen(text);
  size_t got = fwrite(text, 1, len, f);
  return (got == len && fclose(f) == 0) ? 0 : 1;
}

static int write_bytes(const char *path, const unsigned char *data, size_t len) {
  FILE *f = fopen(path, "wb");
  if (!f) return 1;
  size_t got = fwrite(data, 1, len, f);
  return (got == len && fclose(f) == 0) ? 0 : 1;
}

int main(int argc, char **argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: test_battery_persist <core> <workroot>\n");
    return 9;
  }
  const char *core = argv[1];
  const char *work = argv[2];
  char content[1200], srm[1200];
  if (snprintf(content, sizeof(content), "%s/fixture.synth", work) >=
          (int)sizeof(content) ||
      snprintf(srm, sizeof(srm), "%s/fixture.srm", work) >= (int)sizeof(srm)) {
    fprintf(stderr, "FAIL: work path too long\n");
    return 1;
  }
  MAKE_DIR(work);
  /* The fixture needs a content path to derive a save name from; the bytes
   * are a marker, never emulated data. */
  if (write_file(content, "Synthetic harness fixture. Not game content.\n") != 0) {
    fprintf(stderr, "FAIL: cannot write %s\n", content);
    return 1;
  }
  remove(srm);

  /* 1. A session that writes save RAM leaves it on disk. */
  ezcore_session *s = open_with(core, work, work);
  if (!s) return 1;
  if (play(s, content)) { ezcore_unload(s); return 1; }
  void *mem = NULL;
  size_t mem_len = 0;
  if (!ezcore_get_legacy_memory(s, RETRO_MEMORY_SAVE_RAM, &mem, &mem_len) ||
      !mem_len) {
    fprintf(stderr, "FAIL: the fixture exposed no save RAM to persist\n");
    ezcore_unload(s);
    return 1;
  }
  unsigned char expect[8192];
  if (mem_len > sizeof(expect)) {
    fprintf(stderr, "FAIL: fixture save RAM is %zu bytes, test holds %zu\n",
            mem_len, sizeof(expect));
    ezcore_unload(s);
    return 1;
  }
  memcpy(expect, mem, mem_len);
  const size_t save_len = mem_len;
  ezcore_unload(s);

  FILE *f = fopen(srm, "rb");
  if (!f) {
    fprintf(stderr, "FAIL: no battery file at %s after a writing session\n", srm);
    return 1;
  }
  unsigned char got[8192];
  size_t got_len = fread(got, 1, sizeof(got), f);
  bool extra = fgetc(f) != EOF;
  fclose(f);
  if (got_len != mem_len || extra || memcmp(got, expect, mem_len) != 0) {
    fprintf(stderr,
            "FAIL: battery file holds %zu bytes (extra=%d), the core had %zu, "
            "contents differ\n", got_len, (int)extra, mem_len);
    return 1;
  }
  printf("ok: a written battery save reaches %s (%zu bytes)\n", srm, got_len);

  /* 2. A saved image is in the core's memory before its first frame. */
  unsigned char seeded[8192];
  memset(seeded, 0xC7, save_len);
  seeded[0] = 0x11; /* a pattern the fixture never writes on its own */
  if (write_bytes(srm, seeded, save_len) != 0) {
    fprintf(stderr, "FAIL: cannot seed %s\n", srm);
    return 1;
  }
  s = open_with(core, work, work);
  if (!s) return 1;
  if (play(s, content)) { ezcore_unload(s); return 1; }
  mem = NULL;
  mem_len = 0;
  if (!ezcore_get_legacy_memory(s, RETRO_MEMORY_SAVE_RAM, &mem, &mem_len) ||
      mem_len != save_len) {
    fprintf(stderr, "FAIL: no %zu-byte save RAM after reload\n", save_len);
    ezcore_unload(s);
    return 1;
  }
  if (memcmp(mem, seeded, mem_len) != 0) {
    fprintf(stderr, "FAIL: the saved image did not reach the core's save RAM\n");
    ezcore_unload(s);
    return 1;
  }
  ezcore_unload(s);
  printf("ok: a saved image is restored before the core's first frame\n");

  /* 3. A file of the wrong size is a different cart revision, not a save. */
  unsigned char short_image[64];
  memset(short_image, 0xC7, sizeof(short_image));
  if (write_bytes(srm, short_image, sizeof(short_image)) != 0) {
    fprintf(stderr, "FAIL: cannot seed %s\n", srm);
    return 1;
  }
  s = open_with(core, work, work);
  if (!s) return 1;
  if (play(s, content)) { ezcore_unload(s); return 1; }
  mem = NULL;
  mem_len = 0;
  if (!ezcore_get_legacy_memory(s, RETRO_MEMORY_SAVE_RAM, &mem, &mem_len)) {
    fprintf(stderr, "FAIL: no save RAM after the wrong-size reload\n");
    ezcore_unload(s);
    return 1;
  }
  if (mem_len == sizeof(short_image) ||
      (((unsigned char *)mem)[0] == 0xC7 &&
       ((unsigned char *)mem)[sizeof(short_image) - 1] == 0xC7)) {
    fprintf(stderr, "FAIL: a 64-byte file was spliced into %zu bytes of SRAM\n",
            mem_len);
    ezcore_unload(s);
    return 1;
  }
  ezcore_unload(s);
  printf("ok: a wrong-sized battery file is ignored\n");

  /* 4. No save directory, no persistence: the host decides where saves live. */
  remove(srm);
  s = open_with(core, work, "");
  if (!s) return 1;
  if (play(s, content)) { ezcore_unload(s); return 1; }
  ezcore_unload(s);
  f = fopen(srm, "rb");
  if (f) {
    fclose(f);
    fprintf(stderr, "FAIL: a battery file appeared without a save directory\n");
    return 1;
  }
  printf("ok: no save directory means no battery file\nPASS\n");
  return 0;
}

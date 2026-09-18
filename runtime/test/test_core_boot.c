/* test_core_boot.c — boot a core, run frames, save/restore state, verify.
 *
 * Usage: ./test_core_boot <core_path> <rom_path>
 * Exit codes:
 *   0 = pass
 *   1 = load/init failed
 *   2 = load_game failed
 *   3 = no pixels after 30 frames
 *   4 = save_state failed
 *   5 = load_state failed
 *   9 = crash (should not happen; we fork a child)
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#ifndef _WIN32
#include <unistd.h>
#include <sys/wait.h>
#endif
#include "ezcore_runtime.h"

static int run_boot_test(const char* core_path, const char* rom_path) {
  char err[1024] = {0};
  ezcore_session* s = ezcore_load(core_path, err, sizeof(err));
  if (!s) {
    fprintf(stderr, "  ezcore_load failed: %s\n", err);
    return 1;
  }

  if (!ezcore_init(s)) {
    fprintf(stderr, "  ezcore_init failed\n");
    ezcore_unload(s);
    return 1;
  }

  const char* name = ezcore_core_name(s);
  const char* ver = ezcore_core_version(s);
  printf("  core: %s v%s\n", name, ver);

  ezcore_set_dirs("./test-system", "./test-save");

  FILE* f = fopen(rom_path, "rb");
  if (!f) {
    fprintf(stderr, "  cannot open rom: %s\n", rom_path);
    ezcore_unload(s);
    return 2;
  }
  fseek(f, 0, SEEK_END);
  long rom_size = ftell(f);
  fseek(f, 0, SEEK_SET);
  void* rom_data = malloc(rom_size);
  fread(rom_data, 1, rom_size, f);
  fclose(f);

  if (!ezcore_load_game(s, rom_path, rom_data, rom_size)) {
    fprintf(stderr, "  load_game failed\n");
    free(rom_data);
    ezcore_unload(s);
    return 2;
  }

  unsigned w, h;
  double fps;
  ezcore_system_geometry(s, &w, &h, &fps);
  printf("  geometry: %ux%u @ %.1f fps\n", w, h, fps);

  /* Run 30 frames */
  for (int i = 0; i < 30; i++) ezcore_run_frame(s);

  unsigned rw, rh;
  const uint32_t* px = ezcore_frame_pixels(s, &rw, &rh);
  if (!px) {
    fprintf(stderr, "  no frame pixels\n");
    free(rom_data);
    ezcore_unload(s);
    return 3;
  }

  /* Sum pixels */
  long sum = 0;
  for (unsigned i = 0; i < rw * rh; i++) sum += px[i];
  printf("  pixel sum: %ld\n", sum);
  if (sum == 0) {
    fprintf(stderr, "  zero pixels — nothing rendered\n");
    free(rom_data);
    ezcore_unload(s);
    return 3;
  }

  /* Save state */
  size_t snap_size = ezcore_serialize_size(s);
  if (snap_size == 0) {
    fprintf(stderr, "  serialize_size returned 0\n");
    free(rom_data);
    ezcore_unload(s);
    return 4;
  }
  void* snap = malloc(snap_size);
  if (!ezcore_serialize(s, snap, snap_size)) {
    fprintf(stderr, "  serialize failed\n");
    free(snap);
    free(rom_data);
    ezcore_unload(s);
    return 4;
  }
  printf("  save state: %zu bytes\n", snap_size);

  /* Run more frames to diverge */
  for (int i = 0; i < 10; i++) ezcore_run_frame(s);

  /* Restore */
  if (!ezcore_unserialize(s, snap, snap_size)) {
    fprintf(stderr, "  unserialize failed\n");
    free(snap);
    free(rom_data);
    ezcore_unload(s);
    return 5;
  }

  /* Verify pixels after restore */
  ezcore_run_frame(s);
  px = ezcore_frame_pixels(s, &rw, &rh);
  long sum2 = 0;
  for (unsigned i = 0; i < rw * rh; i++) sum2 += px[i];
  printf("  pixel sum after restore: %ld\n", sum2);

  /* Cheat plumbing */
  ezcore_cheat_reset(s);
  ezcore_cheat_set(s, 0, true, "0101ABCD");

  /* Audio drain */
  int16_t audio[2048];
  size_t audio_frames = ezcore_audio_drain(s, audio, 1024);
  printf("  audio frames drained: %zu\n", audio_frames);

  free(snap);
  free(rom_data);
  ezcore_unload(s);
  return 0;
}

/* Load + init + identify only (no content needed). Used by the core
 * matrix for cores without a test fixture: proves ABI, packaging and
 * init, distinct from full render verification. Exit 0/1 like above. */
static int run_identify_only(const char* core_path) {
  char err[1024] = {0};
  ezcore_session* s = ezcore_load(core_path, err, sizeof(err));
  if (!s) {
    fprintf(stderr, "  ezcore_load failed: %s\n", err);
    return 1;
  }

  if (!ezcore_init(s)) {
    fprintf(stderr, "  ezcore_init failed\n");
    ezcore_unload(s);
    return 1;
  }

  printf("  core: %s v%s\n", ezcore_core_name(s), ezcore_core_version(s));
  ezcore_unload(s);
  return 0;
}

int main(int argc, char** argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: %s <core_path> <rom_path|--identify-only>\n", argv[0]);
    return 1;
  }

  const char* core_path = argv[1];
  const char* rom_path = argv[2];

  printf("=== boot test: %s ===\n", core_path);

#ifdef _WIN32
  /* No fork() on Windows: each core runs as its own CTest process, so a
   * crash is still contained to that core's test case. */
  if (strcmp(rom_path, "--identify-only") == 0) {
    return run_identify_only(core_path);
  }
  return run_boot_test(core_path, rom_path);
#else
  /* Fork a child so a crash doesn't kill the test runner */
  pid_t pid = fork();
  if (pid == 0) {
    /* Child: run the test */
    int rc;
    if (strcmp(rom_path, "--identify-only") == 0) {
      rc = run_identify_only(core_path);
    } else {
      rc = run_boot_test(core_path, rom_path);
    }
    _exit(rc);
  }

  /* Parent: wait for child */
  int status;
  waitpid(pid, &status, 0);

  if (WIFEXITED(status)) {
    int rc = WEXITSTATUS(status);
    if (rc == 0) {
      printf("  ✅ PASSED\n\n");
    } else {
      printf("  ❌ FAILED (exit code %d)\n\n", rc);
    }
    return rc;
  } else if (WIFSIGNALED(status)) {
    int sig = WTERMSIG(status);
    printf("  ❌ CRASHED (signal %d: %s)\n\n", sig, strsignal(sig));
    return 9;
  }

  return 1;
#endif
}

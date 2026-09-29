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
 *   6 = restore did not reproduce the saved frame (state-fidelity gate)
 *   9 = crash (should not happen; we fork a child)
 *
 * What the RENDERS level of docs/MATRIX.md therefore means, as enforced
 * by this file (read this list as the contract; do not let a printed value
 * stand in for a checked one):
 *   - 30 frames run, and ezcore_frame_pixels() is non-NULL;
 *   - the PRE-restore pixel sum is nonzero (exit 3 otherwise);
 *   - serialize and unserialize both succeed (exit 4 / exit 5);
 *   - the pixel sum of the frame reproduced from the restored state
 *     matches the pre-save sum to within
 *     RESTORE_PIXEL_SUM_TOLERANCE_REL (exit 6 otherwise).
 * A core whose unserialize() returns true but leaves a corrupted
 * framebuffer behind no longer earns RENDERS.
 *
 * Exit-code choice for the new failure: 6, and none of the pre-existing
 * codes fits. 3 means "this core renders nothing at all" and is raised
 * before any state is saved, so reusing it would misfile a broken restore
 * as a broken renderer. 4 and 5 are defined as the serialize/unserialize
 * calls themselves returning false — the exit 5 path is a returned-false
 * branch, and this failure happens strictly after that call returned
 * true, so overloading 5 would make the header document a contract the
 * code no longer keeps. 6 is a new, distinct meaning rather than a
 * silent repurposing of an existing one.
 *
 * Still NOT enforced here (printed only, deliberately out of scope for the
 * state-fidelity gate): the drained audio frame count and the
 * cheat_reset/cheat_set calls. MATRIX.md's IDENTIFIES row is likewise
 * unstrengthened here — see its harness-limits section.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#ifndef _WIN32
#include <unistd.h>
#include <sys/wait.h>
#endif
#include "ezcore_runtime.h"

/* How far the post-restore pixel sum may drift from the pre-restore sum
 * before the restore is called broken. Expressed as a fraction of the
 * baseline's magnitude, so it scales with resolution and pixel depth
 * instead of being a magic absolute delta.
 *
 * Why a tolerance at all, and why exactly this one:
 *
 * The pre-restore sum is taken after 30 frames, and the post-restore sum
 * is taken after 30 + 10 + 1 frames from a state saved at frame 30. A
 * faithful restore replays frame 30 exactly, so the two sums describe the
 * same frame and SHOULD be equal bit for bit. They are not required to be
 * equal by this gate because the harness cannot distinguish "the restore
 * lost pixel data" from "the core's renderer is not a pure function of
 * the emulated state" — a core with a time-, host-clock- or RNG-seeded
 * element (blitters reading a host timer, uninitialised RAM rendering as
 * noise) can legitimately redraw a visually equivalent frame with
 * different bytes. Exact equality would grade those cores RED for a defect
 * they do not have, and the fix would then be to weaken the gate, not the
 * core.
 *
 * Why 2% and not 0%, and not a looser 10%:
 *  - 0% conflates the two failure classes above and is the thing this
 *    change exists to stop doing (MATRIX.md's caveat: fidelity is
 *    "unproven"), so it is too weak a contract to ship;
 *  - a sum-based check averages over the whole frame, so a small fraction
 *    of genuinely corrupted pixels moves it very little: at NES-class
 *    256x240, 2% of the sum is on the order of a thousand flipped
 *    low-valued pixels, which is far more than the drift a faithful,
 *    deterministic-but-timed renderer produces (a handful of sprite or
 *    scanline pixels) and far less than total framebuffer loss, which
 *    moves the sum by 100%;
 *  - 10% would let a core that loses, say, a fifth of the framebuffer
 *    still pass. 2% keeps the signal well above the noise floor while
 *    staying far below the "half the screen is gone" regime.
 *
 * This is a deliberately loose smoke gate, NOT a pixel-exactness proof. A
 * core that swaps two equally-weighted sprites can still pass it. Tighten
 * it to 0 for a specific core only alongside evidence that core is
 * bit-exact, never globally and never silently. */
#define RESTORE_PIXEL_SUM_TOLERANCE_REL 0.02

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

  /* Sum pixels. int64_t, not long: the total is a sum of rw*rh uint32_t
   * values, which overflows a 32-bit long on any non-trivial resolution
   * (and `long` is 32-bit on Windows/LLP64, where this harness also runs).
   * An overflowing sum would make the comparison below meaningless. */
  int64_t sum = 0;
  for (unsigned i = 0; i < rw * rh; i++) sum += px[i];
  printf("  pixel sum: %lld\n", (long long)sum);
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
  if (!px) {
    /* The restore left no framebuffer at all. Dereferencing it below would
     * segfault and be reported as exit 9 (crash), which would misfile a
     * failed restore as a crashed core. Same exit 6 as a wrong sum: this is
     * a restore-fidelity failure, not a renderer failure. */
    fprintf(stderr, "  no frame pixels after restore\n");
    free(snap);
    free(rom_data);
    ezcore_unload(s);
    return 6;
  }
  int64_t sum2 = 0;
  for (unsigned i = 0; i < rw * rh; i++) sum2 += px[i];
  printf("  pixel sum after restore: %lld\n", (long long)sum2);

  /* THE GATE (docs/MATRIX.md RENDERS "save/restore"). serialize() and
   * unserialize() both returning true only proves the round trip was
   * callable; it says nothing about whether the restored state reproduces
   * the frame that was saved. Before this check the post-restore sum was
   * printed and discarded, so a core that silently corrupted the
   * framebuffer on restore still earned RENDERS.
   *
   * A baseline always exists here: sum == 0 returned 3 above, so control
   * only reaches this point with a nonzero pre-restore sum. The sum != 0
   * guard is kept as a cheap, explicit statement of that precondition
   * rather than relied on implicitly, so this block can never divide by or
   * normalise against a zero baseline if the code above is ever reordered.
   *
   * Comparison is |sum2 - sum| <= |sum| * RESTORE_PIXEL_SUM_TOLERANCE_REL,
   * computed in double to keep the multiply from overflowing. See the
   * constant's comment for why this is a relative tolerance rather than
   * exact equality. */
  if (sum != 0) {
    double baseline = (double)sum;
    double allowed = (baseline < 0 ? -baseline : baseline) *
                     RESTORE_PIXEL_SUM_TOLERANCE_REL;
    double drift = (double)sum2 - baseline;
    if (drift < 0) drift = -drift;
    if (drift > allowed) {
      fprintf(stderr,
              "  restore did not reproduce the saved frame: pixel sum %lld "
              "vs %lld (drift %.4f > %.2f%% of baseline)\n",
              (long long)sum2, (long long)sum,
              baseline != 0.0 ? (drift / (baseline < 0 ? -baseline : baseline)) * 100.0 : 0.0,
              RESTORE_PIXEL_SUM_TOLERANCE_REL * 100.0);
      free(snap);
      free(rom_data);
      ezcore_unload(s);
      return 6;
    }
    printf("  restore check: ok (within %.2f%%)\n",
           RESTORE_PIXEL_SUM_TOLERANCE_REL * 100.0);
  }

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

// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* test_core_boot.c — boot a core, run frames, save/restore state, verify.
 *
 * Usage: ./test_core_boot <core_path> <rom_path>
 *        EZCORE_BOOT_OPTIONS="key=value;..." optionally sets core options
 *        before the game loads (see apply_boot_options).
 *        EZCORE_FRAME_PPM=/path/frame.ppm optionally saves the frame used for
 *        the pre-restore pixel sum as a binary PPM (P6, maxval 255, RGB) and
 *        prints one "frame:" line with its size, pixel sum and SHA-256 over
 *        the RGB bytes. The hash is the evidence: it lets a stored frame be
 *        compared across runs without keeping the pixels in someone's head.
 *        With the variable set, a frame that cannot be written is a failure
 *        of the evidence, not a warning (exit 7); with it unset this line and
 *        this verdict do not exist.
 * Exit codes:
 *   0 = pass
 *   1 = load/init failed
 *   2 = load_game failed
 *   3 = no pixels after 30 frames
 *   4 = save_state failed
 *   5 = load_state failed
 *   6 = restore did not reproduce the saved frame (state-fidelity gate)
 *   7 = frame capture could not be written (only when requested)
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
 * Exit 7 is likewise new: a missing or unwritable frame destination is a
 * failure to record evidence, not a verdict on the core. Folding it into 3 or
 * 6 would report "no rendering" or "broken restore" for a core that did
 * neither, so the capture failure gets its own code and only exists when the
 * destination was asked for.
 *
 * Still NOT enforced here (printed only, deliberately out of scope for the
 * state-fidelity gate): the drained audio frame count and the
 * cheat_reset/cheat_set calls. MATRIX.md's IDENTIFIES row is likewise
 * unstrengthened here — see its harness-limits section.
 */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
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

/* Optional core options for this boot, from the environment:
 *   EZCORE_BOOT_OPTIONS="key=value;key=value"
 * Applied after init and before load_game, the same point the app applies
 * them, because many cores read their options only inside retro_load_game
 * (a software-renderer choice, typically). Unset means no options: every
 * existing invocation behaves exactly as before. A key the core does not
 * declare fails the boot (exit 1) rather than being ignored, so evidence
 * recorded "with option X" really had option X. */
static bool apply_boot_options(ezcore_session* s) {
  const char* spec = getenv("EZCORE_BOOT_OPTIONS");
  if (!spec || !*spec) return true;
  char buf[2048];
  snprintf(buf, sizeof(buf), "%s", spec);
  char* save = NULL;
  for (char* pair = strtok_r(buf, ";", &save); pair;
       pair = strtok_r(NULL, ";", &save)) {
    char* eq = strchr(pair, '=');
    if (!eq || eq == pair) {
      fprintf(stderr, "  malformed option '%s' (want key=value)\n", pair);
      return false;
    }
    *eq = '\0';
    if (!ezcore_set_core_option(s, pair, eq + 1)) {
      fprintf(stderr, "  core does not declare option '%s'\n", pair);
      return false;
    }
    printf("  option: %s=%s\n", pair, eq + 1);
  }
  return true;
}

/* Frame count (EZCORE_BOOT_FRAMES, default [fallback]) and optional 60 fps
 * pacing (EZCORE_BOOT_PACE=1), see run_boot_test. */
static int boot_frames(int fallback) {
  const char *v = getenv("EZCORE_BOOT_FRAMES");
  int n = v ? atoi(v) : 0;
  return n > 0 ? n : fallback;
}

static void run_frames(ezcore_session *s, int n) {
  const char *pace = getenv("EZCORE_BOOT_PACE");
  for (int i = 0; i < n; i++) {
    ezcore_run_frame(s);
    if (pace && *pace == '1') {
      struct timespec ts = {0, 16666667};
      nanosleep(&ts, NULL);
    }
  }
}

/* SHA-256 over the RGB payload only. Local and self-contained: the harness
 * must produce the same digest on a machine with no crypto library installed,
 * and the digest must be reproducible by hashing the stored PPM's pixel bytes
 * with any standard tool. The PPM header is excluded because the dimensions
 * already appear on the frame line. */
static uint32_t sha_rotr32(uint32_t x, unsigned n) {
  return (x >> n) | (x << (32 - n));
}

static void sha256_block(uint32_t h[8], const unsigned char block[64]) {
  static const uint32_t k[64] = {
      0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u,
      0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
      0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
      0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
      0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
      0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
      0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
      0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
      0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
      0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
      0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u,
      0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
      0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u,
      0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
      0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
      0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};
  uint32_t w[64];
  for (unsigned i = 0; i < 16; i++) {
    w[i] = ((uint32_t)block[i * 4] << 24) |
           ((uint32_t)block[i * 4 + 1] << 16) |
           ((uint32_t)block[i * 4 + 2] << 8) | (uint32_t)block[i * 4 + 3];
  }
  for (unsigned i = 16; i < 64; i++) {
    uint32_t s0 = sha_rotr32(w[i - 15], 7) ^ sha_rotr32(w[i - 15], 18) ^
                  (w[i - 15] >> 3);
    uint32_t s1 = sha_rotr32(w[i - 2], 17) ^ sha_rotr32(w[i - 2], 19) ^
                  (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  uint32_t a = h[0], b = h[1], c = h[2], d = h[3];
  uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];
  for (unsigned i = 0; i < 64; i++) {
    uint32_t s1 = sha_rotr32(e, 6) ^ sha_rotr32(e, 11) ^ sha_rotr32(e, 25);
    uint32_t ch = (e & f) ^ ((~e) & g);
    uint32_t t1 = hh + s1 + ch + k[i] + w[i];
    uint32_t s0 = sha_rotr32(a, 2) ^ sha_rotr32(a, 13) ^ sha_rotr32(a, 22);
    uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
    uint32_t t2 = s0 + maj;
    hh = g; g = f; f = e; e = d + t1;
    d = c; c = b; b = a; a = t1 + t2;
  }
  h[0] += a; h[1] += b; h[2] += c; h[3] += d;
  h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

static void sha256_rgb(const unsigned char* data, size_t len, char out[65]) {
  uint32_t h[8] = {0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
                   0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u};
  uint64_t bits = (uint64_t)len * 8;
  size_t pos = 0;
  while (len - pos >= 64) {
    sha256_block(h, data + pos);
    pos += 64;
  }
  unsigned char block[64] = {0};
  size_t rem = len - pos;
  memcpy(block, data + pos, rem);
  block[rem] = 0x80;
  if (rem >= 56) {
    sha256_block(h, block);
    memset(block, 0, sizeof(block));
  }
  for (unsigned i = 0; i < 8; i++)
    block[56 + i] = (unsigned char)(bits >> (56 - 8 * i));
  sha256_block(h, block);
  for (unsigned i = 0; i < 8; i++)
    snprintf(out + i * 8, 9, "%08x", h[i]);
  out[64] = '\0';
}

/* Optionally record the frame just measured by the pre-restore pixel sum as a
 * binary PPM (P6, maxval 255). The frame is XRGB8888, so red lives in bits
 * 16-23 and blue in bits 0-7; each pixel becomes R,G,B bytes in that order.
 * Returns 0 when nothing was requested or the write succeeded, nonzero when a
 * requested frame could not be captured. A silent skip would let a render
 * claim cite a frame that was never stored, so failure is loud and fatal. */
static int write_frame_ppm(const uint32_t* px, unsigned w, unsigned h,
                           int64_t sum) {
  const char* path = getenv("EZCORE_FRAME_PPM");
  if (!path || !*path) return 0;

  FILE* out = fopen(path, "wb");
  if (!out) {
    fprintf(stderr, "  error: cannot open EZCORE_FRAME_PPM '%s': %s\n",
            path, strerror(errno));
    return 1;
  }

  if (w == 0 || h == 0 || (size_t)w > SIZE_MAX / (size_t)h ||
      (size_t)w * (size_t)h > SIZE_MAX / 3) {
    fprintf(stderr,
            "  error: frame %ux%u is empty or too large to write as PPM\n",
            w, h);
    fclose(out);
    return 1;
  }

  size_t count = (size_t)w * (size_t)h;
  unsigned char* rgb = malloc(count * 3);
  if (!rgb) {
    fprintf(stderr, "  error: out of memory writing EZCORE_FRAME_PPM '%s'\n",
            path);
    fclose(out);
    return 1;
  }
  for (size_t i = 0; i < count; i++) {
    rgb[i * 3] = (unsigned char)((px[i] >> 16) & 0xFF);
    rgb[i * 3 + 1] = (unsigned char)((px[i] >> 8) & 0xFF);
    rgb[i * 3 + 2] = (unsigned char)(px[i] & 0xFF);
  }

  char digest[65];
  sha256_rgb(rgb, count * 3, digest);
  int header = fprintf(out, "P6\n%u %u\n255\n", w, h);
  size_t written = fwrite(rgb, 3, count, out);
  int closed = fclose(out);
  free(rgb);
  if (header < 0 || written != count || closed != 0) {
    fprintf(stderr, "  error: failed to write EZCORE_FRAME_PPM '%s'\n", path);
    return 1;
  }
  printf("frame: %ux%u sum=%lld sha256=%s file=%s\n", w, h,
         (long long)sum, digest, path);
  return 0;
}

static int run_boot_test(const char* core_path, const char* rom_path) {
  char err[1024] = {0};
  /* Set the content directories before the core is loaded and initialized,
   * matching the app (the worker calls setDirs before service.start).
   * Cores may read the system directory during retro_init: LRPS2 scans its
   * BIOS folder there to build its core-option list. Setting it later meant
   * the scan ran against the spawn CWD instead. */
  ezcore_set_dirs("./test-system", "./test-save");
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

  if (!apply_boot_options(s)) {
    ezcore_unload(s);
    return 1;
  }

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

  /* Run 30 frames. EZCORE_BOOT_FRAMES and EZCORE_BOOT_PACE=1 (60 fps) are
   * for cores that boot on their own thread in real time (PPSSPP): 30
   * unpaced frames end before such a core has drawn anything. */
  run_frames(s, boot_frames(30));

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

  /* The runtime's video callback keeps only the latest frame and reallocates
   * it whenever a core presents a different size, so (px, rw, rh) is one
   * consistent snapshot even for cores that resize mid-boot. Failure to store
   * a requested frame is fatal (exit 7), but only when a path was requested:
   * with EZCORE_FRAME_PPM unset neither the write nor this branch exists. */
  if (write_frame_ppm(px, rw, rh, sum) != 0) {
    free(rom_data);
    ezcore_unload(s);
    return 7;
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
  run_frames(s, 10);

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
    /* _exit() bypasses stdio flushing, so every printf the child made is
     * still buffered when the process image is torn down and is discarded.
     * All the evidence this harness exists to produce -- geometry, pixel
     * sum, save-state size, the restore verdict -- went to stdout, so
     * `ctest -V` printed nothing and a real boot was indistinguishable
     * from a harness that silently did nothing. _exit is still correct
     * (it must not run the parent's atexit handlers); it just needs the
     * flush done for it. */
    fflush(NULL);
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

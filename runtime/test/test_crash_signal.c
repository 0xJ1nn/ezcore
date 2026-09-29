/* test_crash_signal.c — automated proof of the P6 exit-code contract.
 *
 * `crash_libretro` (runtime/test/crash_core.c) is a core that faults on
 * demand, but until this test existed it was built and never run by CTest:
 * nothing checked that the fixture still faults, and nothing checked that
 * the harness turns a real SIGSEGV into exit code 9. The spike's central
 * claim was therefore only ever demonstrated by hand.
 *
 * This test drives both halves of that contract from one binary:
 *
 *   1. CLEAN  — EZCORE_CRASH_AFTER unset. The core must load, init, load a
 *               game and render frames like any other core and exit 0. This
 *               is the "the fixture is genuinely usable, and a pass here
 *               means the crash below came from the trigger and not from a
 *               core that is broken for other reasons" control.
 *
 *   2. CRASH  — EZCORE_CRASH_AFTER=3, set in the child only. The child must
 *               die on SIGSEGV, and the parent must classify that signal
 *               death as 9, using the same WIFEXITED/WIFSIGNALED mapping
 *               test_core_boot.c already uses (test_core_boot.c:200-212).
 *               9 is the number kCrashExitCode in
 *               lib/emu/supervisor_session.dart claims, so this is where
 *               the C harness and the Dart classifier are pinned together.
 *
 * Isolation: each case runs in its own fork()ed child, so the faulting
 * grandchild can never take the test runner down with it, and neither case
 * can see or disturb the other's environment — see the setenv/unsetenv
 * placement in main().
 *
 * Scope, stated plainly: this is a FIXTURE-level test. It proves the crash
 * fixture faults and that the fork harness reports a signal death as 9. It
 * proves nothing about the app: ContainmentMode.supervisedProcess still
 * throws UnsupportedContainmentError, so no core is actually isolated from
 * a faulting one at app level. See .ezcore/P6_SPIKE_NOTES.md.
 *
 * Exit: 0 = pass, 1 = a case failed, 9 = usage error (mirrors the
 * convention in test_input_reset.c / test_core_boot.c).
 */
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef _WIN32
#include <sys/wait.h>
#include <unistd.h>
#endif

#include "ezcore_runtime.h"

/* Frames driven in the clean case, and the frame the crash case is armed to
 * fault on. CRASH_AFTER must be well under FRAMES so the crash child reaches
 * the fault instead of quietly completing its run. */
#define FRAMES 30
#define CRASH_AFTER 3

/* The contract under test: test_core_boot.c returns 9 for WIFSIGNALED, and
 * the Dart classifier treats exitCode 9 as `crashed`. */
#define CRASH_EXIT_CODE 9

/* Assertion convention copied from test_input_reset.c. */
#define CHECK(cond, msg)                                                       \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, "FAIL: %s\n", msg);                                      \
      return 1;                                                                \
    } else {                                                                   \
      printf("ok: %s\n", msg);                                                 \
    }                                                                          \
  } while (0)

/* Loads the crash core through the real dynload path and runs FRAMES frames.
 * Always executed inside a forked child, so a fault here costs the child and
 * not the runner. Return codes deliberately match test_core_boot.c's child
 * vocabulary so a pre-fault failure is distinguishable from "did not fault":
 *   0 = clean run
 *   1 = load/init failed
 *   2 = load_game failed
 *   3 = no frame pixels
 * The crash case never returns at all when the fixture works. */
static int drive_core(const char *core_path) {
  char err[1024] = {0};
  ezcore_session *s = ezcore_load(core_path, err, sizeof(err));
  if (!s) {
    fprintf(stderr, "  ezcore_load failed: %s\n", err);
    return 1;
  }
  if (!ezcore_init(s)) {
    fprintf(stderr, "  ezcore_init failed\n");
    ezcore_unload(s);
    return 1;
  }
  if (!ezcore_load_game(s, "/dev/null", NULL, 0)) {
    fprintf(stderr, "  load_game failed\n");
    ezcore_unload(s);
    return 2;
  }

  for (int i = 0; i < FRAMES; i++) ezcore_run_frame(s);

  unsigned w = 0, h = 0;
  const uint32_t *px = ezcore_frame_pixels(s, &w, &h);
  if (!px || w == 0 || h == 0) {
    fprintf(stderr, "  no frame pixels (%ux%u)\n", w, h);
    ezcore_unload(s);
    return 3;
  }

  ezcore_unload(s);
  return 0;
}

#ifndef _WIN32
/* The classifier, transcribed from test_core_boot.c:200-212 so this test
 * asserts the same mapping the boot harness actually uses. A signal death is
 * reported as CRASH_EXIT_CODE (9), not as a raw signal number. */
static int classify_status(int status) {
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  if (WIFSIGNALED(status)) return CRASH_EXIT_CODE;
  return 1; /* stopped, or some state the harness does not model */
}

/* Forks a child that runs drive_core() with EZCORE_CRASH_AFTER arranged for
 * that child alone, and reports the child's wait status back to main(). */
static pid_t fork_case(const char *core_path, const char *crash_after) {
  pid_t pid = fork();
  if (pid == 0) {
    /* Child branch. The trigger is set *here*, after fork, so the test
     * process itself never carries EZCORE_CRASH_AFTER and the clean case
     * and the crash case cannot contaminate each other. The clean case
     * additionally unsets it, so the test is hermetic even if the developer
     * exporting EZCORE_CRASH_AFTER in their shell started ctest from it. */
    if (crash_after != NULL) {
      setenv("EZCORE_CRASH_AFTER", crash_after, 1);
    } else {
      unsetenv("EZCORE_CRASH_AFTER");
    }
    _exit(drive_core(core_path));
  }
  return pid;
}
#endif /* !_WIN32 */

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: test_crash_signal <crash_libretro.so>\n");
    return 9;
  }

  const char *core_path = argv[1];

  printf("=== P6 crash fixture: exit-code contract ===\n");
  printf("  core: %s\n", core_path);

#ifdef _WIN32
  /* No fork() on Windows, and a signal death here would take the whole test
   * process with it — there is no WIFSIGNALED to classify with either. So
   * this platform gets the clean half only: it still proves the fixture
   * builds and loads as a normal core on Windows, and says out loud that the
   * signal-classification half did not run rather than quietly reporting a
   * pass. test_core_boot.c takes the same position (no fork there either:
   * each core is its own CTest process, so a crash is contained to that
   * test case). See "No cross-platform verification" in P6_SPIKE_NOTES.md. */
  int clean_rc = drive_core(core_path);
  if (clean_rc != 0) {
    fprintf(stderr, "clean case aborted at step %d before reaching any frame\n",
            clean_rc);
    return 1;
  }
  CHECK(clean_rc == 0,
        "clean case: crash core loads and renders 30 frames (exit 0)");
  printf("SKIPPED: signal-classification case needs fork()/WIFSIGNALED (POSIX "
         "only)\n");
  printf("\n✅ CRASH FIXTURE CLEAN-PATH TEST PASSED (crash half skipped)\n");
  return 0;
#else
  /* --- Case 1: CLEAN. The fixture must be usable as an ordinary core. --- */
  pid_t clean_pid = fork_case(core_path, NULL);
  if (clean_pid < 0) {
    perror("fork");
    return 1;
  }

  int clean_status = 0;
  if (waitpid(clean_pid, &clean_status, 0) < 0) {
    perror("waitpid");
    return 1;
  }
  if (WIFSIGNALED(clean_status)) {
    /* Fatal to the diagnosis: if the fixture faults with the trigger unset,
     * a later "it crashed" result proves nothing about EZCORE_CRASH_AFTER. */
    fprintf(stderr,
            "clean case died on signal %d (%s) with EZCORE_CRASH_AFTER unset "
            "— the fixture faults unconditionally\n",
            WTERMSIG(clean_status), strsignal(WTERMSIG(clean_status)));
    return 1;
  }
  int clean_rc = classify_status(clean_status);
  if (clean_rc != 0) {
    fprintf(stderr, "clean case failed at step %d (see child output above)\n",
            clean_rc);
    return 1;
  }
  CHECK(clean_rc == 0,
        "case 1 clean: WIFEXITED(0) classifies as 0, core ran 30 frames");

  /* --- Case 2: CRASH. A real signal must be classified as 9. --- */
  pid_t crash_pid = fork_case(core_path, "3");
  if (crash_pid < 0) {
    perror("fork");
    return 1;
  }

  int crash_status = 0;
  if (waitpid(crash_pid, &crash_status, 0) < 0) {
    perror("waitpid");
    return 1;
  }

  if (!WIFSIGNALED(crash_status)) {
    if (WIFEXITED(crash_status)) {
      fprintf(stderr,
              "crash case exited %d instead of dying on a signal — "
              "EZCORE_CRASH_AFTER=3 no longer makes the fixture fault "
              "(or it failed at step %d before frame %d)\n",
              WEXITSTATUS(crash_status), WEXITSTATUS(crash_status), CRASH_AFTER);
    } else {
      fprintf(stderr, "crash case ended in an unmodelled wait state\n");
    }
    return 1;
  }

  int sig = WTERMSIG(crash_status);
  printf("  crash child died on signal %d (%s)\n", sig, strsignal(sig));
  CHECK(sig == SIGSEGV,
        "case 2 crash: EZCORE_CRASH_AFTER=3 produces a real SIGSEGV");

  int classified = classify_status(crash_status);
  /* Assert the LITERAL 9, not CRASH_EXIT_CODE. classify_status returns
   * CRASH_EXIT_CODE, so comparing the two is a tautology: redefining the
   * macro would leave this check passing. The contract under test is the
   * number 9, because that is what test_core_boot.c's fork harness reports
   * and what the Dart classifier's kCrashExitCode matches. */
  CHECK(classified == 9,
        "case 2 crash: WIFSIGNALED classifies as exit code 9 (kCrashExitCode)");

  printf("\n✅ CRASH FIXTURE EXIT-CODE CONTRACT PROVEN\n");
  return 0;
#endif
}

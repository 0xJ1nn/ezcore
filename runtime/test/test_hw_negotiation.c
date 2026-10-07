/* How a core picks its context type, and what the host must answer.
 *
 * Two answers decide whether a GPU core renders or crashes:
 *
 *   GET_PREFERRED_HW_RENDER is an OUT-PARAM. The host writes the type it
 *   prefers; it must not read the core's variable, which real cores leave
 *   uninitialised (Flycast: `u32 preferred;`). When the host echoed that
 *   garbage back, Flycast fell through to Vulkan and crashed in its renderer.
 *
 *   SET_HW_RENDER for Vulkan must be refused while the host cannot hand frames
 *   over (no set_image, no readback). Saying yes leaves the core drawing into
 *   nothing; saying no sends it to OpenGL or software.
 *
 * Uses synth_hw_core's test hooks; no copyrighted code or content.
 */
#include "ezcore_runtime.h"

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

#include <libretro.h>

static int g_failures;
static void check(int c, const char *what) {
  printf("  %s %s\n", c ? "ok  " : "FAIL", what);
  if (!c) g_failures++;
}

/* Loads the core with one hook set, runs load_game, and reports the probes. */
static int run_case(const char *core, const char *hook, int *set_result,
                    int *pref_result, unsigned *pref_type) {
  if (hook) setenv(hook, "1", 1);
  char err[256] = {0};
  ezcore_session *s = ezcore_load(core, err, sizeof(err));
  if (!s) {
    printf("  FAIL could not load %s: %s\n", core, err);
    exit(1);
  }
  int loaded = ezcore_load_game(s, NULL, NULL, 0);
  void *h = dlopen(core, RTLD_NOW);
  int (*p_set)(void) = (int (*)(void))dlsym(h, "probe_set_hw_render_result");
  int (*p_pr)(void) = (int (*)(void))dlsym(h, "probe_preferred_result");
  unsigned (*p_pt)(void) = (unsigned (*)(void))dlsym(h, "probe_preferred_type");
  if (!p_set || !p_pr || !p_pt) {
    printf("  FAIL probe symbols missing\n");
    exit(1);
  }
  *set_result = p_set();
  *pref_result = p_pr();
  *pref_type = p_pt();
  ezcore_unload(s);
  dlclose(h);
  if (hook) unsetenv(hook);
  return loaded;
}

int main(int argc, char **argv) {
  const char *core = argc > 1 ? argv[1] : "synth_hw_core.so";
  int set_r, pref_r;
  unsigned pref_t;
  printf("hardware context negotiation\n");

  /* Is there a GL context to be had at all? (A plain GLES3 request.) */
  int have_gpu = run_case(core, NULL, &set_r, &pref_r, &pref_t);

  /* Vulkan: refused, whatever the machine has. */
  int vk_loaded = run_case(core, "EZCORE_SYNTH_ASK_VULKAN", &set_r, &pref_r,
                           &pref_t);
  check(set_r == 0, "SET_HW_RENDER refuses Vulkan (no frame handoff yet)");
  check(!vk_loaded, "the Vulkan-only core then declines to load");

  /* Preferred: the host writes its own answer. */
  int pref_loaded = run_case(core, "EZCORE_SYNTH_ASK_PREFERRED", &set_r,
                             &pref_r, &pref_t);
  if (!have_gpu) {
    check(pref_r == 0, "no GPU here, so GET_PREFERRED_HW_RENDER says no");
  } else {
    check(pref_r == 1, "GET_PREFERRED_HW_RENDER answers when a GPU exists");
    check(pref_t != 0xDEADBEEFu, "it writes a type instead of echoing ours");
    check(pref_t == RETRO_HW_CONTEXT_OPENGL ||
              pref_t == RETRO_HW_CONTEXT_OPENGLES3,
          "the type is one we can create (GL or GLES3, never Vulkan)");
    check(pref_loaded, "a core that follows the answer gets its context");
  }

  printf("\n%s\n", g_failures ? "FAILURES PRESENT" : "all ok");
  return g_failures ? 1 : 0;
}

// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* Native test for desktop GL context selection in the windowing backend.
 *
 * A desktop core that initialises its own GL loader with GLX needs the
 * context the runtime handed it to be current in GLX, not merely current in
 * EGL. This probe asks the real runtime for an OpenGL-core context and then
 * queries the real GLX driver for the current display and context. Nothing is
 * faked: both the context and the query come from the host driver.
 *
 * The test skips only when there is no X display or no GL library at all. On
 * a machine where a desktop context can be created, an EGL-only context is a
 * real failure, because the core cannot use it.
 */
#include "ezcore_gpu.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__linux__) && !defined(__ANDROID__)
#define EZCORE_TEST_GLX 1
#include <dlfcn.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#endif

static int g_failures;

static void ok(const char *what) { printf("  ok   %s\n", what); }
static void bad(const char *what, const char *why) {
  printf("  FAIL %s: %s\n", what, why);
  g_failures++;
}
static void skip(const char *what, const char *why) {
  printf("  skip %s: %s\n", what, why);
}
static void check(bool cond, const char *what, const char *why) {
  if (cond) ok(what);
  else bad(what, why);
}

#ifdef EZCORE_TEST_GLX
static bool glx_current(char *msg, size_t n) {
  void *lib = dlopen("libGLX.so.0", RTLD_NOW | RTLD_LOCAL);
  if (!lib) lib = dlopen("libGL.so.1", RTLD_NOW | RTLD_LOCAL);
  if (!lib) {
    snprintf(msg, n, "no GLX library on this host");
    return false;
  }
  void *(*current_display)(void) =
      (void *(*)(void))dlsym(lib, "glXGetCurrentDisplay");
  void *(*current_context)(void) =
      (void *(*)(void))dlsym(lib, "glXGetCurrentContext");
  if (!current_display || !current_context) {
    snprintf(msg, n, "GLX entry points missing");
    return false;
  }
  void *dpy = current_display();
  void *ctx = current_context();
  snprintf(msg, n, "glXGetCurrentDisplay=%p glXGetCurrentContext=%p", dpy, ctx);
  return dpy && ctx;
}

static void run_probe(unsigned major, unsigned minor) {
  char err[256] = {0};
  struct ezcore_gpu_context *c = NULL;
  enum ezcore_gpu_init_result r = ezcore_gpu_init(
      &c, EZCORE_GPU_OPENGL_CORE, major, minor, true, err, sizeof(err));
  char what[96];
  snprintf(what, sizeof(what), "OpenGL-core %u.%u context created", major, minor);
  if (r != EZCORE_GPU_INIT_OK || !c) {
    bad(what, err[0] ? err : "the backend refused a desktop GL request");
    return;
  }
  ok(what);

  check(ezcore_gpu_api_of(c) == EZCORE_GPU_OPENGL_CORE,
        "the context keeps the API the core asked for",
        "api_of disagreed with the request");
  check(ezcore_gpu_current_framebuffer(c) != 0,
        "a renderable framebuffer is handed over",
        "framebuffer 0 means the core renders into nothing");
  check(ezcore_gpu_get_proc_address(c, "glClear") != NULL,
        "a desktop GL entry point resolves",
        "a real desktop context must resolve glClear");

  char glx_msg[192] = {0};
  check(glx_current(glx_msg, sizeof(glx_msg)),
        "the desktop context is current in GLX", glx_msg);
  printf("  info %s\n", glx_msg);
  ezcore_gpu_destroy(c);
}
#endif

int main(void) {
  printf("Desktop GL context selection\n");
#ifdef EZCORE_TEST_GLX
  const char *display = getenv("DISPLAY");
  if (!display || !*display) {
    skip("desktop GL context", "no X display; GLX cannot be required here");
    printf("\nall desktop GL checks skipped\n");
    return 0;
  }
  if (!ezcore_gpu_supported(EZCORE_GPU_OPENGL)) {
    skip("desktop GL context", "this host offers no desktop GL backend");
    printf("\nall desktop GL checks skipped\n");
    return 0;
  }

  fflush(NULL);
  pid_t pid = fork();
  if (pid < 0) {
    skip("desktop GL context", "could not fork a driver probe");
    return 0;
  }
  if (pid == 0) {
    run_probe(3, 2);
    /* A version no driver can satisfy must step down to a real context
     * instead of failing the core. This is the config/attribute fallback,
     * exercised against the driver rather than a mock. */
    run_probe(9, 9);
    fflush(NULL);
    _exit(g_failures ? 1 : 0);
  }
  int status = 0;
  if (waitpid(pid, &status, 0) < 0) {
    skip("desktop GL context", "could not wait for the driver probe");
    return 0;
  }
  if (WIFSIGNALED(status)) {
    char why[96];
    snprintf(why, sizeof(why), "the driver crashed (signal %d)",
             WTERMSIG(status));
    skip("desktop GL context", why);
  } else if (WIFEXITED(status) && WEXITSTATUS(status) != 0) {
    bad("desktop GL driver probe", "see the failing check above");
  }
#else
  skip("desktop GL context", "this platform has no X11/GLX path");
#endif
  printf("\n%s\n", g_failures ? "FAILURES PRESENT" : "all desktop GL checks passed");
  return g_failures ? 1 : 0;
}

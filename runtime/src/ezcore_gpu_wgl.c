/* Windows render context: WGL backend (ADR-018, Option B).
 *
 * NOT YET IMPLEMENTED. This file exists so that a Windows build configures and
 * links -- CMake selects exactly one platform backend, and a missing file would
 * make the whole runtime fail to build on Windows, which is worse than a
 * runtime with no GPU support.
 *
 * What it does instead is report EZCORE_GPU_INIT_UNAVAILABLE from every entry
 * point, so on Windows today:
 *   - every CPU core works exactly as before;
 *   - a core that asks for hardware rendering is told SET_HW_RENDER is
 *     unavailable and falls back to software, instead of crashing or hanging;
 *   - the GPU command returns the same "not built in" answer the Linux build
 *     gives when EGL is missing, so callers need no platform branches.
 *
 * That is the contract that makes the "works on all platforms without rework"
 * claim testable: the seam is identical everywhere, and filling a backend in
 * later changes one file without touching the dispatcher, env_cb, or Dart.
 *
 * To implement: create an HDC + pixel format + WGL context, resolve the GL
 * entry points through wglGetProcAddress (never link opengl32.lib, for the
 * reason in ezcore_gpu_egl.c), build the FBO in ezcore_gpu_make_framebuffer
 * once that is shared with the EGL path, and handle context loss through
 * ezcore_gpu_platform_notify_reset.
 *
 * The sharp edge, recorded so it is not discovered late: a machine with no
 * opengl32.dll has no path, and Microsoft's own answer for modern Windows is
 * ANGLE (translating GLES to D3D11). That is a new dependency and therefore a
 * maintainer decision under project.md §26 -- not something to be introduced
 * quietly in an implementation of this file.
 */
#include "ezcore_gpu_internal.h"

#include <stdio.h>

static void set_err(char *err, size_t n, const char *msg) {
  if (err && n) snprintf(err, n, "%s", msg);
}

enum ezcore_gpu_init_result ezcore_gpu_platform_init(
    struct ezcore_gpu_context **out, enum ezcore_gpu_api api,
    unsigned version_major, unsigned version_minor, bool headless, char *err,
    size_t err_len) {
  (void)api; (void)version_major; (void)version_minor; (void)headless;
  if (out) *out = NULL;
  set_err(err, err_len,
          "the Windows WGL backend is not implemented yet; cores requesting "
          "hardware rendering fall back to software");
  return EZCORE_GPU_INIT_UNAVAILABLE;
}

void ezcore_gpu_platform_destroy(struct ezcore_gpu_context *ctx) { (void)ctx; }

bool ezcore_gpu_platform_is_current(struct ezcore_gpu_context *ctx) {
  (void)ctx;
  return false;
}

unsigned ezcore_gpu_platform_current_framebuffer(struct ezcore_gpu_context *ctx) {
  (void)ctx;
  return 0;
}

void *ezcore_gpu_platform_get_proc_address(struct ezcore_gpu_context *ctx,
                                           const char *name) {
  (void)ctx; (void)name;
  return NULL;
}

void ezcore_gpu_platform_notify_reset(struct ezcore_gpu_context *ctx) {
  if (ctx) ctx->generation++;
}

bool ezcore_gpu_platform_supported(enum ezcore_gpu_api api) {
  (void)api;
  return false;
}

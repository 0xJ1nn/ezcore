/* macOS render context: CGL/NSOpenGL backend (ADR-018, Option B).
 *
 * NOT YET IMPLEMENTED, for the same reason and with the same contract as
 * ezcore_gpu_wgl.c: the file must exist so a macOS build configures and links,
 * and every entry point reports EZCORE_GPU_INIT_UNAVAILABLE so that
 *   - CPU cores are unaffected,
 *   - a core asking for hardware rendering is told it is unavailable and
 *     falls back to software rather than crashing,
 *   - callers see the same "not built in" answer as any other backend.
 *
 * Recorded now, because macOS is where the choice is least obvious. Two
 * relevant facts, both verifiable in the libretro header rather than assumed:
 *
 *  - rcp64 references no vkCreateInstance and 3199 GL symbols, and dualscreen
 *    15, so both are GL. They are the two cores this backend would unblock.
 *  - The four Vulkan cores (geometry1, powercube, portcomp, dreamarc) are
 *    unblocked by the portable Vulkan backend, which needs no macOS-specific
 *    code at all: libvulkan.dylib is resolved through the loader. So macOS gets
 *    Vulkan first for free, and this file is the smaller remaining job.
 *
 * To implement: NSOpenGLContext / CGL, resolve GL through
 * NSOpenGLContext::getProcAddress: (never link OpenGL.framework for the reason
 * in ezcore_gpu_egl.c), and share the FBO builder with the EGL path so the two
 * cannot drift.
 *
 * The sharp edge: macOS 10.14+ deprecates OpenGL. Apple Silicon has no OpenGL
 * at all. So on an M-series Mac this backend can only ever serve whatever the
 * core can do without GL -- which is a reason Vulkan is the long-run path on
 * Apple hardware, not an implementation detail to defer.
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
          "the macOS CGL backend is not implemented yet; cores requesting "
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

bool ezcore_gpu_platform_resize(struct ezcore_gpu_context *ctx, int w, int h) {
  (void)ctx; (void)w; (void)h;
  return false; /* no GL context on this backend yet */
}

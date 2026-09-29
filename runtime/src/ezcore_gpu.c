/* Backend dispatch for the GPU render context (ADR-018, Option B).
 *
 * This is the ONLY file that knows which platform implementation is in play.
 * Everything above it -- env_cb in runtime.c, and the C test harness -- talks
 * to ezcore_gpu.h and never names a backend. CMake compiles exactly one of
 * ezcore_gpu_egl.c (Linux/Android), ezcore_gpu_wgl.c (Windows) or
 * ezcore_gpu_cgl.c (macOS) plus ezcore_gpu_vulkan.c, which is portable
 * because it goes through the Vulkan loader rather than linking libvulkan.
 *
 * The fallback here is what keeps the promise in ezcore_gpu.h honest: if no
 * platform backend is compiled in, every entry point reports
 * EZCORE_GPU_INIT_UNAVAILABLE instead of crashing or lying, so a build
 * without GPU support still runs every CPU core.
 */
#include "ezcore_gpu_internal.h"

#include <stdio.h>
#include <string.h>

/* Provided by exactly one platform backend, or by none. Weak-ish: declared
 * here, defined in a backend translation unit. Backends return
 * EZCORE_GPU_INIT_UNAVAILABLE rather than being absent so a backend that
 * cannot create a context on this machine is distinguishable from one that
 * was not compiled in. */

enum ezcore_gpu_init_result ezcore_gpu_platform_init(
    struct ezcore_gpu_context **out, enum ezcore_gpu_api api,
    unsigned version_major, unsigned version_minor, bool headless, char *err,
    size_t err_len);

void ezcore_gpu_platform_destroy(struct ezcore_gpu_context *ctx);
bool ezcore_gpu_platform_is_current(struct ezcore_gpu_context *ctx);
unsigned ezcore_gpu_platform_current_framebuffer(struct ezcore_gpu_context *ctx);
void *ezcore_gpu_platform_get_proc_address(struct ezcore_gpu_context *ctx,
                                           const char *name);
void ezcore_gpu_platform_notify_reset(struct ezcore_gpu_context *ctx);
bool ezcore_gpu_platform_supported(enum ezcore_gpu_api api);

/* Vulkan is a separate backend from the windowing context: it needs no EGL
 * surface on the desktop path, and it is the backend four of the six blocked
 * cores actually ask for. Kept behind the same interface so the caller sees
 * one thing. */
enum ezcore_gpu_init_result ezcore_gpu_vulkan_init(
    struct ezcore_gpu_context **out, unsigned version_major,
    unsigned version_minor, bool headless, char *err, size_t err_len);
void ezcore_gpu_vulkan_destroy(struct ezcore_gpu_context *ctx);
bool ezcore_gpu_vulkan_is_current(struct ezcore_gpu_context *ctx);
enum ezcore_gpu_api ezcore_gpu_vulkan_api(struct ezcore_gpu_context *ctx);
unsigned ezcore_gpu_vulkan_current_framebuffer(struct ezcore_gpu_context *ctx);
void *ezcore_gpu_vulkan_get_proc_address(struct ezcore_gpu_context *ctx,
                                         const char *name);
void ezcore_gpu_vulkan_notify_reset(struct ezcore_gpu_context *ctx);
bool ezcore_gpu_vulkan_supported(void);

static void set_err(char *err, size_t err_len, const char *msg) {
  if (err && err_len) {
    snprintf(err, err_len, "%s", msg);
  }
}

enum ezcore_gpu_init_result ezcore_gpu_init(struct ezcore_gpu_context **out,
                                            enum ezcore_gpu_api api,
                                            unsigned version_major,
                                            unsigned version_minor,
                                            bool headless, char *err,
                                            size_t err_len) {
  if (!out) {
    set_err(err, err_len, "ezcore_gpu_init: out is NULL");
    return EZCORE_GPU_INIT_FAILED;
  }
  *out = NULL;

  if (api == EZCORE_GPU_NONE) {
    set_err(err, err_len, "ezcore_gpu_init: api is EZCORE_GPU_NONE");
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }

  /* A core that asks for Vulkan gets Vulkan or nothing. Falling back to a
   * windowing/GL context here would hand it a context TYPE it did not
   * request, which for a Vulkan core means every call in its renderer goes to
   * a null dispatch stub and the screen stays black with no error. So the
   * Vulkan answer is final, and the reason it failed is preserved rather than
   * overwritten -- the first version fell through to the platform backend,
   * which replaced "vkCreateDevice failed" with "eglCreateContext failed" and
   * made a working Vulkan driver look like a broken EGL. */
  if (api == EZCORE_GPU_VULKAN) {
    return ezcore_gpu_vulkan_init(out, version_major, version_minor, headless,
                                  err, err_len);
  }

  return ezcore_gpu_platform_init(out, api, version_major, version_minor,
                                  headless, err, err_len);
}

void ezcore_gpu_destroy(struct ezcore_gpu_context *ctx) {
  if (!ctx) return;
  if (ezcore_gpu_api_of(ctx) == EZCORE_GPU_VULKAN) {
    ezcore_gpu_vulkan_destroy(ctx);
    return;
  }
  ezcore_gpu_platform_destroy(ctx);
}

bool ezcore_gpu_is_current(struct ezcore_gpu_context *ctx) {
  if (!ctx) return false;
  if (ctx->backend == EZCORE_BACKEND_VULKAN) {
    return ezcore_gpu_vulkan_is_current(ctx);
  }
  return ezcore_gpu_platform_is_current(ctx);
}

enum ezcore_gpu_api ezcore_gpu_api_of(struct ezcore_gpu_context *ctx) {
  /* Read the shared header, not a backend accessor: the tag is the one field
   * every backend agrees on. */
  return ctx ? ctx->api : EZCORE_GPU_NONE;
}

unsigned ezcore_gpu_current_framebuffer(struct ezcore_gpu_context *ctx) {
  if (!ctx) return 0;
  if (ctx->backend == EZCORE_BACKEND_VULKAN) {
    return ezcore_gpu_vulkan_current_framebuffer(ctx);
  }
  return ezcore_gpu_platform_current_framebuffer(ctx);
}

void *ezcore_gpu_get_proc_address(struct ezcore_gpu_context *ctx,
                                  const char *name) {
  if (!ctx || !name) return NULL;
  if (ctx->backend == EZCORE_BACKEND_VULKAN) {
    return ezcore_gpu_vulkan_get_proc_address(ctx, name);
  }
  return ezcore_gpu_platform_get_proc_address(ctx, name);
}

void ezcore_gpu_notify_reset(struct ezcore_gpu_context *ctx) {
  if (!ctx) return;
  if (ctx->backend == EZCORE_BACKEND_VULKAN) {
    ezcore_gpu_vulkan_notify_reset(ctx);
    return;
  }
  ezcore_gpu_platform_notify_reset(ctx);
}

bool ezcore_gpu_supported(enum ezcore_gpu_api api) {
  if (api == EZCORE_GPU_NONE) return false;
  if (api == EZCORE_GPU_VULKAN) return ezcore_gpu_vulkan_supported();
  return ezcore_gpu_platform_supported(api);
}

const char *ezcore_gpu_api_name(enum ezcore_gpu_api api) {
  switch (api) {
    case EZCORE_GPU_NONE: return "none";
    case EZCORE_GPU_OPENGL: return "opengl";
    case EZCORE_GPU_OPENGLES2: return "opengles2";
    case EZCORE_GPU_OPENGL_CORE: return "opengl-core";
    case EZCORE_GPU_OPENGLES3: return "opengles3";
    case EZCORE_GPU_VULKAN: return "vulkan";
  }
  return "unknown";
}

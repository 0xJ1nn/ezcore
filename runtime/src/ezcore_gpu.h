/* GPU render-context surface for the ezCORE runtime (ADR-018, Option B).
 *
 * WHY THIS FILE EXISTS
 * --------------------
 * A libretro core that defaults to a GPU renderer calls
 * RETRO_ENVIRONMENT_SET_HW_RENDER and asks the host for a render context.
 * ezCORE's env_cb answers 13 of 93 environment commands and that was not one
 * of them, so six cores (geometry1, rcp64, dualscreen, portcomp, dreamarc,
 * powercube) could not run at all. See docs/DECISIONS.md ADR-018.
 *
 * WHAT THIS IS NOT
 * -----------------
 * It is NOT a public ezCORE ABI. Nothing here is exported from
 * libezcore_runtime.so; the whole surface is internal to the runtime, and
 * libretro cores reach it only through env_cb. That is deliberate: a public
 * ABI would mean an EZCORE_ABI_VERSION bump, and a new link-time dependency on
 * EGL or Vulkan, both of which the maintainer has ruled out (ADR-018 Q6).
 *
 * The design rule that matters: ONE backend-agnostic context owns the surface.
 * Per-platform code (EGL vs WGL vs CGL, and the Vulkan loader) lives behind
 * this interface and nowhere else, so a new platform is a new implementation
 * of these functions and never a change to the caller. That is what "works on
 * all platforms without rework" has to mean structurally, not just as
 * intention.
 *
 * Both backends are supported because the blocked cores split between them:
 * geometry1/powercube/portcomp/dreamarc want Vulkan (they reference
 * vkCreateInstance), rcp64 and dualscreen are GL-only (0 vkCreateInstance
 * symbols, 3199 and 15 GL symbols respectively). A Vulkan-only or GL-only
 * implementation unblocks at most four or two of the six.
 */
#ifndef EZCORE_GPU_H
#define EZCORE_GPU_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Mirrors the parts of libretro's enum the runtime must not depend on being
 * vendored for, so this header stays independently testable. Values are
 * fixed by the libretro ABI and must not be renumbered. */
enum ezcore_gpu_api {
  EZCORE_GPU_NONE = 0,
  EZCORE_GPU_OPENGL = 1,      /* RETRO_HW_CONTEXT_OPENGL            */
  EZCORE_GPU_OPENGLES2 = 2,   /* RETRO_HW_CONTEXT_OPENGLES2         */
  EZCORE_GPU_OPENGL_CORE = 3, /* RETRO_HW_CONTEXT_OPENGL_CORE       */
  EZCORE_GPU_OPENGLES3 = 4,   /* RETRO_HW_CONTEXT_OPENGLES3         */
  EZCORE_GPU_VULKAN = 6       /* RETRO_HW_CONTEXT_VULKAN            */
};

/* Opaque to every caller. One implementation per platform, chosen at build
 * time; no caller ever sees behind it. */
struct ezcore_gpu_context;

/* The functions env_cb hands to a core. These signatures mirror libretro's
 * retro_hw_render_callback exactly where a typedef exists, because the values
 * are passed straight through to the core. */
typedef void (*ezcore_hw_context_reset_t)(void);
typedef unsigned (*ezcore_hw_get_current_framebuffer_t)(void);
typedef void (*ezcore_hw_get_proc_address_t)(void);

/* Result of an init attempt. INIT_UNSUPPORTED is deliberately distinct from
 * INIT_FAILED: "this machine cannot do GL at all" must make the host answer
 * false to SET_HW_RENDER so a core can fall back to software rendering,
 * whereas "we tried and it broke" is a host error worth surfacing. Conflating
 * them is how a frontend ends up refusing to boot a core that would have run
 * fine in software. */
enum ezcore_gpu_init_result {
  EZCORE_GPU_INIT_OK = 0,
  EZCORE_GPU_INIT_UNSUPPORTED = 1, /* no driver / no display: answer false */
  EZCORE_GPU_INIT_FAILED = 2,      /* driver present but unusable: error  */
  EZCORE_GPU_INIT_UNAVAILABLE = 3  /* not built in at all                */
};

/* ---------------------------------------------------------------- lifecycle */

/* Creates the render context for [api] at [version_major].[version_minor].
 *
 * [headless] asks for a context with no window system surface, which is what
 * ctest and the capture path need; it is also the only mode available on a
 * machine with no compositor. A headless context is still a real context:
 * cores render into an FBO exactly as they would on screen.
 *
 * Never returns NULL for EZCORE_GPU_INIT_UNSUPPORTED -- the caller must be
 * able to answer SET_HW_RENDER false and let the core fall back, so a NULL
 * return with an unset enum is not a valid state. */
enum ezcore_gpu_init_result ezcore_gpu_init(struct ezcore_gpu_context **out,
                                             enum ezcore_gpu_api api,
                                             unsigned version_major,
                                             unsigned version_minor,
                                             bool headless,
                                             char *err, size_t err_len);

/* Destroys the context. NULL-safe, and safe to call twice. */
void ezcore_gpu_destroy(struct ezcore_gpu_context *ctx);

/* ------------------------------------------------------------------ queries */

bool ezcore_gpu_is_current(struct ezcore_gpu_context *ctx);
enum ezcore_gpu_api ezcore_gpu_api_of(struct ezcore_gpu_context *ctx);

/* The framebuffer a core should render into. For GL this is a real GLuint
 * name; for Vulkan it is the image index the core should write. */
unsigned ezcore_gpu_current_framebuffer(struct ezcore_gpu_context *ctx);

/* Resolves a GL/GLES entry point by name for the core, through the
 * context's own get_proc_address. Returns NULL when absent. */
void *ezcore_gpu_get_proc_address(struct ezcore_gpu_context *ctx,
                                   const char *name);

/* Called by the core from its context_reset callback. In GL this is a no-op
 * (the context is already current); for Vulkan it is where swapchain
 * resources are recreated, because a Vulkan device loss invalidates them
 * without the object surviving. */
void ezcore_gpu_notify_reset(struct ezcore_gpu_context *ctx);

/* True when this build can create a context for [api] at all, without
 * creating one. Lets the host answer GET_PREFERRED_HW_RENDER honestly and
 * lets a caller avoid a pointless init attempt on a machine with no GPU. */
bool ezcore_gpu_supported(enum ezcore_gpu_api api);

/* Human-readable name for logs and error messages. Never NULL. */
const char *ezcore_gpu_api_name(enum ezcore_gpu_api api);

/* The Vulkan queue family the context negotiated, or 0 for a non-Vulkan
 * context. Exposed so the test can assert the host picked a family that
 * advertises graphics support: the original stride bug made it read past the
 * end of the array and settle on whatever followed, and nothing observable
 * distinguished a right family from a wrong one. */
unsigned ezcore_gpu_vulkan_queue_family(struct ezcore_gpu_context *ctx);

#endif /* EZCORE_GPU_H */

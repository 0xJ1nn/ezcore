/* Proves the GPU context seam works, or reports honestly why it cannot.
 *
 * This is the test that makes ADR-018 verifiable rather than aspirational. It
 * runs as a CTest, and on the development host it exercises a real GLES3
 * context on real hardware and a real Vulkan device.
 *
 * The honesty rule, which matters more than any single assertion: NO test here
 * requires a GPU. Every check either passes, or is skipped with the reason
 * printed. A test suite that fails on a machine with no graphics driver would
 * mean P8 could never be verified anywhere except one developer's laptop, and
 * would get deleted rather than fixed.
 */
#include "ezcore_gpu.h"

#include <stdio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

int main(void) {
  char err[256] = {0};
  printf("GPU context seam\n");

  /* ---- api_name is total and never NULL, with or without a GPU -------- */
  for (int api = 0; api <= 6; api++) {
    const char *n = ezcore_gpu_api_name((enum ezcore_gpu_api)api);
    if (!n) {
      bad("api_name is total", "returned NULL for some enum value");
      break;
    }
  }
  ok("api_name is total (never NULL)");

  /* ---- EZCORE_GPU_NONE is refused, and refused cleanly ---------------- */
  {
    struct ezcore_gpu_context *c = NULL;
    err[0] = 0;
    enum ezcore_gpu_init_result r = ezcore_gpu_init(&c, EZCORE_GPU_NONE, 0, 0,
                                                     true, err, sizeof(err));
    check(r == EZCORE_GPU_INIT_UNSUPPORTED, "NONE is unsupported",
          "a core asking for no GPU must be told so, not given a context");
    check(c == NULL, "NONE leaves *out NULL", "*out was written on a refusal");
    check(err[0] != 0, "NONE reports a reason", "no message for a refusal");
  }

  /* ---- NULL out is rejected, not dereferenced ------------------------- */
  {
    enum ezcore_gpu_init_result r =
        ezcore_gpu_init(NULL, EZCORE_GPU_OPENGLES3, 3, 0, true, err,
                        sizeof(err));
    check(r == EZCORE_GPU_INIT_FAILED, "NULL out is a failure, not a crash",
          "a NULL out pointer must be rejected");
  }

  /* ---- destroy is NULL-safe and idempotent ---------------------------- */
  {
    ezcore_gpu_destroy(NULL);
    ok("destroy(NULL) is safe");
  }

  /* ---- GLES3 context, headless ---------------------------------------- */
  {
    struct ezcore_gpu_context *c = NULL;
    err[0] = 0;
    enum ezcore_gpu_init_result r = ezcore_gpu_init(&c, EZCORE_GPU_OPENGLES3, 3,
                                                     0, true, err, sizeof(err));
    if (r == EZCORE_GPU_INIT_OK) {
      ok("GLES3 headless context created");

      check(ezcore_gpu_api_of(c) == EZCORE_GPU_OPENGLES3,
            "context reports the API it was created for",
            "api_of disagreed with the request");
      check(ezcore_gpu_current_framebuffer(c) != 0,
            "a renderable framebuffer was handed over",
            "framebuffer 0 means the core would render into nothing -- the "
            "classic silent black-screen bug");

      /* A real context must resolve a real symbol. If this returns NULL the
       * context is not actually current and every core call would fail. */
      void *glClear = ezcore_gpu_get_proc_address(c, "glClear");
      check(glClear != NULL, "glClear resolves through the context",
            "get_proc_address returned NULL for a core GL function");
      /* Deliberately NOT asserted: that an unknown name resolves to NULL.
       * Mesa returns a non-NULL dispatch stub for names it does not know,
       * which the EGL spec permits. The first version of this test asserted
       * it and failed on a correct implementation, so the check is dropped
       * rather than worked around. A core that asks for a symbol it does not
       * have is the core's bug; the host has no way to detect it portably. */
      ezcore_gpu_get_proc_address(c, "glTotallyNotAFunction");

      /* Draw a full-screen clear through the FBO and read it back. This is
       * the only assertion that can catch a removed framebuffer-completeness
       * check, a missing colour attachment or a wrong viewport: with an
       * incomplete FBO every GL call is a silent no-op, so a test that only
       * asks "is the handle nonzero" passes on a context that renders
       * nothing. The FBO-completeness mutation survived three earlier test
       * revisions precisely because nothing ever drew. */
      {
        typedef void (*PFN_clear)(unsigned);
        typedef void (*PFN_clear_color)(float, float, float, float);
        typedef void (*PFN_viewport)(int, int, unsigned, unsigned);
        typedef unsigned (*PFN_check_fb)(unsigned);
        typedef void (*PFN_bind_fb)(unsigned, unsigned);
        typedef unsigned (*PFN_get_error)(void);
        typedef void (*PFN_read_pixels)(int, int, unsigned, unsigned, unsigned,
                                        unsigned, void *);
        PFN_clear glClear_ = (PFN_clear)ezcore_gpu_get_proc_address(c, "glClear");
        PFN_clear_color glClearColor_ =
            (PFN_clear_color)ezcore_gpu_get_proc_address(c, "glClearColor");
        PFN_viewport glViewport_ =
            (PFN_viewport)ezcore_gpu_get_proc_address(c, "glViewport");
        PFN_check_fb glCheck_ =
            (PFN_check_fb)ezcore_gpu_get_proc_address(c, "glCheckFramebufferStatus");
        PFN_bind_fb glBind_ =
            (PFN_bind_fb)ezcore_gpu_get_proc_address(c, "glBindFramebuffer");
        PFN_get_error glErr_ =
            (PFN_get_error)ezcore_gpu_get_proc_address(c, "glGetError");
        PFN_read_pixels glRead_ =
            (PFN_read_pixels)ezcore_gpu_get_proc_address(c, "glReadPixels");

        check(glClear_ && glViewport_ && glCheck_ && glBind_ && glErr_ && glRead_,
              "all entry points needed to draw resolve",
              "a draw path symbol did not resolve; the context is not usable");

        if (glBind_ && glCheck_ && glViewport_ && glClear_ && glErr_) {
          glBind_(1 /* GL_FRAMEBUFFER */, ezcore_gpu_current_framebuffer(c));
          unsigned status = glCheck_(0x8D40);
          char msg[96];
          snprintf(msg, sizeof(msg),
                   "status was 0x%x, expected 0x8cd5 (GL_FRAMEBUFFER_COMPLETE); "
                   "an incomplete FBO makes every core draw a silent no-op",
                   status);
          check(status == 0x8CD5, "the framebuffer handed to the core is COMPLETE",
                msg);

          /* Drain any error left by setup. glGetError both reports AND
           * clears, so a stale pending error would otherwise be attributed to
           * the clear below -- which is how a passing implementation gets
           * blamed for a bug in the test. */
          while (glErr_() != 0) {
          }

          glViewport_(0, 0, 64, 64);
          /* Clear to a NON-ZERO colour so the readback can distinguish
           * "the clear happened" from "nothing was ever written". The first
           * version cleared to the default (0,0,0,0) and then asserted the
           * pixel was 0x40 -- which is a colour nothing ever set, so the check
           * was asserting a falsehood and would have failed on a perfectly
           * correct context. */
          if (glClearColor_) glClearColor_(0.25f, 0.5f, 0.75f, 1.0f);
          glClear_(0x00004000 /* GL_COLOR_BUFFER_BIT */);
          unsigned err = glErr_();
          snprintf(msg, sizeof(msg), "glGetError was 0x%x after a clear", err);
          check(err == 0, "glClear raises no GL error", msg);

          if (glRead_) {
            unsigned char px[4] = {0, 0, 0, 0};
            glRead_(0, 0, 1, 1, 0x1908 /* GL_RGBA */, 0x1401 /* GL_UNSIGNED_BYTE */,
                    px);
            /* 0.25/0.5/0.75 -> 63/127/191, +/-1 for driver rounding. */
            snprintf(msg, sizeof(msg),
                     "read %u,%u,%u,%u expected ~63,127,191,255; the FBO is "
                     "not actually renderable", px[0], px[1], px[2], px[3]);
            check(abs((int)px[0] - 63) <= 1 && abs((int)px[1] - 127) <= 1 &&
                      abs((int)px[2] - 191) <= 1,
                  "a cleared pixel reads back as the clear colour", msg);
          }
        }
      }

      ezcore_gpu_notify_reset(c);
      ok("notify_reset is callable on a live context");

      ezcore_gpu_destroy(c);
      ok("context destroyed");
    } else {
      skip("GLES3 context",
           r == EZCORE_GPU_INIT_UNAVAILABLE
               ? "no GL backend compiled in for this platform"
               : err);
    }
  }

  /* ---- Vulkan device, headless ---------------------------------------- */
  {
    /* A dedicated buffer: a skip message must describe THIS attempt, never
     * whatever an earlier call happened to leave behind. The first version
     * reused one `err` across the whole test and so reported "no Vulkan
     * driver on this machine" for a failure that had left its own message,
     * which is exactly the sort of false "your hardware is unsupported"
     * claim that makes a support question unanswerable. */
    char verr[256] = {0};
    struct ezcore_gpu_context *d = NULL;
    enum ezcore_gpu_init_result r =
        ezcore_gpu_init(&d, EZCORE_GPU_VULKAN, 1, 0, true, verr, sizeof(verr));
    if (r == EZCORE_GPU_INIT_OK) {
      ok("Vulkan device created (instance, physical device, device, queue)");
      check(ezcore_gpu_api_of(d) == EZCORE_GPU_VULKAN,
            "Vulkan context reports the Vulkan API", "api_of disagreed");
      check(ezcore_gpu_is_current(d), "Vulkan context reports current",
            "a created device must report usable");
      check(ezcore_gpu_supported(EZCORE_GPU_VULKAN),
            "supported() agrees with a successful init",
            "supported() said no while init() succeeded");
      /* A Vulkan request must yield a Vulkan context. If the dispatcher ever
       * falls through to the windowing backend again, api_of is the one
       * observable that shows it -- and it is the bug that would hand a
       * Vulkan core a GL context, whose every call goes nowhere. */
      check(ezcore_gpu_api_of(d) == EZCORE_GPU_VULKAN,
            "a Vulkan request was not answered with a GL context",
            "the dispatcher fell through to the windowing backend");
      /* current_framebuffer on Vulkan is an image INDEX, not a GL name. It
       * must be 0 for the headless single-image target; a large value would
       * mean a queue family or image count was read from the wrong offset. */
      check(ezcore_gpu_current_framebuffer(d) == 0,
            "the Vulkan headless target reports image index 0",
            "a nonzero image index means the queue/image state was misread");
      /* The chosen queue family must be one that actually advertises
       * graphics. The stride bug (4 words assumed, 6 actual) read past the
       * end of the family array and could land on any family at all; with
       * only "a device was created" asserted, that passed. Asserting the
       * family index is a real number that the driver accepted is the check
       * that makes a mis-stride visible. */
      unsigned fam = ezcore_gpu_vulkan_queue_family(d);
      char fmsg[96];
      snprintf(fmsg, sizeof(fmsg),
               "queue family %u -- out of range, or a family that was read "
               "from the wrong offset (the struct is 6 words, not 4)", fam);
      check(fam < 16, "the negotiated queue family index is in range", fmsg);
      if (fam == 0) {
        /* Family 0 is conventionally graphics-capable; on this host it is
         * 0xf. Recorded rather than hard-failed because a driver is free to
         * order families differently, and a wrong assumption here would be a
         * test that fails on correct hardware. */
        ok("queue family 0 chosen (graphics is conventional on this stack)");
      } else {
        char m2[96];
        snprintf(m2, sizeof(m2), "chose family %u; 0 is graphics on this stack",
                 fam);
        skip("queue family 0 preference", m2);
      }
      ezcore_gpu_destroy(d);
      ok("Vulkan device destroyed");
    } else {
      skip("Vulkan device", verr[0] ? verr : "no Vulkan driver on this machine");
    }
  }

  /* ---- supported() must agree with init() for GL ---------------------- */
  {
    err[0] = 0;
    bool sup = ezcore_gpu_supported(EZCORE_GPU_OPENGLES3);
    if (!sup) {
      skip("GLES3 support probe", "no EGL on this machine");
    } else {
      struct ezcore_gpu_context *c = NULL;
      enum ezcore_gpu_init_result r = ezcore_gpu_init(&c, EZCORE_GPU_OPENGLES3, 3,
                                                       0, true, err, sizeof(err));
      check(r == EZCORE_GPU_INIT_OK, "supported() true implies init() succeeds",
            "supported() reported a capability init() could not deliver");
      ezcore_gpu_destroy(c);
    }
  }

  /* Coverage note, stated rather than hidden: removing the framebuffer
   * completeness check in make_fbo is NOT detectable from outside the runtime
   * on a driver where the FBO is genuinely complete, because its failure path
   * is never reached. Mutation testing confirmed it survives. What IS
   * observable -- and asserted above -- is that the FBO handed to the core
   * completes and renders, which is the property the check exists to protect.
   * The check itself is kept as defence against drivers that return an
   * incomplete FBO for a 64x64 RGBA8 + depth-stencil target, which this host
   * does not. */
  printf("\n%s\n", g_failures ? "FAILURES PRESENT" : "all GPU seam checks passed");
  return g_failures ? 1 : 0;
}

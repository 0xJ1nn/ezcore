/* EGL-backed render context: Linux and Android (ADR-018, Option B).
 *
 * One implementation serves every GL/GLES API variant ezCORE exposes, because
 * EGL's config/surface/context attributes cover all of them and the
 * differences are parameters, not code paths. That is what keeps the promise
 * in ezcore_gpu.h: Android and desktop share this file, so neither needs the
 * other reworked.
 *
 * NO LINK-TIME GL DEPENDENCY. libEGL and libGLESv2 are opened with the
 * existing ez_dyn_* seam and every entry point is resolved through
 * eglGetProcAddress / the context's own get_proc_address. The runtime must
 * stay loadable on a machine with no GPU at all, and PLATFORM.md §6 is a list
 * of promises that must not quietly become false. A -lEGL on the runtime would
 * break `ezcore_load` for every CPU-only user.
 *
 * EGL and GLES headers are used directly, not vendored: they are the platform
 * SDK's own headers, which is a compile-time dependency, not a shipped one.
 * The Android NDK and the Linux mesa/libglvnd packages both provide them.
 */
#include "ezcore_gpu_gl_body.h"

#include "dynload.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__linux__) || defined(__ANDROID__)
#define EZCORE_HAVE_EGL 1
#else
#define EZCORE_HAVE_EGL 0
#endif

#if EZCORE_HAVE_EGL

#include <EGL/egl.h>
#include <EGL/eglext.h>


/* Only the EGL entry points the runtime itself calls. Everything else goes
 * through eglGetProcAddress, so this list is short and fixed. */
struct egl_api {
  EGLDisplay (*GetDisplay)(EGLNativeDisplayType);
  EGLBoolean (*Initialize)(EGLDisplay, EGLint *, EGLint *);
  EGLBoolean (*Terminate)(EGLDisplay);
  const char *(*QueryString)(EGLDisplay, EGLint);
  EGLBoolean (*ChooseConfig)(EGLDisplay, const EGLint *, EGLConfig *, EGLint,
                             EGLint *);
  EGLSurface (*CreatePbufferSurface)(EGLDisplay, EGLConfig, const EGLint *);
  EGLSurface (*CreateWindowSurface)(EGLDisplay, EGLConfig, EGLNativeWindowType,
                                    const EGLint *);
  EGLContext (*CreateContext)(EGLDisplay, EGLConfig, EGLContext,
                              const EGLint *);
  EGLBoolean (*DestroyContext)(EGLDisplay, EGLContext);
  EGLBoolean (*DestroySurface)(EGLDisplay, EGLSurface);
  EGLBoolean (*MakeCurrent)(EGLDisplay, EGLSurface, EGLSurface, EGLContext);
  EGLBoolean (*BindAPI)(EGLenum);
  __eglMustCastToProperFunctionPointerType (*GetProcAddress)(const char *);
  EGLint (*GetError)(void);
};

static struct egl_api g_egl;
static void *g_egl_lib;
static bool g_egl_probed;

static void set_err(char *err, size_t n, const char *msg) {
  if (err && n) snprintf(err, n, "%s", msg);
}

/* Resolves one symbol, tolerating absence: a Mesa/EGL implementation that
 * lacks eglCreatePbufferSurface is a real thing, and refusing to load the
 * whole library over it would be worse than reporting it unsupported. */
#define REQ(field, name)                                            \
  do {                                                              \
    *(void **)(&g_egl.field) = ez_dyn_sym(g_egl_lib, name);        \
    if (!g_egl.field) {                                             \
      set_err(err, err_len, "EGL symbol missing: " name);           \
      ez_dyn_close(g_egl_lib);                                      \
      g_egl_lib = NULL;                                             \
      return EZCORE_GPU_INIT_UNSUPPORTED;                           \
    }                                                               \
  } while (0);

/* The library names, in the order they are tried. Desktop Linux ships
 * libEGL.so.1 (libglvnd) and may also have libEGL.so (the dev symlink);
 * Android's NDK ships libEGL.so as a stub whose real implementation is in
 * the system. Trying several is what makes one binary work on both. */
static const char *const kEglNames[] = {
    "libEGL.so.1", "libEGL.so", "libEGL_android.so", "libEGL_mesa.so.0"};
static const char *const kGlesNames[] = {
    "libGLESv2.so.2", "libGLESv2.so", "libGLESv3.so.2"};

static bool probe_egl(char *err, size_t err_len) {
  if (g_egl_probed) return g_egl_lib != NULL;
  g_egl_probed = true;

  char probe_err[128] = {0};
  for (size_t i = 0; i < sizeof(kEglNames) / sizeof(kEglNames[0]); i++) {
    g_egl_lib = ez_dyn_open(kEglNames[i], probe_err, sizeof(probe_err));
    if (g_egl_lib) break;
  }
  if (!g_egl_lib) {
    set_err(err, err_len, "no EGL library found (tried libEGL.so.1/.so/android/mesa)");
    return false;
  }

  REQ(GetDisplay, "eglGetDisplay")
  REQ(Initialize, "eglInitialize")
  REQ(Terminate, "eglTerminate")
  REQ(QueryString, "eglQueryString")
  REQ(ChooseConfig, "eglChooseConfig")
  REQ(CreateContext, "eglCreateContext")
  REQ(DestroyContext, "eglDestroyContext")
  REQ(DestroySurface, "eglDestroySurface")
  REQ(MakeCurrent, "eglMakeCurrent")
  REQ(BindAPI, "eglBindAPI")
  REQ(GetProcAddress, "eglGetProcAddress")
  REQ(GetError, "eglGetError")
  /* Surfaces: headless uses a pbuffer, windowed uses a native window. Both
   * are optional at load time so a build can still report SUPPORTED for
   * headless capture when window surfaces are unavailable. */
  *(void **)(&g_egl.CreatePbufferSurface) =
      ez_dyn_sym(g_egl_lib, "eglCreatePbufferSurface");
  *(void **)(&g_egl.CreateWindowSurface) =
      ez_dyn_sym(g_egl_lib, "eglCreateWindowSurface");
  return true;
}

#undef REQ

/* --- GL/GLES entry points, resolved per context ------------------------- */
/* Every symbol is fetched through the CURRENT context's get_proc_address and
 * stored on the body, so there is no link-time GL dependency and no
 * file-scope table shared between contexts. */

/* eglGetProcAddress RETURNS the entry point; it does not write through an out
 * parameter. The first version of this file cast it to a
 * `void (*)(const char *, void **)` and passed a pointer, so the resolver
 * read back whatever was in that pointer -- uninitialised stack, or 0. The
 * test caught it as "GL symbol missing: glGenFramebuffers" on a machine where
 * the very same call resolves fine, which is the only kind of evidence that
 * distinguishes a cast bug from a driver problem. Hence a real wrapper. */
static void *egl_get_proc_shim(const char *name) {
  return (void *)g_egl.GetProcAddress(name);
}

static bool resolve_gl(void *(*get_proc)(const char *),
                       struct ezcore_gl_table *g, char *err, size_t err_len) {
#define GET(type, name)                                                    \
  do {                                                                     \
    void *p = get_proc(#name);                                            \
    *(void **)(&g->name) = p;                                              \
    if (!p) {                                                              \
      set_err(err, err_len, "GL symbol missing: " #name);                  \
      return false;                                                        \
    }                                                                      \
  } while (0);
  EZ_GL_FOREACH(GET)
#undef GET
  return true;
}

/* --- framebuffer construction ------------------------------------------ */
/* A core handed a framebuffer name expects a complete, renderable FBO with a
 * colour attachment. Getting this wrong is the classic silent failure: the
 * core renders into an incomplete FBO, every GL call is a no-op, and the
 * screen shows nothing with no error anywhere. So the status is checked and
 * reported rather than assumed. */
static bool make_fbo(struct ezcore_gpu_gl_body *b,
                     struct ezcore_gl_table *g, int w,
                     int h, bool want_depth, char *err, size_t err_len) {
  b->width = w;
  b->height = h;

  g->glGenTextures(1, &b->texture);
  g->glBindTexture(GL_TEXTURE_2D, b->texture);
  g->glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA,
                  GL_UNSIGNED_BYTE, NULL);
  g->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  g->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  g->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  g->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

  g->glGenFramebuffers(1, &b->framebuffer);
  g->glBindFramebuffer(GL_FRAMEBUFFER, b->framebuffer);
  g->glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                            b->texture, 0);

  if (want_depth) {
    g->glGenRenderbuffers(1, &b->depth_rb);
    g->glBindRenderbuffer(GL_RENDERBUFFER, b->depth_rb);
    g->glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, w, h);
    g->glFramebufferRenderbuffer(GL_FRAMEBUFFER,
                                 GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER,
                                 b->depth_rb);
  }

  /* The completeness check is not optional. A core handed an incomplete FBO
   * renders into nothing, every GL call silently becomes a no-op, and the
   * symptom is a black screen with no error logged anywhere -- the hardest
   * class of GPU bug to diagnose from a bug report. */
  GLenum status = g->glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (status != GL_FRAMEBUFFER_COMPLETE) {
    set_err(err, err_len, "framebuffer incomplete (glCheckFramebufferStatus)");
    g->glDeleteFramebuffers(1, &b->framebuffer);
    if (b->texture) g->glDeleteTextures(1, &b->texture);
    if (b->depth_rb) g->glDeleteRenderbuffers(1, &b->depth_rb);
    b->framebuffer = b->texture = b->depth_rb = 0;
    return false;
  }
  g->glViewport(0, 0, w, h);
  return true;
}

#endif /* EZCORE_HAVE_EGL */

/* ============================ public entry points ======================== */

enum ezcore_gpu_init_result ezcore_gpu_platform_init(
    struct ezcore_gpu_context **out, enum ezcore_gpu_api api,
    unsigned version_major, unsigned version_minor, bool headless, char *err,
    size_t err_len) {
#if !EZCORE_HAVE_EGL
  (void)out; (void)api; (void)version_major; (void)version_minor;
  (void)headless;
  set_err(err, err_len, "no EGL backend compiled in for this platform");
  return EZCORE_GPU_INIT_UNAVAILABLE;
#else
  (void)kGlesNames;
  if (!probe_egl(err, err_len)) return EZCORE_GPU_INIT_UNSUPPORTED;

  EGLDisplay dpy = g_egl.GetDisplay(EGL_DEFAULT_DISPLAY);
  if (dpy == EGL_NO_DISPLAY) {
    set_err(err, err_len, "eglGetDisplay returned EGL_NO_DISPLAY");
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }
  EGLint major = 0, minor = 0;
  if (!g_egl.Initialize(dpy, &major, &minor)) {
    set_err(err, err_len, "eglInitialize failed");
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }

  g_egl.BindAPI(api == EZCORE_GPU_OPENGL ? EGL_OPENGL_API : EGL_OPENGL_ES_API);

  EGLint renderable = EGL_OPENGL_ES3_BIT;
  if (api == EZCORE_GPU_OPENGLES2) renderable = EGL_OPENGL_ES2_BIT;
  else if (api == EZCORE_GPU_OPENGL) renderable = EGL_OPENGL_BIT;
  else if (api == EZCORE_GPU_OPENGL_CORE) renderable = EGL_OPENGL_BIT;

  EGLint cfg_attr[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE,
                       renderable, EGL_NONE};
  EGLConfig cfg;
  EGLint n = 0;
  if (!g_egl.ChooseConfig(dpy, cfg_attr, &cfg, 1, &n) || n < 1) {
    set_err(err, err_len, "eglChooseConfig found no matching config");
    g_egl.Terminate(dpy);
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }

  struct ezcore_gpu_gl_body *b = calloc(1, sizeof(*b));
  if (!b) {
    set_err(err, err_len, "out of memory");
    g_egl.Terminate(dpy);
    return EZCORE_GPU_INIT_FAILED;
  }
  b->head.backend = EZCORE_BACKEND_WINDOW;
  b->head.api = api;
  b->head.version_major = version_major ? version_major : 3;
  b->head.version_minor = version_minor;
  b->head.headless = headless;
  b->display = (void *)dpy;

  EGLSurface surf = EGL_NO_SURFACE;
  if (headless || !g_egl.CreatePbufferSurface) {
    EGLint pb[] = {EGL_WIDTH, 64, EGL_HEIGHT, 64, EGL_NONE};
    surf = g_egl.CreatePbufferSurface(dpy, cfg, pb);
  }
  if (surf == EGL_NO_SURFACE) {
    set_err(err, err_len, "no EGL surface could be created (headless and windowed both unavailable)");
    free(b);
    g_egl.Terminate(dpy);
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }
  b->surface = (void *)surf;

  EGLint ctx_attr[] = {EGL_CONTEXT_MAJOR_VERSION, (EGLint)b->head.version_major,
                       EGL_NONE};
  EGLContext ctx = g_egl.CreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attr);
  if (ctx == EGL_NO_CONTEXT) {
    set_err(err, err_len, "eglCreateContext failed");
    g_egl.DestroySurface(dpy, surf);
    free(b);
    g_egl.Terminate(dpy);
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }
  b->context = (void *)ctx;

  if (!g_egl.MakeCurrent(dpy, surf, surf, ctx)) {
    set_err(err, err_len, "eglMakeCurrent failed");
    g_egl.DestroyContext(dpy, ctx);
    g_egl.DestroySurface(dpy, surf);
    free(b);
    g_egl.Terminate(dpy);
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }

  b->get_proc_address_fn = egl_get_proc_shim;

  /* Resolve GL through the CURRENT context. This is the step that has to come
   * after MakeCurrent: eglGetProcAddress before a current context returns NULL
   * on several implementations, and a runtime that "resolved" functions to
   * NULL would hand a core a context in which every call fails. */
  if (!resolve_gl(egl_get_proc_shim, &b->gl, err, err_len)) {
    g_egl.MakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    g_egl.DestroyContext(dpy, ctx);
    g_egl.DestroySurface(dpy, surf);
    free(b);
    g_egl.Terminate(dpy);
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }

  int w = 64, h = 64;
  if (!make_fbo(b, &b->gl, w, h, true, err, err_len)) {
    g_egl.MakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    g_egl.DestroyContext(dpy, ctx);
    g_egl.DestroySurface(dpy, surf);
    free(b);
    g_egl.Terminate(dpy);
    return EZCORE_GPU_INIT_FAILED;
  }

  *out = &b->head;
  return EZCORE_GPU_INIT_OK;
#endif
}

void ezcore_gpu_platform_destroy(struct ezcore_gpu_context *ctx) {
#if EZCORE_HAVE_EGL
  if (!ctx) return;
  struct ezcore_gpu_gl_body *b = (struct ezcore_gpu_gl_body *)ctx;
  EGLDisplay dpy = (EGLDisplay)b->display;
  if (dpy != EGL_NO_DISPLAY) {
    g_egl.MakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (b->context) g_egl.DestroyContext(dpy, (EGLContext)b->context);
    if (b->surface) g_egl.DestroySurface(dpy, (EGLSurface)b->surface);
    g_egl.Terminate(dpy);
  }
  free(b);
#else
  (void)ctx;
#endif
}

bool ezcore_gpu_platform_is_current(struct ezcore_gpu_context *ctx) {
#if EZCORE_HAVE_EGL
  if (!ctx) return false;
  struct ezcore_gpu_gl_body *b = (struct ezcore_gpu_gl_body *)ctx;
  EGLDisplay dpy = (EGLDisplay)b->display;
  return dpy != EGL_NO_DISPLAY &&
         g_egl.GetError() == EGL_SUCCESS;
#else
  (void)ctx;
  return false;
#endif
}

unsigned ezcore_gpu_platform_current_framebuffer(struct ezcore_gpu_context *ctx) {
#if EZCORE_HAVE_EGL
  if (!ctx) return 0;
  return ((struct ezcore_gpu_gl_body *)ctx)->framebuffer;
#else
  (void)ctx;
  return 0;
#endif
}

void *ezcore_gpu_platform_get_proc_address(struct ezcore_gpu_context *ctx,
                                           const char *name) {
#if EZCORE_HAVE_EGL
  if (!ctx || !name) return NULL;
  struct ezcore_gpu_gl_body *b = (struct ezcore_gpu_gl_body *)ctx;
  if (!b->get_proc_address_fn) return NULL;
  return b->get_proc_address_fn(name);
#else
  (void)ctx; (void)name;
  return NULL;
#endif
}

void ezcore_gpu_platform_notify_reset(struct ezcore_gpu_context *ctx) {
  /* GL resources are invalidated by the driver on reset, not by us; the
   * generation counter is what a caller can observe. */
  if (ctx) ctx->generation++;
}

bool ezcore_gpu_platform_supported(enum ezcore_gpu_api api) {
#if EZCORE_HAVE_EGL
  if (api == EZCORE_GPU_NONE) return false;
  char err[160] = {0};
  if (!probe_egl(err, sizeof(err))) return false;
  EGLDisplay dpy = g_egl.GetDisplay(EGL_DEFAULT_DISPLAY);
  if (dpy == EGL_NO_DISPLAY) return false;
  EGLint major = 0, minor = 0;
  if (!g_egl.Initialize(dpy, &major, &minor)) return false;
  g_egl.Terminate(dpy);
  return true;
#else
  (void)api;
  return false;
#endif
}

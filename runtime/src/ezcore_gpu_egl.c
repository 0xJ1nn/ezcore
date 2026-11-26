// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* EGL-backed render context: Linux and Android (the GPU render-context design).
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

/* --- Desktop GL on X11 --------------------------------------------------
 * An EGL context is invisible to GLX. Cores that initialise their own GL
 * loader through GLX (and report "No GLX display" when it is missing) cannot
 * use it even when the runtime considers the context valid. Desktop GL
 * requests therefore prefer a GLX pbuffer context on X11; GLES and non-X11
 * platforms keep the EGL path unchanged. The libraries are still opened at
 * runtime: there is no link-time GL/X11 dependency in the runtime.
 */
#if defined(__linux__) && !defined(__ANDROID__)
#define EZCORE_HAVE_GLX 1

typedef void *EzGlxDisplay;
typedef void *EzGlxConfig;
typedef void *EzGlxContext;
typedef unsigned long EzGlxDrawable;

#define EZ_GLX_NONE 0
#define EZ_GLX_DRAWABLE_TYPE 0x8010
#define EZ_GLX_PBUFFER_BIT 0x00000001
#define EZ_GLX_RENDER_TYPE 0x8011
#define EZ_GLX_RGBA_BIT 0x00000001
#define EZ_GLX_RED_SIZE 8
#define EZ_GLX_DEPTH_SIZE 12
#define EZ_GLX_STENCIL_SIZE 13
#define EZ_GLX_PBUFFER_WIDTH 0x8042
#define EZ_GLX_PBUFFER_HEIGHT 0x8043
#define EZ_GLX_RGBA_TYPE 0x8014
#define EZ_GLX_CONTEXT_MAJOR_VERSION_ARB 0x2091
#define EZ_GLX_CONTEXT_MINOR_VERSION_ARB 0x2092
#define EZ_GLX_CONTEXT_PROFILE_MASK_ARB 0x9126
#define EZ_GLX_CONTEXT_CORE_PROFILE_BIT_ARB 0x00000001

struct glx_api {
  EzGlxDisplay (*OpenDisplay)(const char *);
  int (*CloseDisplay)(EzGlxDisplay);
  EzGlxConfig *(*ChooseFBConfig)(EzGlxDisplay, int, const int *, int *);
  EzGlxDrawable (*CreatePbuffer)(EzGlxDisplay, EzGlxConfig, const int *);
  EzGlxContext (*CreateNewContext)(EzGlxDisplay, EzGlxConfig, int,
                                   EzGlxContext, int);
  int (*MakeCurrent)(EzGlxDisplay, EzGlxDrawable, EzGlxDrawable, EzGlxContext);
  void (*DestroyContext)(EzGlxDisplay, EzGlxContext);
  void (*DestroyPbuffer)(EzGlxDisplay, EzGlxDrawable);
  void *(*GetProcAddress)(const unsigned char *);
  void *(*GetCurrentContext)(void);
};

static struct glx_api g_glx;
static void *g_glx_lib;
static void *g_x11_lib;
static bool g_glx_probed;

#define REQ_GLX(field, lib, name)                                       \
  do {                                                                  \
    *(void **)(&g_glx.field) = ez_dyn_sym(lib, name);                  \
    if (!g_glx.field) {                                                 \
      set_err(err, err_len, "GLX symbol missing: " name);               \
      return false;                                                     \
    }                                                                   \
  } while (0)

static bool probe_glx(char *err, size_t err_len) {
  if (g_glx_probed) return g_glx_lib != NULL && g_x11_lib != NULL;
  g_glx_probed = true;

  char probe_err[128] = {0};
  g_glx_lib = ez_dyn_open("libGLX.so.0", probe_err, sizeof(probe_err));
  if (!g_glx_lib)
    g_glx_lib = ez_dyn_open("libGL.so.1", probe_err, sizeof(probe_err));
  g_x11_lib = ez_dyn_open("libX11.so.6", probe_err, sizeof(probe_err));
  if (!g_glx_lib || !g_x11_lib) {
    set_err(err, err_len, "GLX or X11 library not found");
    return false;
  }
  REQ_GLX(ChooseFBConfig, g_glx_lib, "glXChooseFBConfig");
  REQ_GLX(CreatePbuffer, g_glx_lib, "glXCreatePbuffer");
  REQ_GLX(CreateNewContext, g_glx_lib, "glXCreateNewContext");
  REQ_GLX(MakeCurrent, g_glx_lib, "glXMakeContextCurrent");
  REQ_GLX(DestroyContext, g_glx_lib, "glXDestroyContext");
  REQ_GLX(DestroyPbuffer, g_glx_lib, "glXDestroyPbuffer");
  REQ_GLX(GetProcAddress, g_glx_lib, "glXGetProcAddress");
  REQ_GLX(GetCurrentContext, g_glx_lib, "glXGetCurrentContext");
  REQ_GLX(OpenDisplay, g_x11_lib, "XOpenDisplay");
  REQ_GLX(CloseDisplay, g_x11_lib, "XCloseDisplay");
  return true;
}

#undef REQ_GLX

static void *glx_get_proc_shim(const char *name) {
  return (void *)g_glx.GetProcAddress((const unsigned char *)name);
}

/* Version ladder for a core-profile request. The exact version the core
 * asked for comes first; the ladder then steps down to versions a software
 * driver is likely to accept, and finally drops the request altogether. */
static const int kGlxCoreVersions[][2] = {
    {4, 6}, {4, 5}, {4, 3}, {4, 0}, {3, 3}, {3, 2}};

static enum ezcore_gpu_init_result glx_init(
    struct ezcore_gpu_context **out, enum ezcore_gpu_api api,
    unsigned version_major, unsigned version_minor, bool headless, char *err,
    size_t err_len) {
  (void)headless; /* the pbuffer is headless by construction */
  if (!probe_glx(err, err_len)) return EZCORE_GPU_INIT_UNSUPPORTED;

  EzGlxDisplay dpy = g_glx.OpenDisplay(NULL);
  if (!dpy) {
    set_err(err, err_len, "XOpenDisplay failed for a desktop GL context");
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }
  /* Config attributes: an RGB pbuffer with a real depth/stencil buffer.

   * EGL_OPENGL_BIT counterparts are GLX_RGBA_BIT and GLX_PBUFFER_BIT. */
  const int cfg_attr[] = {EZ_GLX_DRAWABLE_TYPE,
                          EZ_GLX_PBUFFER_BIT,
                          EZ_GLX_RENDER_TYPE,
                          EZ_GLX_RGBA_BIT,
                          EZ_GLX_RED_SIZE,
                          8,
                          EZ_GLX_DEPTH_SIZE,
                          24,
                          EZ_GLX_STENCIL_SIZE,
                          8,
                          EZ_GLX_NONE};
  int n = 0;
  EzGlxConfig *cfgs = g_glx.ChooseFBConfig(dpy, 0, cfg_attr, &n);
  if (!cfgs || n < 1) {
    set_err(err, err_len, "glXChooseFBConfig found no matching config");
    g_glx.CloseDisplay(dpy);
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }
  const int pb_attr[] = {EZ_GLX_PBUFFER_WIDTH, 64, EZ_GLX_PBUFFER_HEIGHT, 64,
                         EZ_GLX_NONE};
  EzGlxDrawable pb = g_glx.CreatePbuffer(dpy, cfgs[0], pb_attr);
  if (!pb) {
    set_err(err, err_len, "glXCreatePbuffer failed");
    g_glx.CloseDisplay(dpy);
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }

  typedef EzGlxContext (*create_attribs_fn)(EzGlxDisplay, EzGlxConfig,
                                            EzGlxContext, int, const int *);
  create_attribs_fn create_attribs = (create_attribs_fn)g_glx.GetProcAddress(
      (const unsigned char *)"glXCreateContextAttribsARB");

  const bool want_core = api == EZCORE_GPU_OPENGL_CORE;
  int attr[9];
  EzGlxContext ctx = NULL;
  int attempts = 0;
  /* Exact request first, then the version ladder, then no attributes. */
  for (int step = -1; step < (int)(sizeof(kGlxCoreVersions) /
                                   sizeof(kGlxCoreVersions[0])) &&
                      !ctx;
       step++) {
    int k = 0;
    unsigned major = 0, minor = 0;
    if (step == -1) {
      major = version_major;
      minor = version_minor;
      /* A driver answers an out-of-range version with an X error, not just
       * NULL. Clamp to the highest published desktop GL versions before
       * putting the request on the wire. */
      if (major > 4 || (major == 4 && minor > 6)) {
        major = 4;
        minor = 6;
      } else if (major == 3 && minor > 3) {
        minor = 3;
      } else if (major == 2 && minor > 1) {
        minor = 1;
      }
    } else if (want_core) {
      major = (unsigned)kGlxCoreVersions[step][0];
      minor = (unsigned)kGlxCoreVersions[step][1];
    } else {
      break; /* a plain GL request only tries its exact version and default */
    }
    bool skip = major == 0 && step == -1;
    for (size_t v = 0; !skip && want_core && step >= 0 && v < (size_t)step; v++)
      if (kGlxCoreVersions[v][0] == (int)major &&
          kGlxCoreVersions[v][1] == (int)minor)
        skip = true;
    if (skip) continue;
    if (major) {
      attr[k++] = EZ_GLX_CONTEXT_MAJOR_VERSION_ARB;
      attr[k++] = (int)major;
      attr[k++] = EZ_GLX_CONTEXT_MINOR_VERSION_ARB;
      attr[k++] = (int)minor;
    }
    if (want_core) {
      attr[k++] = EZ_GLX_CONTEXT_PROFILE_MASK_ARB;
      attr[k++] = EZ_GLX_CONTEXT_CORE_PROFILE_BIT_ARB;
    }
    attr[k] = EZ_GLX_NONE;
    attempts++;
    if (create_attribs)
      ctx = create_attribs(dpy, cfgs[0], NULL, 1, attr);
    else if (step == -1)
      ctx = g_glx.CreateNewContext(dpy, cfgs[0], EZ_GLX_RGBA_TYPE, NULL, 1);
  }
  if (!ctx && create_attribs) {
    attempts++;
    ctx = create_attribs(dpy, cfgs[0], NULL, 1,
                         (const int[]){EZ_GLX_NONE});
  }
  if (!ctx && !create_attribs)
    ctx = g_glx.CreateNewContext(dpy, cfgs[0], EZ_GLX_RGBA_TYPE, NULL, 1);
  if (!ctx) {
    char msg[160];
    snprintf(msg, sizeof(msg),
             "GLX context creation failed after %d config/attribute attempts",
             attempts);
    set_err(err, err_len, msg);
    g_glx.DestroyPbuffer(dpy, pb);
    g_glx.CloseDisplay(dpy);
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }
  if (!g_glx.MakeCurrent(dpy, pb, pb, ctx)) {
    set_err(err, err_len, "glXMakeContextCurrent failed");
    g_glx.DestroyContext(dpy, ctx);
    g_glx.DestroyPbuffer(dpy, pb);
    g_glx.CloseDisplay(dpy);
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }

  struct ezcore_gpu_gl_body *b = calloc(1, sizeof(*b));
  if (!b) {
    set_err(err, err_len, "out of memory");
    g_glx.DestroyContext(dpy, ctx);
    g_glx.DestroyPbuffer(dpy, pb);
    g_glx.CloseDisplay(dpy);
    return EZCORE_GPU_INIT_FAILED;
  }
  b->head.backend = EZCORE_BACKEND_WINDOW;
  b->head.api = api;
  b->head.version_major = version_major ? version_major : 3;
  b->head.version_minor = version_minor;
  b->head.headless = headless;
  b->glx = true;
  b->display = (void *)dpy;
  b->surface = (void *)(uintptr_t)pb; /* GLXPbuffer is an XID */
  b->context = (void *)ctx;
  b->get_proc_address_fn = glx_get_proc_shim;

  if (!resolve_gl(glx_get_proc_shim, &b->gl, err, err_len)) {
    g_glx.MakeCurrent(dpy, 0, 0, NULL);
    g_glx.DestroyContext(dpy, ctx);
    g_glx.DestroyPbuffer(dpy, pb);
    g_glx.CloseDisplay(dpy);
    free(b);
    return EZCORE_GPU_INIT_UNSUPPORTED;
  }
  if (!make_fbo(b, &b->gl, 64, 64, true, err, err_len)) {
    g_glx.MakeCurrent(dpy, 0, 0, NULL);
    g_glx.DestroyContext(dpy, ctx);
    g_glx.DestroyPbuffer(dpy, pb);
    g_glx.CloseDisplay(dpy);
    free(b);
    return EZCORE_GPU_INIT_FAILED;
  }
  *out = &b->head;
  return EZCORE_GPU_INIT_OK;
}
#else
#define EZCORE_HAVE_GLX 0
#endif

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

  /* Desktop GL for both OpenGL kinds. A core-profile request used to bind
   * the GLES API, so a core asking for GL 3.3 core got a GLES context and
   * desktop-only functions resolved to NULL (Mupen64Plus-Next crashed in
   * glsm_ctl calling one). */
  const bool desktop = api == EZCORE_GPU_OPENGL || api == EZCORE_GPU_OPENGL_CORE;
#if EZCORE_HAVE_GLX
  /* Desktop GL first: a GLX-current context is the only kind a GLX-based
   * core loader can use. If GLX is absent, keep the EGL path below. */
  if (desktop) {
    enum ezcore_gpu_init_result gr = glx_init(
        out, api, version_major, version_minor, headless, err, err_len);
    if (gr == EZCORE_GPU_INIT_OK) return gr;
  }
#endif
  g_egl.BindAPI(desktop ? EGL_OPENGL_API : EGL_OPENGL_ES_API);

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

  /* Version, and for a core-profile request the core profile itself; a plain
   * OpenGL request takes whatever compatible context the driver offers. */
  EGLint ctx_attr[9];
  int na = 0;
  if (api != EZCORE_GPU_OPENGL || version_major > 0) {
    ctx_attr[na++] = EGL_CONTEXT_MAJOR_VERSION;
    ctx_attr[na++] = (EGLint)b->head.version_major;
    ctx_attr[na++] = EGL_CONTEXT_MINOR_VERSION;
    ctx_attr[na++] = (EGLint)b->head.version_minor;
  }
  if (api == EZCORE_GPU_OPENGL_CORE) {
    ctx_attr[na++] = EGL_CONTEXT_OPENGL_PROFILE_MASK;
    ctx_attr[na++] = EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT;
  }
  ctx_attr[na] = EGL_NONE;
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
#if EZCORE_HAVE_GLX
  if (b->glx) {
    EzGlxDisplay dpy = (EzGlxDisplay)b->display;
    if (dpy) {
      g_glx.MakeCurrent(dpy, 0, 0, NULL);
      if (b->context) g_glx.DestroyContext(dpy, (EzGlxContext)b->context);
      if (b->surface)
        g_glx.DestroyPbuffer(dpy, (EzGlxDrawable)(uintptr_t)b->surface);
      g_glx.CloseDisplay(dpy);
    }
    free(b);
    return;
  }
#endif
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
#if EZCORE_HAVE_GLX
  if (b->glx)
    return g_glx.GetCurrentContext() == (EzGlxContext)b->context;
#endif
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

bool ezcore_gpu_platform_resize(struct ezcore_gpu_context *ctx, int w, int h) {
#if EZCORE_HAVE_EGL
  struct ezcore_gpu_gl_body *b = (struct ezcore_gpu_gl_body *)ctx;
  if (!b || !b->framebuffer) return false;
  if (b->width == w && b->height == h) return true;
  struct ezcore_gl_table *g = &b->gl;
  /* Same texture, renderbuffer and FBO names, new storage. */
  g->glBindTexture(GL_TEXTURE_2D, b->texture);
  g->glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA,
                  GL_UNSIGNED_BYTE, NULL);
  if (b->depth_rb) {
    g->glBindRenderbuffer(GL_RENDERBUFFER, b->depth_rb);
    g->glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, w, h);
  }
  g->glBindFramebuffer(GL_FRAMEBUFFER, b->framebuffer);
  if (g->glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    return false;
  b->width = w;
  b->height = h;
  g->glViewport(0, 0, w, h);
  return true;
#else
  (void)ctx; (void)w; (void)h;
  return false;
#endif
}

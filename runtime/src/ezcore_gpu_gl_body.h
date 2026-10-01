/* GL/GLES context body: the windowing backend's private layout.
 *
 * Separate from ezcore_gpu_internal.h on purpose. The shared header is
 * included by the Vulkan backend, which has no GL headers at all; leaving the
 * GL function table in there would make a Vulkan-only build fail to compile
 * for a type it never uses. ezcore_gpu_gl_table.h pulls in PFNGL* types from
 * <GLES3/gl3.h>, so anything including it must already have that header.
 */
#ifndef EZCORE_GPU_GL_BODY_H
#define EZCORE_GPU_GL_BODY_H

#include "ezcore_gpu_internal.h"
#include "ezcore_gpu_gl_table.h"

#if defined(__linux__) || defined(__ANDROID__)
/* GLES3.h is self-contained and provides every PFNGL* type the table needs.
 * It is present in both the Android NDK and mesa/libglvnd on desktop, which
 * is what lets one backend file serve Android and Linux. */
#include <GLES3/gl3.h>
#endif

struct ezcore_gpu_gl_body {
  struct ezcore_gpu_context head;

  void *display;  /* EGLDisplay / HDC / NSOpenGLContext*  */
  void *surface;  /* EGLSurface  / HWND  / NSOpenGLContext* */
  void *context;  /* EGLContext  / HGLRC  / NSOpenGLContext* */

  unsigned framebuffer; /* GLuint FBO the core renders into    */
  unsigned texture;     /* GLuint colour attachment           */
  unsigned depth_rb;    /* GLuint depth/stencil, 0 if none     */
  int width, height;

  /* Resolved per context, never linked: the runtime must stay loadable on a
   * machine with no GPU (ADR-018 Q6, PLATFORM.md §6). */
  void *(*get_proc_address_fn)(const char *);

  struct ezcore_gl_table {
#define EZ_DECL_GL(type, name) type name;
    EZ_GL_FOREACH(EZ_DECL_GL)
#undef EZ_DECL_GL
  } gl;
};

#endif /* EZCORE_GPU_GL_BODY_H */

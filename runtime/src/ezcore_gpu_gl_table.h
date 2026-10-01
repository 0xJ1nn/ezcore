/* X-macro list of the GL/GLES entry points the runtime resolves per context.
 *
 * One list, three consumers: the pointer struct, the resolver and nothing
 * else. Declaring the list once is what stops the struct and the resolver from
 * drifting -- the first draft of this file had the struct in one macro list
 * and the resolver walking a different one, which compiles and then fails at
 * runtime when a symbol is resolved but never stored.
 *
 * PFN types come from <GLES3/gl3.h> in the backend. This header is included
 * only from ezcore_gpu_internal.h, which is included only after that.
 */
#ifndef EZCORE_GPU_GL_TABLE_H
#define EZCORE_GPU_GL_TABLE_H

#define EZ_GL_FOREACH(X)                                                       \
  X(PFNGLGENFRAMEBUFFERSPROC, glGenFramebuffers)                               \
  X(PFNGLBINDFRAMEBUFFERPROC, glBindFramebuffer)                               \
  X(PFNGLDELETEFRAMEBUFFERSPROC, glDeleteFramebuffers)                         \
  X(PFNGLGENRENDERBUFFERSPROC, glGenRenderbuffers)                             \
  X(PFNGLBINDRENDERBUFFERPROC, glBindRenderbuffer)                             \
  X(PFNGLDELETERENDERBUFFERSPROC, glDeleteRenderbuffers)                       \
  X(PFNGLRENDERBUFFERSTORAGEPROC, glRenderbufferStorage)                       \
  X(PFNGLFRAMEBUFFERTEXTURE2DPROC, glFramebufferTexture2D)                     \
  X(PFNGLFRAMEBUFFERRENDERBUFFERPROC, glFramebufferRenderbuffer)               \
  X(PFNGLCHECKFRAMEBUFFERSTATUSPROC, glCheckFramebufferStatus)                 \
  X(PFNGLGENTEXTURESPROC, glGenTextures)                                       \
  X(PFNGLBINDTEXTUREPROC, glBindTexture)                                       \
  X(PFNGLDELETETEXTURESPROC, glDeleteTextures)                                 \
  X(PFNGLTEXIMAGE2DPROC, glTexImage2D)                                         \
  X(PFNGLTEXPARAMETERIPROC, glTexParameteri)                                   \
  X(PFNGLACTIVETEXTUREPROC, glActiveTexture)                                   \
  X(PFNGLGENBUFFERSPROC, glGenBuffers)                                         \
  X(PFNGLBINDBUFFERPROC, glBindBuffer)                                         \
  X(PFNGLBUFFERDATAPROC, glBufferData)                                         \
  X(PFNGLBUFFERSUBDATAPROC, glBufferSubData)                                   \
  X(PFNGLDELETEBUFFERSPROC, glDeleteBuffers)                                   \
  X(PFNGLGETERRORPROC, glGetError)                                             \
  X(PFNGLVIEWPORTPROC, glViewport)                                             \
  X(PFNGLFINISHPROC, glFinish)                                                 \
  X(PFNGLFLUSHPROC, glFlush)                                                   \
  X(PFNGLGETSTRINGPROC, glGetString)                                           \
  X(PFNGLGETINTEGERVPROC, glGetIntegerv)                                       \
  X(PFNGLREADPIXELSPROC, glReadPixels)                                         \
  X(PFNGLENABLEPROC, glEnable)                                                 \
  X(PFNGLDISABLEPROC, glDisable)                                               \
  X(PFNGLBLENDFUNCPROC, glBlendFunc)                                           \
  X(PFNGLDRAWARRAYSPROC, glDrawArrays)                                         \
  X(PFNGLGENVERTEXARRAYSPROC, glGenVertexArrays)                               \
  X(PFNGLBINDVERTEXARRAYPROC, glBindVertexArray)                               \
  X(PFNGLDELETEVERTEXARRAYSPROC, glDeleteVertexArrays)                         \
  X(PFNGLENABLEVERTEXATTRIBARRAYPROC, glEnableVertexAttribArray)               \
  X(PFNGLVERTEXATTRIBPOINTERPROC, glVertexAttribPointer)

#endif /* EZCORE_GPU_GL_TABLE_H */

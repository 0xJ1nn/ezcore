/* Dynamic-library loading behind one seam.
 *
 * runtime.c never touches dlopen/LoadLibrary directly: POSIX (.so/.dylib)
 * and Windows (.dll) differ, and ARCHITECTURE.md requires platform
 * `#ifdef`s to live in platform files only. CMake compiles exactly one
 * of dynload_posix.c / dynload_win32.c.
 */
#pragma once

#include <stddef.h>

/* Opens a core library. Returns NULL and fills err on failure. */
void *ez_dyn_open(const char *path, char *err, size_t err_len);

/* Resolves a symbol. Returns NULL when absent (caller decides whether
 * the symbol is mandatory or optional). */
void *ez_dyn_sym(void *handle, const char *sym);

/* Closes a library opened by ez_dyn_open. NULL-safe. */
void ez_dyn_close(void *handle);

/* Windows dynamic loading (.dll via LoadLibraryA). */
#include "dynload.h"

#define WIN32_LEAN_AND_MEAN
#include <stdio.h>
#include <windows.h>

void *ez_dyn_open(const char *path, char *err, size_t err_len) {
  HMODULE module = LoadLibraryA(path);
  if (!module && err && err_len > 0) {
    DWORD code = GetLastError();
    char *msg = NULL;
    DWORD flags = FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
                  FORMAT_MESSAGE_IGNORE_INSERTS;
    if (FormatMessageA(flags, NULL, code, 0, (LPSTR)&msg, 0, NULL) && msg) {
      snprintf(err, err_len, "LoadLibrary failed (%lu): %s", (unsigned long)code, msg);
      LocalFree(msg);
    } else {
      snprintf(err, err_len, "LoadLibrary failed (%lu)", (unsigned long)code);
    }
  }
  return (void *)module;
}

void *ez_dyn_sym(void *handle, const char *sym) {
  if (!handle) return NULL;
  return (void *)GetProcAddress((HMODULE)handle, sym);
}

void ez_dyn_close(void *handle) {
  if (handle) FreeLibrary((HMODULE)handle);
}

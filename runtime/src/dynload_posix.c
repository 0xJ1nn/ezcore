/* POSIX dynamic loading (Linux, macOS, Android, iOS simulator/device). */
#include "dynload.h"

#include <dlfcn.h>
#include <stdio.h>

void *ez_dyn_open(const char *path, char *err, size_t err_len) {
  void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!handle && err && err_len > 0) {
    snprintf(err, err_len, "dlopen failed: %s", dlerror());
  }
  return handle;
}

void *ez_dyn_sym(void *handle, const char *sym) {
  if (!handle) return NULL;
  return dlsym(handle, sym);
}

void ez_dyn_close(void *handle) {
  if (handle) dlclose(handle);
}

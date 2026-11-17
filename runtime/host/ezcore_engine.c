/* ezcore_engine.c — the tiny name→backend registry for the engine seam. */
#include "ezcore_engine.h"

#include <stdio.h>
#include <string.h>

#define EZH_MAX_ENGINES 8

static const ezh_engine_vtable *g_engines[EZH_MAX_ENGINES];
static unsigned g_count;

void ezh_engine_register(const ezh_engine_vtable *vtable) {
  if (!vtable || !vtable->name) return;
  for (unsigned i = 0; i < g_count; i++) {
    if (strcmp(g_engines[i]->name, vtable->name) == 0) return; /* idempotent */
  }
  if (g_count < EZH_MAX_ENGINES) g_engines[g_count++] = vtable;
}

const ezh_engine_vtable *ezh_engine_find(const char *name) {
  if (!name) return NULL;
  for (unsigned i = 0; i < g_count; i++) {
    if (strcmp(g_engines[i]->name, name) == 0) return g_engines[i];
  }
  return NULL;
}

void ezh_engine_names(char *buf, size_t n) {
  size_t at = 0;
  if (!buf || n == 0) return;
  for (unsigned i = 0; i < g_count; i++) {
    size_t len = strlen(g_engines[i]->name);
    if (i) {
      if (at + 2 >= n) break;
      buf[at++] = ','; buf[at++] = ' ';
    }
    if (at + len >= n) break;
    memcpy(buf + at, g_engines[i]->name, len);
    at += len;
  }
  buf[at] = '\0';
}

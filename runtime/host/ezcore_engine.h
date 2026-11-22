// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* ezcore_engine.h — the GENERIC engine-backend seam inside the host process.
 *
 * The wire contract (ezcore_core_host_protocol.h) is unchanged by this file.
 * What it makes explicit is the seam BEHIND that contract: an engine is a
 * table of operations, not necessarily a libretro core. libretro is one
 * backend (the default, so nothing breaks); Tier-2 engines — standalone
 * programs, or the in-tree synthetic proof — are first-class backends too.
 * Selection is data: the host reads `--engine=NAME` at startup and looks the
 * name up in a small registry. No op, no byte on the wire, changes.
 *
 * This is the "OS that hosts engines" boundary: the host owns framing,
 * validation and the protocol; an engine owns only what its operations do.
 */
#ifndef EZCORE_ENGINE_H
#define EZCORE_ENGINE_H

#include <stddef.h>
#include <stdint.h>

typedef struct ezh_engine ezh_engine;

/* A frame's pixels/PCM are owned by the engine, valid until the next call. */
typedef struct {
  unsigned w, h;
  const uint8_t *rgba; /* w*h*4 bytes */
  const uint8_t *pcm;  /* s16 stereo, may be NULL */
  size_t pcm_bytes;
} ezh_frame;

/*
 * Every operation the generic host can dispatch. An engine that cannot do an
 * op either no-ops it or returns an error through the existing EZH_ERROR
 * response; the wire protocol never learns which backend is in play.
 */
typedef struct ezh_engine_vtable {
  const char *name;

  /* lifespan + content */
  ezh_engine *(*create)(void);
  void (*destroy)(ezh_engine *);
  int (*open)(ezh_engine *, const char *core, const char *system_dir,
              const char *save_dir, char *err, size_t errlen);
  int (*load_content)(ezh_engine *, const char *content, char *err,
                      size_t errlen);
  const char *(*core_name)(const ezh_engine *);
  void (*geometry)(const ezh_engine *, unsigned *w, unsigned *h, double *fps);
  double (*sample_rate)(const ezh_engine *);

  /* frame loop */
  void (*run_frame)(ezh_engine *, unsigned count);
  void (*frame_size)(const ezh_engine *, unsigned *w, unsigned *h);
  void (*pixels_copy)(const ezh_engine *, void *dst, size_t n);
  size_t (*audio_drain)(ezh_engine *, int16_t *dst, size_t frames);
  void (*pause)(ezh_engine *, int paused);
  void (*reset)(ezh_engine *);

  /* input */
  void (*clear_buttons)(ezh_engine *, unsigned port);
  void (*set_button)(ezh_engine *, unsigned port, unsigned id, int pressed);
  void (*set_analog)(ezh_engine *, unsigned port, unsigned stick,
                     unsigned axis, int value);
  void (*mouse_move)(ezh_engine *, int dx, int dy);
  void (*mouse_button)(ezh_engine *, unsigned id, int pressed);
  void (*key)(ezh_engine *, unsigned code, int pressed, unsigned ch,
              unsigned mods);
  void (*pointer)(ezh_engine *, int x, int y, int pressed);

  /* save states */
  size_t (*serialize_size)(const ezh_engine *);
  int (*serialize)(ezh_engine *, void *dst, size_t n);
  int (*unserialize)(ezh_engine *, const void *src, size_t n);

  /* cheats */
  void (*cheat_reset)(ezh_engine *);
  int (*cheat_set)(ezh_engine *, unsigned index, int enabled,
                   const char *code);

  /* options */
  unsigned (*option_count)(const ezh_engine *);
  void (*option_get)(const ezh_engine *, unsigned i, const char **key,
                     const char **def, const char **value);
  int (*option_set)(ezh_engine *, const char *key, const char *value);
} ezh_engine_vtable;

/* Registry: backends register by name; the host resolves --engine=NAME.
 * ezh_engine_names writes a comma-separated list for an error message. */
void ezh_engine_register(const ezh_engine_vtable *vtable);
const ezh_engine_vtable *ezh_engine_find(const char *name);
void ezh_engine_names(char *buf, size_t n);

/* Backends (defined in ezcore_engine_*.c). */
extern const ezh_engine_vtable ezh_engine_libretro;
extern const ezh_engine_vtable ezh_engine_synthetic;

#endif

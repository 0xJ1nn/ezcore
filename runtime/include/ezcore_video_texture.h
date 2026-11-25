// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* Thread-safe frame snapshots for the desktop Flutter texture surface.
 *
 * The runtime produces frames on the emulation thread; Flutter asks for pixels
 * on the render thread. This bridge keeps three RGBA snapshots so the render
 * thread can finish reading one while the next frames are published. It is
 * shared by the Linux and Windows runners: the platform classes only register
 * the texture and hand Flutter the pointer this module returns.
 *
 * Nothing here is exported as a libretro entry point. The runtime owns the
 * session; callers pass that session to the publish function.
 */
#ifndef EZCORE_VIDEO_TEXTURE_H
#define EZCORE_VIDEO_TEXTURE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ezcore_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ezcore_video_texture ezcore_video_texture;

/* Counters for the player's frame stats and for regression tests. */
typedef struct {
  uint64_t frames_published;
  uint64_t frames_dropped;   /* no snapshot available to write into */
  uint64_t buffer_growths;   /* geometry required a larger allocation */
  uint32_t width;
  uint32_t height;
} ezcore_video_texture_stats;

/* Creates an empty bridge. Returns NULL on allocation failure. */
ezcore_video_texture *ezcore_video_texture_create(void);

/* Releases every snapshot. Safe to call twice on the same pointer only if
 * the caller sets its own pointer to NULL after the first call. */
void ezcore_video_texture_destroy(ezcore_video_texture *texture);

/* Publishes an RGBA frame. `rgba` must hold width*height*4 bytes for the
 * duration of the call. Returns false for invalid dimensions or allocation
 * failure. Null `rgba` with non-zero dimensions is rejected. */
bool ezcore_video_texture_publish(ezcore_video_texture *texture,
                                  const uint8_t *rgba, uint32_t width,
                                  uint32_t height);

/* Reads the session's latest frame with the runtime's RGBA copy and publishes
 * it. Call after the core has finished a frame, before asking Flutter to
 * redraw the texture. Returns false when the session has no frame yet. */
bool ezcore_video_texture_publish_session(ezcore_video_texture *texture,
                                          ezcore_session *session);

/* Returns the newest snapshot and its real dimensions. The pointer stays
 * valid until the next call to this function or destroy. May be called from
 * the render thread while another thread publishes frames. Returns NULL and
 * zero dimensions when nothing has been published. */
const uint8_t *ezcore_video_texture_pixels(ezcore_video_texture *texture,
                                           uint32_t *width, uint32_t *height);

/* Copies the current counters. `out` must not be NULL. */
void ezcore_video_texture_stats_get(ezcore_video_texture *texture,
                                    ezcore_video_texture_stats *out);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif  /* EZCORE_VIDEO_TEXTURE_H */

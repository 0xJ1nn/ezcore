// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* Desktop video texture bridge, shared by the Linux and Windows runners.
 *
 * Three snapshots make the render-thread callback safe against the emulation
 * thread advancing frames. The callback keeps the snapshot it returned held
 * until the next callback; publication never writes into a held snapshot, so
 * the renderer never sees half of one frame and half of the next.
 */
#include "ezcore_video_texture.h"

#include <stdlib.h>
#include <string.h>

#include "ezcore_video_lock.h"

#define EZCORE_VIDEO_SLOTS 3

struct video_slot {
  uint8_t *data;
  size_t capacity;
  uint32_t width;
  uint32_t height;
  uint64_t sequence;
  bool held;
};

struct ezcore_video_texture {
  ezcore_video_lock *lock;
  struct video_slot slots[EZCORE_VIDEO_SLOTS];
  int published;  /* -1 until the first frame */
  int held;       /* -1 while no snapshot is with the renderer */
  uint64_t sequence;
  ezcore_video_texture_stats stats;
};

ezcore_video_texture *ezcore_video_texture_create(void) {
  ezcore_video_texture *texture = calloc(1, sizeof(*texture));
  if (!texture) return NULL;
  texture->lock = ezcore_video_lock_create();
  if (!texture->lock) {
    free(texture);
    return NULL;
  }
  texture->published = -1;
  texture->held = -1;
  return texture;
}

void ezcore_video_texture_destroy(ezcore_video_texture *texture) {
  if (!texture) return;
  for (int i = 0; i < EZCORE_VIDEO_SLOTS; ++i) free(texture->slots[i].data);
  ezcore_video_lock_destroy(texture->lock);
  free(texture);
}

/* Chooses the oldest snapshot the renderer is not holding. Published frames
 * are candidates: a frame that has not been presented yet may be replaced by
 * a newer one without any visible effect. Returns -1 only when every slot is
 * held, which three slots and one callback make impossible in practice. */
static int next_writable_slot(ezcore_video_texture *texture) {
  int best = -1;
  for (int i = 0; i < EZCORE_VIDEO_SLOTS; ++i) {
    if (texture->slots[i].held) continue;
    if (best < 0 || texture->slots[i].sequence < texture->slots[best].sequence)
      best = i;
  }
  return best;
}

/* Caller holds the lock. Copies `rgba` (or reads the session) into the chosen
 * slot and publishes it. `copy` may be NULL, in which case the session is
 * read with the runtime's RGBA copy. */
static bool publish_locked(ezcore_video_texture *texture,
                           const uint8_t *rgba, uint32_t width,
                           uint32_t height, ezcore_session *session) {
  size_t need = (size_t)width * height * 4;
  if (need == 0) return false;
  if (!rgba && !session) return false;

  int index = next_writable_slot(texture);
  if (index < 0) {
    texture->stats.frames_dropped++;
    return false;
  }
  struct video_slot *slot = &texture->slots[index];
  if (slot->capacity < need) {
    uint8_t *grown = malloc(need);
    if (!grown) {
      texture->stats.frames_dropped++;
      return false;
    }
    free(slot->data);
    slot->data = grown;
    slot->capacity = need;
    texture->stats.buffer_growths++;
  }

  size_t copied;
  if (rgba) {
    memcpy(slot->data, rgba, need);
    copied = need;
  } else {
    copied = ezcore_frame_pixels_copy(session, slot->data, slot->capacity);
    if (copied != need) {
      texture->stats.frames_dropped++;
      return false;
    }
  }
  slot->width = width;
  slot->height = height;
  slot->sequence = ++texture->sequence;
  texture->published = index;

  texture->stats.frames_published++;
  texture->stats.width = width;
  texture->stats.height = height;
  return true;
}

bool ezcore_video_texture_publish(ezcore_video_texture *texture,
                                  const uint8_t *rgba, uint32_t width,
                                  uint32_t height) {
  if (!texture) return false;
  if (width == 0 || height == 0 || !rgba) return false;
  ezcore_video_lock_acquire(texture->lock);
  bool ok = publish_locked(texture, rgba, width, height, NULL);
  ezcore_video_lock_release(texture->lock);
  return ok;
}

bool ezcore_video_texture_publish_session(ezcore_video_texture *texture,
                                          ezcore_session *session) {
  if (!texture || !session) return false;
  unsigned width = 0, height = 0;
  ezcore_frame_size(session, &width, &height);
  if (width == 0 || height == 0) return false;
  ezcore_video_lock_acquire(texture->lock);
  bool ok = publish_locked(texture, NULL, width, height, session);
  ezcore_video_lock_release(texture->lock);
  return ok;
}

const uint8_t *ezcore_video_texture_pixels(ezcore_video_texture *texture,
                                           uint32_t *width,
                                           uint32_t *height) {
  if (width) *width = 0;
  if (height) *height = 0;
  if (!texture) return NULL;

  ezcore_video_lock_acquire(texture->lock);
  if (texture->held >= 0) texture->slots[texture->held].held = false;
  texture->held = -1;
  int index = texture->published;
  if (index >= 0) {
    texture->slots[index].held = true;
    texture->held = index;
  }
  const uint8_t *data = index >= 0 ? texture->slots[index].data : NULL;
  uint32_t w = index >= 0 ? texture->slots[index].width : 0;
  uint32_t h = index >= 0 ? texture->slots[index].height : 0;
  ezcore_video_lock_release(texture->lock);

  if (width) *width = w;
  if (height) *height = h;
  return data;
}

void ezcore_video_texture_stats_get(ezcore_video_texture *texture,
                                    ezcore_video_texture_stats *out) {
  if (!texture || !out) return;
  ezcore_video_lock_acquire(texture->lock);
  *out = texture->stats;
  ezcore_video_lock_release(texture->lock);
}

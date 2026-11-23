// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* ezcore_video.c — CPU-core video texture bridge.
 *
 * A Flutter SurfaceProducer hands its android.view.Surface to the runtime as an
 * ANativeWindow. Each completed frame is copied from the session's latest
 * XRGB8888 picture into that window; ANativeWindow_unlockAndPost hands the
 * filled buffer to the compositor, where the Flutter Texture widget samples it.
 * The copy and the attach/present state machine are platform-neutral so they
 * can be tested on a host; only the window lock is Android-only.
 */
#include "ezcore_runtime.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#if defined(__ANDROID__)
#include <android/native_window.h>
#endif

#define EZCORE_MAX_VIDEOS 8u

typedef struct {
  ezcore_session *session;
  void *window;
  unsigned width, height;
  uint64_t presents, failed_presents;
  bool active;
} video_slot;

static video_slot g_slots[EZCORE_MAX_VIDEOS];
static atomic_flag g_video_lock = ATOMIC_FLAG_INIT;

static void video_lock(void) {
  while (atomic_flag_test_and_set_explicit(&g_video_lock, memory_order_acquire)) {
  }
}

static void video_unlock(void) {
  atomic_flag_clear_explicit(&g_video_lock, memory_order_release);
}

static video_slot *find_slot(ezcore_session *s, bool create) {
  video_slot *free_slot = NULL;
  for (unsigned i = 0; i < EZCORE_MAX_VIDEOS; i++) {
    if (g_slots[i].session == s) return &g_slots[i];
    if (create && !free_slot && !g_slots[i].session) free_slot = &g_slots[i];
  }
  return create ? free_slot : NULL;
}

bool ezcore_video_blit_rows(uint8_t *dst, size_t dst_stride,
                            const uint32_t *src, unsigned width,
                            unsigned height, bool bgra) {
  if (!dst || !src || width == 0 || height == 0) return false;
  if (dst_stride < (size_t)width * 4u) return false;
  for (unsigned y = 0; y < height; y++) {
    uint8_t *row = dst + (size_t)y * dst_stride;
    const uint32_t *pixels = src + (size_t)y * width;
    for (unsigned x = 0; x < width; x++) {
      const uint32_t p = pixels[x];
      const uint8_t red = (uint8_t)((p >> 16) & 0xFFu);
      const uint8_t green = (uint8_t)((p >> 8) & 0xFFu);
      const uint8_t blue = (uint8_t)(p & 0xFFu);
      uint8_t *out = row + (size_t)x * 4u;
      out[0] = bgra ? blue : red;
      out[1] = green;
      out[2] = bgra ? red : blue;
      out[3] = 0xFFu;
    }
  }
  return true;
}

bool ezcore_video_attach(ezcore_session *s, void *window, unsigned width,
                         unsigned height) {
  if (!s || !window || width == 0 || height == 0) return false;
#if defined(__ANDROID__)
  /* Match the producer's size and ask for 32-bit colour. A window that
   * refuses the geometry cannot be written safely; surface_changed may
   * still move it later, which present checks against the frame size. */
  if (ANativeWindow_setBuffersGeometry((ANativeWindow *)window,
                                       (int32_t)width, (int32_t)height,
                                       WINDOW_FORMAT_RGBA_8888) != 0) {
    return false;
  }
#endif
  video_lock();
  video_slot *slot = find_slot(s, true);
  if (!slot) {
    video_unlock();
    return false;
  }
  slot->session = s;
  slot->window = window;
  slot->width = width;
  slot->height = height;
  slot->presents = 0;
  slot->failed_presents = 0;
  slot->active = true;
  video_unlock();
  return true;
}

void ezcore_video_detach(ezcore_session *s) {
  if (!s) return;
  video_lock();
  video_slot *slot = find_slot(s, false);
  if (slot && slot->active) {
    /* The handle came from ANativeWindow_fromSurface and is owned by us. */
#if defined(__ANDROID__)
    if (slot->window) ANativeWindow_release((ANativeWindow *)slot->window);
#endif
    memset(slot, 0, sizeof(*slot));
  }
  video_unlock();
}

bool ezcore_video_present(ezcore_session *s) {
  if (!s) return false;
  video_lock();
  video_slot *slot = find_slot(s, false);
  void *window = slot && slot->active ? slot->window : NULL;
  video_unlock();
  if (!window) return false;

  unsigned w = 0, h = 0;
  const uint32_t *frame = ezcore_frame_pixels(s, &w, &h);
  bool ok = false;
#if defined(__ANDROID__)
  if (frame && w && h) {
    ANativeWindow_Buffer buffer;
    if (ANativeWindow_lock((ANativeWindow *)window, &buffer, NULL) == 0) {
      if (buffer.width >= (int32_t)w && buffer.height >= (int32_t)h) {
        const bool bgra = buffer.format == WINDOW_FORMAT_BGRA_8888;
        ok = ezcore_video_blit_rows((uint8_t *)buffer.bits,
                                    (size_t)buffer.stride * 4u, frame, w, h,
                                    bgra);
      }
      ANativeWindow_unlockAndPost((ANativeWindow *)window);
    }
  }
#else
  /* Host builds keep the state machine testable but cannot own a window. */
  (void)frame;
  (void)w;
  (void)h;
#endif

  video_lock();
  slot = find_slot(s, false);
  if (slot && slot->active) {
    if (ok) slot->presents++;
    else slot->failed_presents++;
  }
  video_unlock();
  return ok;
}

bool ezcore_video_stats(ezcore_session *s, ezcore_video_statistics *out) {
  if (!s || !out) return false;
  video_lock();
  const video_slot *slot = find_slot(s, false);
  if (!slot || !slot->active) {
    video_unlock();
    return false;
  }
  out->presents = slot->presents;
  out->failed_presents = slot->failed_presents;
  out->width = slot->width;
  out->height = slot->height;
  out->attached = true;
  video_unlock();
  return true;
}

// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

#ifndef EZCORE_AUDIO_INTERNAL_H
#define EZCORE_AUDIO_INTERNAL_H

#include "ezcore_runtime.h"

#ifdef __cplusplus
extern "C" {
#endif

/* The one process-wide audio device, or NULL when none is open. */
ezcore_audio *ezcore_audio_active(void);

/* Enqueue stereo s16 frames from the core's libretro audio callback into the
 * lock-free ring. Returns the number of frames accepted; the remainder is
 * counted as overruns. Safe to call from the thread running the core. */
size_t ezcore_audio_feed(const int16_t *frames, size_t frame_count);

#ifdef __cplusplus
}
#endif

#endif /* EZCORE_AUDIO_INTERNAL_H */

// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* One small mutex seam for the desktop video texture bridge. POSIX uses a
 * pthread mutex, Windows a critical section; exactly one implementation is
 * compiled per platform, just like the dynamic-loader seam. */
#ifndef EZCORE_VIDEO_LOCK_H
#define EZCORE_VIDEO_LOCK_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ezcore_video_lock ezcore_video_lock;

ezcore_video_lock *ezcore_video_lock_create(void);
void ezcore_video_lock_destroy(ezcore_video_lock *lock);
void ezcore_video_lock_acquire(ezcore_video_lock *lock);
void ezcore_video_lock_release(ezcore_video_lock *lock);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif  /* EZCORE_VIDEO_LOCK_H */

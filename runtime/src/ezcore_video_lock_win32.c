// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

#include "ezcore_video_lock.h"

#include <windows.h>
#include <stdlib.h>

struct ezcore_video_lock {
  CRITICAL_SECTION section;
};

ezcore_video_lock *ezcore_video_lock_create(void) {
  ezcore_video_lock *lock = malloc(sizeof(*lock));
  if (!lock) return NULL;
  InitializeCriticalSection(&lock->section);
  return lock;
}

void ezcore_video_lock_destroy(ezcore_video_lock *lock) {
  if (!lock) return;
  DeleteCriticalSection(&lock->section);
  free(lock);
}

void ezcore_video_lock_acquire(ezcore_video_lock *lock) {
  if (lock) EnterCriticalSection(&lock->section);
}

void ezcore_video_lock_release(ezcore_video_lock *lock) {
  if (lock) LeaveCriticalSection(&lock->section);
}

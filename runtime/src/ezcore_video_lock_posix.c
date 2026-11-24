// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

#include "ezcore_video_lock.h"

#include <pthread.h>
#include <stdlib.h>

struct ezcore_video_lock {
  pthread_mutex_t mutex;
};

ezcore_video_lock *ezcore_video_lock_create(void) {
  ezcore_video_lock *lock = malloc(sizeof(*lock));
  if (!lock) return NULL;
  if (pthread_mutex_init(&lock->mutex, NULL) != 0) {
    free(lock);
    return NULL;
  }
  return lock;
}

void ezcore_video_lock_destroy(ezcore_video_lock *lock) {
  if (!lock) return;
  pthread_mutex_destroy(&lock->mutex);
  free(lock);
}

void ezcore_video_lock_acquire(ezcore_video_lock *lock) {
  if (lock) pthread_mutex_lock(&lock->mutex);
}

void ezcore_video_lock_release(ezcore_video_lock *lock) {
  if (lock) pthread_mutex_unlock(&lock->mutex);
}

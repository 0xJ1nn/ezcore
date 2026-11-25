// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/* Turns the Surface from a Flutter SurfaceProducer into the ANativeWindow the
 * runtime writes into. The handle is owned by the runtime while attached and
 * released here when the player closes or the activity is destroyed. */
#include <jni.h>
#include <stdint.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>

JNIEXPORT jlong JNICALL
Java_com_ezcore_app_VideoTextureBridge_nativeWindowFromSurface(
    JNIEnv *env, jobject thiz, jobject surface) {
  (void)thiz;
  if (!surface) return 0;
  return (jlong)(uintptr_t)ANativeWindow_fromSurface(env, surface);
}

JNIEXPORT void JNICALL
Java_com_ezcore_app_VideoTextureBridge_releaseNativeWindow(
    JNIEnv *env, jobject thiz, jlong handle) {
  (void)env;
  (void)thiz;
  if (handle != 0) {
    ANativeWindow_release((ANativeWindow *)(uintptr_t)handle);
  }
}

// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception
package com.ezcore.app

import android.view.Surface
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/// Registers one Flutter surface texture for the player and hands its native
/// window to the runtime through the `ezcore/video` channel. Frames never
/// cross the channel: Dart only asks Flutter to composite the new surface.
class VideoTextureBridge(private val engine: FlutterEngine) {
    private var producer: TextureRegistry.SurfaceProducer? = null
    private var window: Long = 0L

    companion object {
        init {
            System.loadLibrary("ezcore_surface")
        }
    }

    private external fun nativeWindowFromSurface(surface: Surface): Long
    private external fun releaseNativeWindow(handle: Long)

    fun install() {
        MethodChannel(engine.dartExecutor.binaryMessenger, "ezcore/video")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "create" -> {
                            val width = (call.argument<Number>("width")?.toInt() ?: 0)
                            val height = (call.argument<Number>("height")?.toInt() ?: 0)
                            require(width > 0 && height > 0) { "Invalid texture size" }
                            result.success(create(width, height))
                        }
                        "frameReady" -> {
                            // A frame was written into the window; ask the
                            // compositor to sample it into the Texture widget.
                            producer?.scheduleFrame()
                            result.success(null)
                        }
                        "release" -> {
                            release()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("video", e.message, null)
                }
            }
    }

    private fun create(width: Int, height: Int): Map<String, Any> {
        release()
        val next = engine.renderer.createSurfaceProducer(
            TextureRegistry.SurfaceLifecycle.manual
        )
        next.setSize(width, height)
        val handle = nativeWindowFromSurface(next.surface)
        if (handle == 0L) {
            next.release()
            throw IllegalStateException("Surface has no native window")
        }
        producer = next
        window = handle
        // The runtime owns the window handle until Dart asks us to release it.
        return mapOf(
            "textureId" to next.id(),
            "window" to handle,
            "width" to width,
            "height" to height
        )
    }

    fun release() {
        if (window != 0L) {
            releaseNativeWindow(window)
            window = 0L
        }
        producer?.release()
        producer = null
    }
}

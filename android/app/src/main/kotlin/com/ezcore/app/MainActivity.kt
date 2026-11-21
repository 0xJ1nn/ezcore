package com.ezcore.app

import android.app.Activity
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.hardware.input.InputManager
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Device PCM sink for the `ezcore/audio` channel: signed-16 stereo,
/// streaming. Non-blocking writes so a stalled device clips instead of
/// janking the frame loop; the player surfaces errors, never silence.
class MainActivity : FlutterActivity() {
    private var track: AudioTrack? = null
    private var gamepadChannel: MethodChannel? = null
    // Save-backup picker: at most one launched tree owns the pending result,
    // so a cancel and a success each answer Dart exactly once.
    private var pendingBackupPick: MethodChannel.Result? = null
    private val backupPickRequestCode = 0x4255434B // 'BUCK'
    private var padConnected: Boolean = false
    // Stick-as-dpad latch state so held sticks don't spam releases wrongly.
    private val stickHeld = mutableSetOf<String>()
    private var inputManager: InputManager? = null
    private val deviceListener = object : InputManager.InputDeviceListener {
        override fun onInputDeviceAdded(deviceId: Int) {}
        override fun onInputDeviceRemoved(deviceId: Int) {
            if (padConnected) {
                padConnected = false
                stickHeld.clear()
                gamepadChannel?.invokeMethod(
                    "connection", mapOf("connected" to false, "name" to ""))
            }
        }
        override fun onInputDeviceChanged(deviceId: Int) {}
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "ezcore/audio")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            val rate = (call.argument<Double>("sampleRate") ?: 44100.0)
                                .toInt().coerceIn(8000, 192000)
                            start(rate)
                            result.success(null)
                        }
                        "write" -> {
                            val data = call.arguments as? ByteArray
                                ?: return@setMethodCallHandler result.error(
                                    "audio", "Missing PCM", null)
                            write(data)
                            result.success(null)
                        }
                        "stop" -> {
                            stop()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("audio", e.message, null)
                }
            }
        // Packaged native locations: cores + runtime ship in jniLibs and
        // resolve here so Dart never hardcodes device paths.
        MethodChannel(engine.dartExecutor.binaryMessenger, "ezcore/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bundledCoresDir" ->
                        result.success(applicationInfo.nativeLibraryDir)
                    "runtimeRef" -> result.success(mapOf(
                        "kind" to "path",
                        "path" to applicationInfo.nativeLibraryDir +
                            "/libezcore_runtime.so"))
                    else -> result.notImplemented()
                }
            }
        // Save backups live in a durable SAF tree the person picks once; that
        // grant outlives the app. The other two methods answer honestly where
        // Android has no iCloud or system-equivalent folder picker contract.
        MethodChannel(engine.dartExecutor.binaryMessenger, "ezcore/backup")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickTree" -> {
                        if (pendingBackupPick != null) {
                            // One picker owns the request code at a time. A
                            // second launch would answer the first call with
                            // the wrong tree and strand its own reply.
                            result.success(null)
                        } else {
                            pendingBackupPick = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            }
                            try {
                                startActivityForResult(intent, backupPickRequestCode)
                            } catch (e: Exception) {
                                pendingBackupPick = null
                                result.success(null)
                            }
                        }
                    }
                    "probeFolder" -> {
                        val folder = call.argument<String>("folder")
                        result.success(folder != null && probeFolder(folder))
                    }
                    "icloudContainer" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
        // Physical gamepads: Android KeyEvent/MotionEvent translated to the
        // canonical ezcore/gamepad vocabulary (see lib/services/gamepad.dart).
        gamepadChannel =
            MethodChannel(engine.dartExecutor.binaryMessenger, "ezcore/gamepad")
        inputManager = getSystemService(INPUT_SERVICE) as InputManager
        inputManager?.registerInputDeviceListener(deviceListener, null)
    }

    private fun padCode(keyCode: Int): String? = when (keyCode) {
        KeyEvent.KEYCODE_BUTTON_A -> "a"
        KeyEvent.KEYCODE_BUTTON_B -> "b"
        KeyEvent.KEYCODE_BUTTON_X -> "x"
        KeyEvent.KEYCODE_BUTTON_Y -> "y"
        KeyEvent.KEYCODE_BUTTON_L1 -> "lb"
        KeyEvent.KEYCODE_BUTTON_R1 -> "rb"
        KeyEvent.KEYCODE_BUTTON_L2 -> "lt"
        KeyEvent.KEYCODE_BUTTON_R2 -> "rt"
        KeyEvent.KEYCODE_BUTTON_THUMBL -> "l3"
        KeyEvent.KEYCODE_BUTTON_THUMBR -> "r3"
        KeyEvent.KEYCODE_BUTTON_START -> "start"
        KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.KEYCODE_BUTTON_MODE -> "select"
        KeyEvent.KEYCODE_DPAD_UP -> "up"
        KeyEvent.KEYCODE_DPAD_DOWN -> "down"
        KeyEvent.KEYCODE_DPAD_LEFT -> "left"
        KeyEvent.KEYCODE_DPAD_RIGHT -> "right"
        else -> null
    }

    private fun isGamepadEvent(event: KeyEvent): Boolean =
        event.source and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD ||
            event.source and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK

    private fun announcePad(deviceId: Int) {
        val name = InputDevice.getDevice(deviceId)?.name ?: "Controller"
        if (!padConnected) {
            padConnected = true
            gamepadChannel?.invokeMethod(
                "connection", mapOf("connected" to true, "name" to name))
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (isGamepadEvent(event)) {
            announcePad(event.deviceId)
            val code = padCode(event.keyCode)
            if (code != null &&
                (event.action == KeyEvent.ACTION_DOWN || event.action == KeyEvent.ACTION_UP)) {
                // Suppress key repeat: only genuine transitions cross the channel.
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0 ||
                    event.action == KeyEvent.ACTION_UP) {
                    gamepadChannel?.invokeMethod(
                        "button",
                        mapOf("code" to code,
                            "pressed" to (event.action == KeyEvent.ACTION_DOWN)))
                }
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun stickDirection(axis: Int, value: Float): String? {
        val v = if (value.isNaN()) 0f else value
        return when (axis) {
            MotionEvent.AXIS_X, MotionEvent.AXIS_Z ->
                if (v > 0.5f) "right" else if (v < -0.5f) "left" else null
            MotionEvent.AXIS_Y, MotionEvent.AXIS_RZ ->
                if (v > 0.5f) "down" else if (v < -0.5f) "up" else null
            MotionEvent.AXIS_HAT_X ->
                if (v > 0.5f) "right" else if (v < -0.5f) "left" else null
            MotionEvent.AXIS_HAT_Y ->
                if (v > 0.5f) "down" else if (v < -0.5f) "up" else null
            else -> null
        }
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        if (event.source and InputDevice.SOURCE_JOYSTICK ==
            InputDevice.SOURCE_JOYSTICK &&
            event.action == MotionEvent.ACTION_MOVE) {
            announcePad(event.deviceId)
            val axes = intArrayOf(
                MotionEvent.AXIS_X, MotionEvent.AXIS_Y,
                MotionEvent.AXIS_Z, MotionEvent.AXIS_RZ,
                MotionEvent.AXIS_HAT_X, MotionEvent.AXIS_HAT_Y)
            val now = mutableSetOf<String>()
            for (axis in axes) {
                stickDirection(axis, event.getAxisValue(axis))?.let { now.add(it) }
            }
            for (code in now - stickHeld) {
                gamepadChannel?.invokeMethod(
                    "button", mapOf("code" to code, "pressed" to true))
            }
            for (code in stickHeld - now) {
                gamepadChannel?.invokeMethod(
                    "button", mapOf("code" to code, "pressed" to false))
            }
            stickHeld.clear()
            stickHeld.addAll(now)
            return true
        }
        return super.dispatchGenericMotionEvent(event)
    }

    private fun start(rate: Int) {
        stop()
        val minBuf = AudioTrack.getMinBufferSize(
            rate, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        require(minBuf > 0) { "Unsupported sample rate $rate" }
        track = if (Build.VERSION.SDK_INT >= 26) {
            AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build())
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(rate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                        .build())
                .setBufferSizeInBytes(minBuf * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()
        } else {
            @Suppress("DEPRECATION")
            AudioTrack(
                AudioManager.STREAM_MUSIC, rate,
                AudioFormat.CHANNEL_OUT_STEREO,
                AudioFormat.ENCODING_PCM_16BIT, minBuf * 2,
                AudioTrack.MODE_STREAM)
        }
        track?.play()
    }

    private fun write(data: ByteArray) {
        val t = track ?: throw IllegalStateException("Output not started")
        require(data.isNotEmpty() && data.size % 4 == 0) { "Incomplete stereo PCM" }
        require(data.size <= 262144) { "PCM chunk too large" }
        // Non-blocking: a full device buffer clips this chunk instead of
        // blocking the platform thread (API 21+, always true here).
        t.write(data, 0, data.size, AudioTrack.WRITE_NON_BLOCKING)
    }

    private fun stop() {
        track?.release()
        track = null
    }

    /// Writes and removes a throwaway file inside a granted SAF tree so the
    /// locator knows the folder will still take saves after a reinstall. A
    /// tree grant has no plain filesystem path, so DocumentsContract works
    /// against the grant directly without pulling in a documentfile library.
    private fun probeFolder(folder: String): Boolean {
        val resolver = contentResolver
        return try {
            val treeUri = Uri.parse(folder)
            val parent = DocumentsContract.buildDocumentUriUsingTree(
                treeUri, DocumentsContract.getTreeDocumentId(treeUri))
            val probe = DocumentsContract.createDocument(
                resolver, parent, "application/octet-stream", ".ezcore_backup_probe")
                ?: return false
            try {
                val out = resolver.openOutputStream(probe) ?: return false
                out.use { it.write("ok".toByteArray()); it.flush() }
                val input = resolver.openInputStream(probe) ?: return false
                input.use { it.readBytes().isNotEmpty() }
            } finally {
                try {
                    DocumentsContract.deleteDocument(resolver, probe)
                } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            false
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == backupPickRequestCode) {
            val pending = pendingBackupPick
            pendingBackupPick = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                // A grant the platform refuses to persist dies on reboot.
                // Answering with it would claim a durable folder the app
                // cannot write after a restart or reinstall.
                val persisted = try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    true
                } catch (_: Exception) {
                    false
                }
                pending?.success(if (persisted) uri.toString() else null)
            } else {
                pending?.success(null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        inputManager?.unregisterInputDeviceListener(deviceListener)
        stop()
        super.onDestroy()
    }
}

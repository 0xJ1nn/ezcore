import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Dart FFI binding over `runtime/build/libezcore_runtime.dylib` (ABI v1).
///
/// Resolution order for the runtime library (desktop dev only):
/// `EZCORE_RUNTIME_LIB` env → `runtime/build/libezcore_runtime.dylib` (repo root).
/// Zero third-party dependencies: UTF-8 is encoded/decoded by hand.
class EzCoreRuntime {
  EzCoreRuntime.load({String? runtimePath})
      : _lib = DynamicLibrary.open(
          runtimePath ??
              Platform.environment['EZCORE_RUNTIME_LIB'] ??
              'runtime/build/libezcore_runtime.dylib',
        ) {
    _bind();
  }

  /// Binds to an already-open handle. Used with [DynamicLibrary.process()]
  /// on iOS (static link) and in tests with mock libraries.
  EzCoreRuntime.fromHandle(DynamicLibrary lib) : _lib = lib {
    _bind();
  }

  /// Opens from an isolate-safe marker (see NativeRuntimeRef): `process`
  /// binds the current process, otherwise the path is dlopened.
  factory EzCoreRuntime.fromMarker(Map marker) {
    if (marker['kind'] == 'process') {
      return EzCoreRuntime.fromHandle(DynamicLibrary.process());
    }
    final path = marker['path'] as String?;
    if (path == null || path.isEmpty) {
      throw StateError('Runtime marker has no path');
    }
    return EzCoreRuntime.load(runtimePath: path);
  }

  void _bind() {
    _abiVersion = _lib
        .lookup<NativeFunction<Int32 Function()>>('ezcore_abi_version')
        .asFunction<int Function()>();
    _load = _lib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(
                    Pointer<Uint8>, Pointer<Uint8>, IntPtr)>>('ezcore_load')
        .asFunction<
            Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>, int)>();
    _unload = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('ezcore_unload')
        .asFunction<void Function(Pointer<Void>)>();
    _init = _lib
        .lookup<NativeFunction<Bool Function(Pointer<Void>)>>('ezcore_init')
        .asFunction<bool Function(Pointer<Void>)>();
    _reset = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('ezcore_reset')
        .asFunction<void Function(Pointer<Void>)>();
    _coreName = _lib
        .lookup<NativeFunction<Pointer<Uint8> Function(Pointer<Void>)>>(
            'ezcore_core_name')
        .asFunction<Pointer<Uint8> Function(Pointer<Void>)>();
    _coreVersion = _lib
        .lookup<NativeFunction<Pointer<Uint8> Function(Pointer<Void>)>>(
            'ezcore_core_version')
        .asFunction<Pointer<Uint8> Function(Pointer<Void>)>();
    _geometry = _lib
        .lookup<
            NativeFunction<
                Void Function(Pointer<Void>, Pointer<Uint32>,
                    Pointer<Uint32>, Pointer<Double>)>>('ezcore_system_geometry')
        .asFunction<
            void Function(Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>,
                Pointer<Double>)>();
    _sampleRate = _lib
        .lookup<NativeFunction<Double Function(Pointer<Void>)>>(
            'ezcore_sample_rate')
        .asFunction<double Function(Pointer<Void>)>();
    _loadGame = _lib
        .lookup<
            NativeFunction<
                Bool Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
                    IntPtr)>>('ezcore_load_game')
        .asFunction<
            bool Function(
                Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)>();
    _runFrame = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('ezcore_run_frame')
        .asFunction<void Function(Pointer<Void>)>();
    _framePixels = _lib
        .lookup<
            NativeFunction<
                Pointer<Uint32> Function(Pointer<Void>, Pointer<Uint32>,
                    Pointer<Uint32>)>>('ezcore_frame_pixels')
        .asFunction<
            Pointer<Uint32> Function(
                Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>)>();
    _framePixelsCopy = _lib
        .lookup<
            NativeFunction<
                IntPtr Function(Pointer<Void>, Pointer<Uint8>,
                    IntPtr)>>('ezcore_frame_pixels_copy')
        .asFunction<int Function(Pointer<Void>, Pointer<Uint8>, int)>();
    _frameSize = _lib
        .lookup<
            NativeFunction<
                Void Function(Pointer<Void>, Pointer<Uint32>,
                    Pointer<Uint32>)>>('ezcore_frame_size')
        .asFunction<
            void Function(Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>)>();
    _cheatReset = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
            'ezcore_cheat_reset')
        .asFunction<void Function(Pointer<Void>)>();
    _cheatSet = _lib
        .lookup<
            NativeFunction<
                Bool Function(Pointer<Void>, Uint32, Bool,
                    Pointer<Uint8>)>>('ezcore_cheat_set')
        .asFunction<
            bool Function(Pointer<Void>, int, bool, Pointer<Uint8>)>();
    _setDirs = _lib
        .lookup<
            NativeFunction<
                Void Function(Pointer<Uint8>, Pointer<Uint8>)>>(
            'ezcore_set_dirs')
        .asFunction<void Function(Pointer<Uint8>, Pointer<Uint8>)>();
    _serializeSize = _lib
        .lookup<NativeFunction<IntPtr Function(Pointer<Void>)>>(
            'ezcore_serialize_size')
        .asFunction<int Function(Pointer<Void>)>();
    _serialize = _lib
        .lookup<
            NativeFunction<
                Bool Function(
                    Pointer<Void>, Pointer<Uint8>, IntPtr)>>(
            'ezcore_serialize')
        .asFunction<bool Function(Pointer<Void>, Pointer<Uint8>, int)>();
    _unserialize = _lib
        .lookup<
            NativeFunction<
                Bool Function(
                    Pointer<Void>, Pointer<Uint8>, IntPtr)>>(
            'ezcore_unserialize')
        .asFunction<bool Function(Pointer<Void>, Pointer<Uint8>, int)>();
    _audioDrain = _lib
        .lookup<
            NativeFunction<
                IntPtr Function(Pointer<Void>, Pointer<Int16>, IntPtr)>>(
            'ezcore_audio_drain')
        .asFunction<int Function(Pointer<Void>, Pointer<Int16>, int)>();
    _audioPending = _lib
        .lookup<NativeFunction<IntPtr Function(Pointer<Void>)>>(
            'ezcore_audio_pending')
        .asFunction<int Function(Pointer<Void>)>();
    _setButton = _lib
        .lookup<
            NativeFunction<
                Void Function(Pointer<Void>, Uint32, Uint32, Bool)>>(
            'ezcore_set_button')
        .asFunction<void Function(Pointer<Void>, int, int, bool)>();
    _clearButtons = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Uint32)>>(
            'ezcore_clear_buttons')
        .asFunction<void Function(Pointer<Void>, int)>();
  }

  final DynamicLibrary _lib;
  late final int Function() _abiVersion;
  late final Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>, int) _load;
  late final void Function(Pointer<Void>) _unload;
  late final bool Function(Pointer<Void>) _init;
  late final void Function(Pointer<Void>) _reset;
  late final Pointer<Uint8> Function(Pointer<Void>) _coreName;
  late final Pointer<Uint8> Function(Pointer<Void>) _coreVersion;
  late final void Function(Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>,
      Pointer<Double>) _geometry;
  late final double Function(Pointer<Void>) _sampleRate;
  late final bool Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)
      _loadGame;
  late final void Function(Pointer<Void>) _runFrame;
  late final Pointer<Uint32> Function(
      Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>) _framePixels;
  late final int Function(Pointer<Void>, Pointer<Uint8>, int) _framePixelsCopy;
  late final void Function(
      Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>) _frameSize;
  late final void Function(Pointer<Void>) _cheatReset;
  late final bool Function(Pointer<Void>, int, bool, Pointer<Uint8>) _cheatSet;
  late final void Function(Pointer<Uint8>, Pointer<Uint8>) _setDirs;
  late final int Function(Pointer<Void>) _serializeSize;
  late final bool Function(Pointer<Void>, Pointer<Uint8>, int) _serialize;
  late final bool Function(Pointer<Void>, Pointer<Uint8>, int) _unserialize;
  late final int Function(Pointer<Void>, Pointer<Int16>, int) _audioDrain;
  late final int Function(Pointer<Void>) _audioPending;
  late final void Function(Pointer<Void>, int, int, bool) _setButton;
  late final void Function(Pointer<Void>, int) _clearButtons;

  int abiVersion() => _abiVersion();

  Pointer<Void> loadSession(String corePath) {
    final pathPtr = _toNativeUtf8(corePath);
    final errPtr = _allocBytes(1024);
    try {
      final session = _load(pathPtr, errPtr, 1024);
      if (session.address == 0) {
        throw StateError('ezcore_load failed: ${_fromNativeUtf8(errPtr)}');
      }
      return session;
    } finally {
      _free(pathPtr);
      _free(errPtr);
    }
  }

  void unload(Pointer<Void> session) => _unload(session);
  bool init(Pointer<Void> session) => _init(session);
  void reset(Pointer<Void> session) => _reset(session);
  String coreName(Pointer<Void> session) => _fromNativeUtf8(_coreName(session));
  String coreVersion(Pointer<Void> session) =>
      _fromNativeUtf8(_coreVersion(session));

  ({int w, int h, double fps}) geometry(Pointer<Void> session) {
    final w = callocUint32();
    final h = callocUint32();
    final fps = callocDouble();
    try {
      _geometry(session, w, h, fps);
      return (w: w.value, h: h.value, fps: fps.value);
    } finally {
      _free(w);
      _free(h);
      _free(fps);
    }
  }

  double sampleRate(Pointer<Void> session) => _sampleRate(session);

  bool loadGame(Pointer<Void> session, String romPath, Uint8List data) {
    final pathPtr = _toNativeUtf8(romPath);
    final dataPtr = _allocBytes(data.length);
    try {
      dataPtr.asTypedList(data.length).setAll(0, data);
      return _loadGame(session, pathPtr, dataPtr, data.length);
    } finally {
      _free(pathPtr);
      _free(dataPtr);
    }
  }

  void runFrame(Pointer<Void> session) => _runFrame(session);

  void setDirs(String systemDir, String saveDir) {
    final sysPtr = _toNativeUtf8(systemDir);
    final savePtr = _toNativeUtf8(saveDir);
    try {
      _setDirs(sysPtr, savePtr);
    } finally {
      _free(sysPtr);
      _free(savePtr);
    }
  }

  void cheatReset(Pointer<Void> session) => _cheatReset(session);

  /// Returns whether the runtime dispatched the call to an available core hook.
  /// The libretro hook is void, so this does not validate the cheat code.
  bool cheatSet(
      Pointer<Void> session, int index, bool enabled, String code) {
    final codePtr = _toNativeUtf8(code);
    try {
      return _cheatSet(session, index, enabled, codePtr);
    } finally {
      _free(codePtr);
    }
  }

  /// Copies the latest frame's pixels as RGBA bytes.
  /// Returns null when no frame is available.
  /// The returned buffer is exactly width*height*4 bytes.
  Uint8List? frameBytes(Pointer<Void> session) {
    final w = callocUint32();
    final h = callocUint32();
    try {
      _frameSize(session, w, h);
      final width = w.value;
      final height = h.value;
      if (width == 0 || height == 0) return null;
      final size = width * height * 4;
      final buf = _allocBytes(size);
      try {
        final copied = _framePixelsCopy(session, buf, size);
        if (copied != size) return null;
        return Uint8List.fromList(buf.asTypedList(copied));
      } finally {
        _free(buf);
      }
    } finally {
      _free(w);
      _free(h);
    }
  }

  /// Drains up to [frames] audio frames (stereo s16) into a PCM buffer.
  /// Returns the actual number of frames drained (0 if none available).
  /// Each frame is 4 bytes (2 channels × 2 bytes).
  int drainAudio(Pointer<Void> session, int frames, ByteBuffer buffer) {
    final maxSamples = frames * 2;
    final bufPtr = _allocBytes(maxSamples * 2);
    try {
      final drained = _audioDrain(session, bufPtr.cast<Int16>(), frames);
      if (drained > 0) {
        final byteCount = drained * 2 * 2;
        final view = bufPtr.asTypedList(byteCount);
        buffer.asUint8List().setAll(0, view);
      }
      return drained;
    } finally {
      _free(bufPtr);
    }
  }

  /// Returns the number of audio frames currently queued in the ring buffer.
  int audioPending(Pointer<Void> session) => _audioPending(session);

  /// Sets a button state for a given port. buttonId is RETRO_DEVICE_ID_JOYPAD_*.
  void setButton(Pointer<Void> session, int port, int buttonId, bool pressed) {
    _setButton(session, port, buttonId, pressed);
  }

  /// Clears all buttons for a port.
  void clearButtons(Pointer<Void> session, int port) {
    _clearButtons(session, port);
  }

  /// Captures a save state via the runtime. Null when the core has no
  /// content loaded or omits serialization. Bytes are opaque to the
  /// frontend — the sync layer moves them without interpreting them.
  Uint8List? saveState(Pointer<Void> session) {
    final size = _serializeSize(session);
    if (size <= 0) return null;
    final buf = _allocBytes(size);
    try {
      if (!_serialize(session, buf, size)) return null;
      return Uint8List.fromList(buf.asTypedList(size));
    } finally {
      _free(buf);
    }
  }

  bool loadState(Pointer<Void> session, Uint8List bytes) {
    if (bytes.isEmpty) return false;
    final buf = _allocBytes(bytes.length);
    try {
      buf.asTypedList(bytes.length).setAll(0, bytes);
      return _unserialize(session, buf, bytes.length);
    } finally {
      _free(buf);
    }
  }

  /// Drains up to [frames] audio frames from the ring buffer (legacy API).
  /// Returns the number of frames actually drained.
  int audioFrames(Pointer<Void> session, {int frames = 1024}) {
    final buf = _allocBytes(frames * 4); // stereo s16: 4 bytes per frame
    try {
      return _audioDrain(session, buf.cast<Int16>(), frames);
    } finally {
      _free(buf);
    }
  }

  /// Sums the current frame's pixels (0 when no frame yet).
  int pixelSum(Pointer<Void> session) {
    final w = callocUint32();
    final h = callocUint32();
    try {
      final px = _framePixels(session, w, h);
      if (px.address == 0) return 0;
      final total = w.value * h.value;
      var sum = 0;
      for (var i = 0; i < total; i++) {
        sum += px[i];
      }
      return sum;
    } finally {
      _free(w);
      _free(h);
    }
  }

  // --- minimal native memory helpers (no package:ffi) ---

  /// Encodes a Dart string as UTF-8 with null terminator.
  Pointer<Uint8> _toNativeUtf8(String s) {
    final encoded = utf8.encode(s);
    final ptr = _allocBytes(encoded.length + 1);
    for (var i = 0; i < encoded.length; i++) {
      ptr[i] = encoded[i];
    }
    ptr[encoded.length] = 0;
    return ptr;
  }

  /// Decodes a null-terminated UTF-8 native string.
  String _fromNativeUtf8(Pointer<Uint8> ptr) {
    if (ptr.address == 0) return '';
    final bytes = <int>[];
    var i = 0;
    while (ptr[i] != 0 && i < 8192) {
      bytes.add(ptr[i]);
      i++;
    }
    return utf8.decode(bytes);
  }

  Pointer<Uint8> _allocBytes(int bytes) {
    final ptr = _libcMalloc(bytes).cast<Uint8>();
    for (var i = 0; i < bytes; i++) {
      ptr[i] = 0;
    }
    return ptr;
  }

  Pointer<Uint8> calloc(int bytes) => _allocBytes(bytes);
  Pointer<Uint32> callocUint32() => _allocBytes(4).cast();
  Pointer<Double> callocDouble() => _allocBytes(8).cast();
  void _free(Pointer ptr) => _libcFree(ptr.cast());
}

final _libcMalloc = DynamicLibrary.process().lookupFunction<
    Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('malloc');
final _libcFree = DynamicLibrary.process().lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)>('free');

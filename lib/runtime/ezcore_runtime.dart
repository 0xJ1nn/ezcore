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
            Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>, IntPtr)
          >
        >('ezcore_load')
        .asFunction<
          Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>, int)
        >();
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
          'ezcore_core_name',
        )
        .asFunction<Pointer<Uint8> Function(Pointer<Void>)>();
    _coreVersion = _lib
        .lookup<NativeFunction<Pointer<Uint8> Function(Pointer<Void>)>>(
          'ezcore_core_version',
        )
        .asFunction<Pointer<Uint8> Function(Pointer<Void>)>();
    _geometry = _lib
        .lookup<
          NativeFunction<
            Void Function(
              Pointer<Void>,
              Pointer<Uint32>,
              Pointer<Uint32>,
              Pointer<Double>,
            )
          >
        >('ezcore_system_geometry')
        .asFunction<
          void Function(
            Pointer<Void>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Double>,
          )
        >();
    _sampleRate = _lib
        .lookup<NativeFunction<Double Function(Pointer<Void>)>>(
          'ezcore_sample_rate',
        )
        .asFunction<double Function(Pointer<Void>)>();
    _loadGame = _lib
        .lookup<
          NativeFunction<
            Bool Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, IntPtr)
          >
        >('ezcore_load_game')
        .asFunction<
          bool Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)
        >();
    _runFrame = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'ezcore_run_frame',
        )
        .asFunction<void Function(Pointer<Void>)>();
    _framePixels = _lib
        .lookup<
          NativeFunction<
            Pointer<Uint32> Function(
              Pointer<Void>,
              Pointer<Uint32>,
              Pointer<Uint32>,
            )
          >
        >('ezcore_frame_pixels')
        .asFunction<
          Pointer<Uint32> Function(
            Pointer<Void>,
            Pointer<Uint32>,
            Pointer<Uint32>,
          )
        >();
    _framePixelsCopy = _lib
        .lookup<
          NativeFunction<IntPtr Function(Pointer<Void>, Pointer<Uint8>, IntPtr)>
        >('ezcore_frame_pixels_copy')
        .asFunction<int Function(Pointer<Void>, Pointer<Uint8>, int)>();
    _frameSize = _lib
        .lookup<
          NativeFunction<
            Void Function(Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>)
          >
        >('ezcore_frame_size')
        .asFunction<
          void Function(Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>)
        >();
    _cheatReset = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
          'ezcore_cheat_reset',
        )
        .asFunction<void Function(Pointer<Void>)>();
    _cheatSet = _lib
        .lookup<
          NativeFunction<
            Bool Function(Pointer<Void>, Uint32, Bool, Pointer<Uint8>)
          >
        >('ezcore_cheat_set')
        .asFunction<bool Function(Pointer<Void>, int, bool, Pointer<Uint8>)>();
    _setDirs = _lib
        .lookup<NativeFunction<Void Function(Pointer<Uint8>, Pointer<Uint8>)>>(
          'ezcore_set_dirs',
        )
        .asFunction<void Function(Pointer<Uint8>, Pointer<Uint8>)>();
    _serializeSize = _lib
        .lookup<NativeFunction<IntPtr Function(Pointer<Void>)>>(
          'ezcore_serialize_size',
        )
        .asFunction<int Function(Pointer<Void>)>();
    _serialize = _lib
        .lookup<
          NativeFunction<Bool Function(Pointer<Void>, Pointer<Uint8>, IntPtr)>
        >('ezcore_serialize')
        .asFunction<bool Function(Pointer<Void>, Pointer<Uint8>, int)>();
    _unserialize = _lib
        .lookup<
          NativeFunction<Bool Function(Pointer<Void>, Pointer<Uint8>, IntPtr)>
        >('ezcore_unserialize')
        .asFunction<bool Function(Pointer<Void>, Pointer<Uint8>, int)>();
    _audioDrain = _lib
        .lookup<
          NativeFunction<IntPtr Function(Pointer<Void>, Pointer<Int16>, IntPtr)>
        >('ezcore_audio_drain')
        .asFunction<int Function(Pointer<Void>, Pointer<Int16>, int)>();
    _audioPending = _lib
        .lookup<NativeFunction<IntPtr Function(Pointer<Void>)>>(
          'ezcore_audio_pending',
        )
        .asFunction<int Function(Pointer<Void>)>();
    _setButton = _lib
        .lookup<
          NativeFunction<Void Function(Pointer<Void>, Uint32, Uint32, Bool)>
        >('ezcore_set_button')
        .asFunction<void Function(Pointer<Void>, int, int, bool)>();
    _clearButtons = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Uint32)>>(
          'ezcore_clear_buttons',
        )
        .asFunction<void Function(Pointer<Void>, int)>();
    _setAnalog = _lib
        .lookup<
          NativeFunction<
            Void Function(Pointer<Void>, Uint32, Uint32, Uint32, Int16)
          >
        >('ezcore_set_analog')
        .asFunction<void Function(Pointer<Void>, int, int, int, int)>();
    _mouseMove = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Int32, Int32)>>(
          'ezcore_mouse_move',
        )
        .asFunction<void Function(Pointer<Void>, int, int)>();
    _setMouseButton = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>, Uint32, Bool)>>(
          'ezcore_set_mouse_button',
        )
        .asFunction<void Function(Pointer<Void>, int, bool)>();
    _setKey = _lib
        .lookup<
          NativeFunction<
            Void Function(Pointer<Void>, Uint32, Bool, Uint32, Uint16)
          >
        >('ezcore_set_key')
        .asFunction<void Function(Pointer<Void>, int, bool, int, int)>();
    _setPointer = _lib
        .lookup<
          NativeFunction<Void Function(Pointer<Void>, Int16, Int16, Bool)>
        >('ezcore_set_pointer')
        .asFunction<void Function(Pointer<Void>, int, int, bool)>();
    // --- core options & capability surface (ABI v1 additions) ---
    _coreOptionCount = _lib
        .lookup<NativeFunction<Uint32 Function(Pointer<Void>)>>(
          'ezcore_get_core_option_count',
        )
        .asFunction<int Function(Pointer<Void>)>();
    _getCoreOption = _lib
        .lookup<
          NativeFunction<
            Bool Function(
              Pointer<Void>,
              Uint32,
              Pointer<Pointer<Uint8>>,
              Pointer<Pointer<Uint8>>,
              Pointer<Pointer<Uint8>>,
            )
          >
        >('ezcore_get_core_option')
        .asFunction<
          bool Function(
            Pointer<Void>,
            int,
            Pointer<Pointer<Uint8>>,
            Pointer<Pointer<Uint8>>,
            Pointer<Pointer<Uint8>>,
          )
        >();
    _setCoreOption = _lib
        .lookup<
          NativeFunction<
            Bool Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)
          >
        >('ezcore_set_core_option')
        .asFunction<
          bool Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)
        >();
    _inputDescriptorCount = _lib
        .lookup<NativeFunction<Uint32 Function(Pointer<Void>)>>(
          'ezcore_get_input_descriptor_count',
        )
        .asFunction<int Function(Pointer<Void>)>();
    _getInputDescriptor = _lib
        .lookup<
          NativeFunction<
            Bool Function(
              Pointer<Void>,
              Uint32,
              Pointer<Uint32>,
              Pointer<Uint32>,
              Pointer<Uint32>,
              Pointer<Uint32>,
              Pointer<Pointer<Uint8>>,
            )
          >
        >('ezcore_get_input_descriptor')
        .asFunction<
          bool Function(
            Pointer<Void>,
            int,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Pointer<Uint8>>,
          )
        >();
    _controllerPortCount = _lib
        .lookup<NativeFunction<Uint32 Function(Pointer<Void>)>>(
          'ezcore_get_controller_port_count',
        )
        .asFunction<int Function(Pointer<Void>)>();
    _controllerPortTypeCount = _lib
        .lookup<NativeFunction<Uint32 Function(Pointer<Void>, Uint32)>>(
          'ezcore_get_controller_port_type_count',
        )
        .asFunction<int Function(Pointer<Void>, int)>();
    _controllerPortType = _lib
        .lookup<
          NativeFunction<
            Bool Function(Pointer<Void>, Uint32, Uint32, Pointer<Uint32>,
                Pointer<Pointer<Uint8>>)
          >
        >('ezcore_get_controller_port_type')
        .asFunction<
          bool Function(Pointer<Void>, int, int, Pointer<Uint32>,
              Pointer<Pointer<Uint8>>)
        >();
    _memoryDescriptorCount = _lib
        .lookup<NativeFunction<Uint32 Function(Pointer<Void>)>>(
          'ezcore_get_memory_descriptor_count',
        )
        .asFunction<int Function(Pointer<Void>)>();
    _getMemoryDescriptor = _lib
        .lookup<
          NativeFunction<
            Bool Function(
              Pointer<Void>,
              Uint32,
              Pointer<Uint64>,
              Pointer<Pointer<Void>>,
              Pointer<IntPtr>,
              Pointer<IntPtr>,
              Pointer<IntPtr>,
              Pointer<IntPtr>,
              Pointer<IntPtr>,
              Pointer<Pointer<Uint8>>,
            )
          >
        >('ezcore_get_memory_descriptor')
        .asFunction<
          bool Function(
            Pointer<Void>,
            int,
            Pointer<Uint64>,
            Pointer<Pointer<Void>>,
            Pointer<IntPtr>,
            Pointer<IntPtr>,
            Pointer<IntPtr>,
            Pointer<IntPtr>,
            Pointer<IntPtr>,
            Pointer<Pointer<Uint8>>,
          )
        >();
  }

  final DynamicLibrary _lib;
  late final int Function() _abiVersion;
  late final Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>, int) _load;
  late final void Function(Pointer<Void>) _unload;
  late final bool Function(Pointer<Void>) _init;
  late final void Function(Pointer<Void>) _reset;
  late final Pointer<Uint8> Function(Pointer<Void>) _coreName;
  late final Pointer<Uint8> Function(Pointer<Void>) _coreVersion;
  late final void Function(
    Pointer<Void>,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Double>,
  )
  _geometry;
  late final double Function(Pointer<Void>) _sampleRate;
  late final bool Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)
  _loadGame;
  late final void Function(Pointer<Void>) _runFrame;
  late final Pointer<Uint32> Function(
    Pointer<Void>,
    Pointer<Uint32>,
    Pointer<Uint32>,
  )
  _framePixels;
  late final int Function(Pointer<Void>, Pointer<Uint8>, int) _framePixelsCopy;
  late final void Function(Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>)
  _frameSize;
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
  late final void Function(Pointer<Void>, int, int, int, int) _setAnalog;
  late final void Function(Pointer<Void>, int, int) _mouseMove;
  late final void Function(Pointer<Void>, int, bool) _setMouseButton;
  late final void Function(Pointer<Void>, int, bool, int, int) _setKey;
  late final void Function(Pointer<Void>, int, int, bool) _setPointer;
  late final int Function(Pointer<Void>) _coreOptionCount;
  late final bool Function(
    Pointer<Void>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Pointer<Uint8>>,
    Pointer<Pointer<Uint8>>,
  )
  _getCoreOption;
  late final bool Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)
  _setCoreOption;
  late final int Function(Pointer<Void>) _inputDescriptorCount;
  late final bool Function(
    Pointer<Void>,
    int,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Uint32>,
    Pointer<Pointer<Uint8>>,
  )
  _getInputDescriptor;
  late final int Function(Pointer<Void>) _controllerPortCount;
  late final int Function(Pointer<Void>, int) _controllerPortTypeCount;
  late final bool Function(Pointer<Void>, int, int, Pointer<Uint32>,
      Pointer<Pointer<Uint8>>) _controllerPortType;
  late final int Function(Pointer<Void>) _memoryDescriptorCount;
  late final bool Function(
    Pointer<Void>,
    int,
    Pointer<Uint64>,
    Pointer<Pointer<Void>>,
    Pointer<IntPtr>,
    Pointer<IntPtr>,
    Pointer<IntPtr>,
    Pointer<IntPtr>,
    Pointer<IntPtr>,
    Pointer<Pointer<Uint8>>,
  )
  _getMemoryDescriptor;

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
  bool cheatSet(Pointer<Void> session, int index, bool enabled, String code) {
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

  /// Analog stick: [stick] 0 left / 1 right, [axis] 0 x / 1 y,
  /// [value] -32768..32767.
  void setAnalog(Pointer<Void> s, int port, int stick, int axis, int value) =>
      _setAnalog(s, port, stick, axis, value.clamp(-32768, 32767));

  /// Relative mouse motion, delivered to the core once per frame.
  void mouseMove(Pointer<Void> s, int dx, int dy) => _mouseMove(s, dx, dy);

  /// A mouse button, [id] a RETRO_DEVICE_ID_MOUSE_* value.
  void setMouseButton(Pointer<Void> s, int id, bool pressed) =>
      _setMouseButton(s, id, pressed);

  /// A key, [keycode] a RETROK_* value; also reaches the core's keyboard
  /// callback when it registered one.
  void setKey(
    Pointer<Void> s,
    int keycode,
    bool pressed, {
    int character = 0,
    int modifiers = 0,
  }) => _setKey(s, keycode, pressed, character, modifiers);

  /// The pointer (touchscreen) across the whole output, -32767..32767.
  void setPointer(Pointer<Void> s, int x, int y, bool pressed) =>
      _setPointer(s, x.clamp(-32767, 32767), y.clamp(-32767, 32767), pressed);

  /// Clears all buttons for a port.
  void clearButtons(Pointer<Void> session, int port) {
    _clearButtons(session, port);
  }

  // --- core options & capability surface (public wrappers) ---

  /// Number of core options registered by the loaded core.
  int coreOptionCount(Pointer<Void> session) {
    return _coreOptionCount(session);
  }

  /// Core option at [index] as (key, defaultValue, value), or null when the
  /// index is out of range. The strings are runtime-owned copies, valid until
  /// the next SET_CORE_OPTIONS* call or session unload.
  ({String key, String defaultValue, String value})? coreOption(
    Pointer<Void> session,
    int index,
  ) {
    final keyPtr = _allocBytes(sizeOf<IntPtr>()).cast<Pointer<Uint8>>();
    final defaultValuePtr = _allocBytes(
      sizeOf<IntPtr>(),
    ).cast<Pointer<Uint8>>();
    final valuePtr = _allocBytes(sizeOf<IntPtr>()).cast<Pointer<Uint8>>();
    try {
      if (!_getCoreOption(session, index, keyPtr, defaultValuePtr, valuePtr)) {
        return null;
      }
      return (
        key: _fromNativeUtf8(keyPtr.value),
        defaultValue: _fromNativeUtf8(defaultValuePtr.value),
        value: _fromNativeUtf8(valuePtr.value),
      );
    } finally {
      _free(keyPtr);
      _free(defaultValuePtr);
      _free(valuePtr);
    }
  }

  /// Sets the current value of a core option by key. The [value] is
  /// deep-copied into runtime memory; the caller's string may be reused.
  /// Returns true when the key matched an existing option.
  bool setCoreOption(Pointer<Void> session, String key, String value) {
    final keyPtr = _toNativeUtf8(key);
    final valuePtr = _toNativeUtf8(value);
    try {
      return _setCoreOption(session, keyPtr, valuePtr);
    } finally {
      _free(keyPtr);
      _free(valuePtr);
    }
  }

  /// Number of input descriptors registered via
  /// RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS.
  int inputDescriptorCount(Pointer<Void> session) {
    return _inputDescriptorCount(session);
  }

  /// Input descriptor at [index] as (port, device, descIndex, id,
  /// description), or null when the index is out of range.
  ({int port, int device, int descIndex, int id, String description})?
  inputDescriptor(Pointer<Void> session, int index) {
    final port = callocUint32();
    final device = callocUint32();
    final descIndex = callocUint32();
    final id = callocUint32();
    final description = _allocBytes(sizeOf<IntPtr>()).cast<Pointer<Uint8>>();
    try {
      if (!_getInputDescriptor(
        session,
        index,
        port,
        device,
        descIndex,
        id,
        description,
      )) {
        return null;
      }
      return (
        port: port.value,
        device: device.value,
        descIndex: descIndex.value,
        id: id.value,
        description: _fromNativeUtf8(description.value),
      );
    } finally {
      _free(port);
      _free(device);
      _free(descIndex);
      _free(id);
      _free(description);
    }
  }

  /// Number of controller ports with info registered via
  /// RETRO_ENVIRONMENT_SET_CONTROLLER_INFO.
  int controllerPortCount(Pointer<Void> session) {
    return _controllerPortCount(session);
  }

  /// Number of device types the core registered for [port] via
  /// RETRO_ENVIRONMENT_SET_CONTROLLER_INFO. Returns 0 when the port is out of
  /// range or the core registered none.
  int controllerPortTypeCount(Pointer<Void> session, int port) {
    return _controllerPortTypeCount(session, port);
  }

  /// One device type of [port] as (id, description), or null when the port or
  /// [typeIndex] is out of range.
  ///
  /// Iterate `port` over `0..controllerPortCount` and `typeIndex` over
  /// `0..controllerPortTypeCount` to enumerate every device a core accepts on
  /// every port. That is what a frontend needs to offer the right control
  /// scheme per port, and the prerequisite for non-joypad device support:
  /// until a core's declared capabilities were readable, a frontend could
  /// only assume every port was a joypad.
  ({int id, String description})? controllerPortType(
    Pointer<Void> session,
    int port,
    int typeIndex,
  ) {
    final id = callocUint32();
    final description = _allocBytes(sizeOf<IntPtr>()).cast<Pointer<Uint8>>();
    try {
      if (!_controllerPortType(session, port, typeIndex, id, description)) {
        return null;
      }
      return (id: id.value, description: _fromNativeUtf8(description.value));
    } finally {
      _free(id);
      _free(description);
    }
  }

  /// Number of memory-map descriptors registered via
  /// RETRO_ENVIRONMENT_SET_MEMORY_MAPS.
  int memoryDescriptorCount(Pointer<Void> session) {
    return _memoryDescriptorCount(session);
  }

  /// Memory-map descriptor at [index] as (flags, ptr, offset, start,
  /// select, disconnect, len, addrspace), or null when the index is out of
  /// range.
  ///
  /// [ptr] points into core-owned memory (NOT copied by the runtime) and is
  /// null when the runtime reports no pointer; all other fields are
  /// runtime-owned copies.
  ({
    int flags,
    Pointer<Void>? ptr,
    int offset,
    int start,
    int select,
    int disconnect,
    int len,
    String addrspace,
  })?
  memoryDescriptor(Pointer<Void> session, int index) {
    final flags = callocUint64();
    final ptr = _allocBytes(sizeOf<IntPtr>()).cast<Pointer<Void>>();
    final offset = _allocBytes(sizeOf<IntPtr>()).cast<IntPtr>();
    final start = _allocBytes(sizeOf<IntPtr>()).cast<IntPtr>();
    final select = _allocBytes(sizeOf<IntPtr>()).cast<IntPtr>();
    final disconnect = _allocBytes(sizeOf<IntPtr>()).cast<IntPtr>();
    final len = _allocBytes(sizeOf<IntPtr>()).cast<IntPtr>();
    final addrspace = _allocBytes(sizeOf<IntPtr>()).cast<Pointer<Uint8>>();
    try {
      if (!_getMemoryDescriptor(
        session,
        index,
        flags,
        ptr,
        offset,
        start,
        select,
        disconnect,
        len,
        addrspace,
      )) {
        return null;
      }
      return (
        flags: flags.value,
        ptr: ptr.value.address == 0 ? null : ptr.value,
        offset: offset.value,
        start: start.value,
        select: select.value,
        disconnect: disconnect.value,
        len: len.value,
        addrspace: _fromNativeUtf8(addrspace.value),
      );
    } finally {
      _free(flags);
      _free(ptr);
      _free(offset);
      _free(start);
      _free(select);
      _free(disconnect);
      _free(len);
      _free(addrspace);
    }
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
  Pointer<Uint64> callocUint64() => _allocBytes(8).cast();
  Pointer<Double> callocDouble() => _allocBytes(8).cast();
  void _free(Pointer ptr) => _libcFree(ptr.cast());
}

final _libcMalloc = DynamicLibrary.process()
    .lookupFunction<
      Pointer<Void> Function(IntPtr),
      Pointer<Void> Function(int)
    >('malloc');
final _libcFree = DynamicLibrary.process()
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'free',
    );

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

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
              'runtime/build/libezcore_bridge.dylib',
        ) {
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
  }

  final DynamicLibrary _lib;
  late final int Function() _abiVersion;
  late final Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>, int) _load;
  late final void Function(Pointer<Void>) _unload;
  late final bool Function(Pointer<Void>) _init;
  late final Pointer<Uint8> Function(Pointer<Void>) _coreName;
  late final Pointer<Uint8> Function(Pointer<Void>) _coreVersion;
  late final void Function(Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>,
      Pointer<Double>) _geometry;
  late final bool Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)
      _loadGame;
  late final void Function(Pointer<Void>) _runFrame;
  late final Pointer<Uint32> Function(
      Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>) _framePixels;
  late final void Function(Pointer<Void>) _cheatReset;
  late final bool Function(Pointer<Void>, int, bool, Pointer<Uint8>) _cheatSet;
  late final void Function(Pointer<Uint8>, Pointer<Uint8>) _setDirs;
  late final int Function(Pointer<Void>) _serializeSize;
  late final bool Function(Pointer<Void>, Pointer<Uint8>, int) _serialize;
  late final bool Function(Pointer<Void>, Pointer<Uint8>, int) _unserialize;

  int abiVersion() => _abiVersion();

  Pointer<Void> loadSession(String corePath) {
    final pathPtr = _toNative(corePath);
    final errPtr = calloc(1024);
    try {
      final session = _load(pathPtr, errPtr, 1024);
      if (session.address == 0) {
        throw StateError('ezcore_load failed: ${_fromNative(errPtr)}');
      }
      return session;
    } finally {
      _free(pathPtr);
      _free(errPtr);
    }
  }

  void unload(Pointer<Void> session) => _unload(session);
  bool init(Pointer<Void> session) => _init(session);
  String coreName(Pointer<Void> session) => _fromNative(_coreName(session));
  String coreVersion(Pointer<Void> session) =>
      _fromNative(_coreVersion(session));

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

  bool loadGame(Pointer<Void> session, String romPath, Uint8List data) {
    final pathPtr = _toNative(romPath);
    final dataPtr = calloc(data.length);
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
    final sysPtr = _toNative(systemDir);
    final savePtr = _toNative(saveDir);
    try {
      _setDirs(sysPtr, savePtr);
    } finally {
      _free(sysPtr);
      _free(savePtr);
    }
  }

  void cheatReset(Pointer<Void> session) => _cheatReset(session);

  bool cheatSet(
      Pointer<Void> session, int index, bool enabled, String code) {
    final codePtr = _toNative(code);
    try {
      return _cheatSet(session, index, enabled, codePtr);
    } finally {
      _free(codePtr);
    }
  }

  /// Captures a save state via the runtime. Null when the core has no
  /// content loaded or omits serialization. Bytes are opaque to the
  /// frontend — the sync layer moves them without interpreting them.
  Uint8List? saveState(Pointer<Void> session) {
    final size = _serializeSize(session);
    if (size <= 0) return null;
    final buf = calloc(size);
    try {
      if (!_serialize(session, buf, size)) return null;
      return Uint8List.fromList(buf.asTypedList(size));
    } finally {
      _free(buf);
    }
  }

  bool loadState(Pointer<Void> session, Uint8List bytes) {
    if (bytes.isEmpty) return false;
    final buf = calloc(bytes.length);
    try {
      buf.asTypedList(bytes.length).setAll(0, bytes);
      return _unserialize(session, buf, bytes.length);
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
  Pointer<Uint8> _toNative(String s) {
    final units = s.codeUnits;
    final ptr = _allocBytes(units.length + 1);
    for (var i = 0; i < units.length; i++) {
      ptr[i] = units[i] & 0xFF;
    }
    ptr[units.length] = 0;
    return ptr;
  }

  String _fromNative(Pointer<Uint8> ptr) {
    if (ptr.address == 0) return '';
    final bytes = <int>[];
    var i = 0;
    while (ptr[i] != 0 && i < 4096) {
      bytes.add(ptr[i]);
      i++;
    }
    return String.fromCharCodes(bytes);
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

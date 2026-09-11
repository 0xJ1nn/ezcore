import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Dart FFI binding over `bridge/libhuh_bridge.dylib` (ABI v1).
///
/// Resolution order for the bridge library (desktop dev only):
/// `EMU_BRIDGE_LIB` env → `bridge/build/libhuh_bridge.dylib` (repo root).
/// Zero third-party dependencies: UTF-8 is encoded/decoded by hand.
class NativeBridge {
  NativeBridge.load({String? bridgePath})
      : _lib = DynamicLibrary.open(
          bridgePath ??
              Platform.environment['EMU_BRIDGE_LIB'] ??
              'bridge/build/libhuh_bridge.dylib',
        ) {
    _abiVersion = _lib
        .lookup<NativeFunction<Int32 Function()>>('huh_abi_version')
        .asFunction<int Function()>();
    _load = _lib
        .lookup<
            NativeFunction<
                Pointer<Void> Function(
                    Pointer<Uint8>, Pointer<Uint8>, IntPtr)>>('huh_load')
        .asFunction<
            Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>, int)>();
    _unload = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('huh_unload')
        .asFunction<void Function(Pointer<Void>)>();
    _init = _lib
        .lookup<NativeFunction<Bool Function(Pointer<Void>)>>('huh_init')
        .asFunction<bool Function(Pointer<Void>)>();
    _coreName = _lib
        .lookup<NativeFunction<Pointer<Uint8> Function(Pointer<Void>)>>(
            'huh_core_name')
        .asFunction<Pointer<Uint8> Function(Pointer<Void>)>();
    _coreVersion = _lib
        .lookup<NativeFunction<Pointer<Uint8> Function(Pointer<Void>)>>(
            'huh_core_version')
        .asFunction<Pointer<Uint8> Function(Pointer<Void>)>();
    _geometry = _lib
        .lookup<
            NativeFunction<
                Void Function(Pointer<Void>, Pointer<Uint32>,
                    Pointer<Uint32>, Pointer<Double>)>>('huh_system_geometry')
        .asFunction<
            void Function(Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>,
                Pointer<Double>)>();
    _loadGame = _lib
        .lookup<
            NativeFunction<
                Bool Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
                    IntPtr)>>('huh_load_game')
        .asFunction<
            bool Function(
                Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)>();
    _runFrame = _lib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('huh_run_frame')
        .asFunction<void Function(Pointer<Void>)>();
    _framePixels = _lib
        .lookup<
            NativeFunction<
                Pointer<Uint32> Function(Pointer<Void>, Pointer<Uint32>,
                    Pointer<Uint32>)>>('huh_frame_pixels')
        .asFunction<
            Pointer<Uint32> Function(
                Pointer<Void>, Pointer<Uint32>, Pointer<Uint32>)>();
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

  int abiVersion() => _abiVersion();

  Pointer<Void> loadSession(String corePath) {
    final pathPtr = _toNative(corePath);
    final errPtr = calloc(1024);
    try {
      final session = _load(pathPtr, errPtr, 1024);
      if (session.address == 0) {
        throw StateError('huh_load failed: ${_fromNative(errPtr)}');
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

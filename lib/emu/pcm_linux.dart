import 'dart:ffi';
import 'dart:typed_data';

import 'native_mem.dart';
import 'pcm_output.dart';

/// ALSA playback sink (Linux) over dart:ffi. No plugins, no native code:
///
/// `libasound.so.2` is opened lazily and only on Linux. Distros without
/// ALSA throw a descriptive error, which the player surfaces through its
/// existing audio-unavailable path instead of staying silent.
class AlsaPcmOutput implements PcmOutput {
  AlsaPcmOutput({this._lib});
  DynamicLibrary? _lib;

  Pointer<Void> _handle = nullptr;
  bool _open = false;

  static const _streamPlayback = 0;
  static const _formatS16Le = 2;
  static const _accessRwInterleaved = 3;
  static const _epipe = -32;

  DynamicLibrary _libOf() {
    var lib = _lib;
    lib ??= _load();
    _lib = lib;
    return lib;
  }

  late final int Function(Pointer<Pointer<Void>>, Pointer<Uint8>, int, int)
      _openFn = _libOf().lookupFunction<
          Int32 Function(
              Pointer<Pointer<Void>>, Pointer<Uint8>, Int32, Int32),
          int Function(Pointer<Pointer<Void>>, Pointer<Uint8>, int, int)>(
          'snd_pcm_open');
  late final int Function(
      Pointer<Void>, int, int, int, int, int, int) _setParams =
      _libOf().lookupFunction<
          Int32 Function(Pointer<Void>, Int32, Int32, Uint32, Uint32, Int32,
              Uint32),
          int Function(
              Pointer<Void>, int, int, int, int, int, int)>(
          'snd_pcm_set_params');
  late final int Function(Pointer<Void>, Pointer<Void>, int) _writei =
      _libOf().lookupFunction<
          IntPtr Function(Pointer<Void>, Pointer<Void>, UintPtr),
          int Function(Pointer<Void>, Pointer<Void>, int)>('snd_pcm_writei');
  late final int Function(Pointer<Void>) _prepare =
      _libOf().lookupFunction<Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)>('snd_pcm_prepare');
  late final int Function(Pointer<Void>) _close =
      _libOf().lookupFunction<Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)>('snd_pcm_close');
  late final Pointer<Uint8> Function(int) _strerror =
      _libOf().lookupFunction<Pointer<Uint8> Function(Int32),
          Pointer<Uint8> Function(int)>('snd_strerror');

  DynamicLibrary _load() {
    for (final name in ['libasound.so.2', 'libasound.so']) {
      try {
        return DynamicLibrary.open(name);
      } catch (_) {}
    }
    throw StateError(
        'ALSA unavailable: libasound.so.2 not found (install libasound2)');
  }

  @override
  String get sinkName => 'ALSA (Linux)';

  @override
  Future<void> start(double sampleRate) async {
    await stop();
    if (!sampleRate.isFinite || sampleRate < 8000 || sampleRate > 192000) {
      throw ArgumentError('Invalid sample rate $sampleRate');
    }
    final rate = sampleRate.round();
    final namePtr = toNativeUtf8('default');
    final handlePtr = mallocBytes(8).cast<Pointer<Void>>();
    try {
      final rc = _openFn(handlePtr, namePtr, _streamPlayback, 0);
      if (rc != 0) {
        throw StateError('ALSA open failed: ${_err(rc)}');
      }
      _handle = handlePtr.value;
    } finally {
      freeBytes(namePtr);
      freeBytes(handlePtr);
    }
    final params = _setParams(
        _handle, _formatS16Le, _accessRwInterleaved, 2, rate, 1, 64000);
    if (params != 0) {
      final handle = _handle;
      _handle = nullptr;
      _close(handle);
      throw StateError('ALSA params failed: ${_err(params)}');
    }
    _open = true;
  }

  @override
  Future<void> write(Uint8List stereoS16) async {
    if (!_open) throw StateError('Output not started');
    if (stereoS16.length % 4 != 0) {
      throw ArgumentError('Incomplete stereo PCM');
    }
    if (stereoS16.isEmpty) return;
    var frames = stereoS16.length ~/ 4;
    var offset = 0;
    var recoveries = 0;
    while (frames > 0) {
      final chunk = frames > 2048 ? 2048 : frames;
      final ptr = mallocBytes(chunk * 4);
      try {
        ptr.asTypedList(chunk * 4).setRange(0, chunk * 4, stereoS16, offset * 4);
        final rc = _writei(_handle, ptr.cast(), chunk);
        if (rc == _epipe) {
          // Underrun: re-prepare once or twice, then drop rather than
          // stall the frame loop.
          if (++recoveries > 2) return;
          _prepare(_handle);
          continue;
        }
        if (rc < 0) throw StateError('ALSA write failed: ${_err(rc)}');
        if (rc == 0) return;
        offset += rc;
        frames -= rc;
      } finally {
        freeBytes(ptr);
      }
    }
  }

  @override
  Future<void> stop() async {
    if (_open) {
      _close(_handle);
      _handle = nullptr;
      _open = false;
    }
  }

  String _err(int code) {
    try {
      return fromNativeUtf8(_strerror(code));
    } catch (_) {
      return 'code $code';
    }
  }
}

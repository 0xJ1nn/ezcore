import 'dart:ffi';
import 'dart:typed_data';

import 'native_mem.dart';
import 'pcm_output.dart';

final class _WaveFormat extends Struct {
  @Uint16()
  external int formatTag;
  @Uint16()
  external int channels;
  @Uint32()
  external int samplesPerSec;
  @Uint32()
  external int avgBytesPerSec;
  @Uint16()
  external int blockAlign;
  @Uint16()
  external int bitsPerSample;
  @Uint16()
  external int extraSize;
}

final class _WaveHeader extends Struct {
  external Pointer<Uint8> data;
  @Uint32()
  external int bufferLength;
  @Uint32()
  external int bytesRecorded;
  @IntPtr()
  external int user;
  @Uint32()
  external int flags;
  @Uint32()
  external int loops;
}

/// Windows PCM sink over the classic waveOut API (winmm.dll, always
/// present). Four 32 KiB buffers round-robin; a chunk whose buffer is
/// still playing is dropped after a short wait instead of stalling the
/// frame loop.
class WinmmPcmOutput implements PcmOutput {
  WinmmPcmOutput({this._lib});
  DynamicLibrary? _lib;

  static const _waveMapper = 0xFFFFFFFF;
  static const _callbackNull = 0;
  static const _whdrDone = 0x00000001;
  static const _bufferBytes = 32768;
  static const _bufferCount = 4;

  int _device = 0;
  bool _open = false;
  int _cursor = 0;
  final List<Pointer<_WaveHeader>> _headers = [];
  final List<Pointer<Uint8>> _buffers = [];

  DynamicLibrary _libOf() {
    var lib = _lib;
    lib ??= _load();
    _lib = lib;
    return lib;
  }

  late final int Function(
          Pointer<IntPtr>, int, Pointer<_WaveFormat>, int, int, int) _openFn =
      _libOf().lookupFunction<
          Int32 Function(Pointer<IntPtr>, UintPtr, Pointer<_WaveFormat>,
              IntPtr, IntPtr, Int32),
          int Function(Pointer<IntPtr>, int, Pointer<_WaveFormat>, int, int,
              int)>('waveOutOpen');
  late final int Function(int, Pointer<_WaveHeader>, int) _prepare =
      _libOf().lookupFunction<
          Int32 Function(IntPtr, Pointer<_WaveHeader>, Int32),
          int Function(int, Pointer<_WaveHeader>, int)>(
          'waveOutPrepareHeader');
  late final int Function(int, Pointer<_WaveHeader>, int) _write =
      _libOf().lookupFunction<
          Int32 Function(IntPtr, Pointer<_WaveHeader>, Int32),
          int Function(int, Pointer<_WaveHeader>, int)>('waveOutWrite');
  late final int Function(int, Pointer<_WaveHeader>, int) _unprepare =
      _libOf().lookupFunction<
          Int32 Function(IntPtr, Pointer<_WaveHeader>, Int32),
          int Function(int, Pointer<_WaveHeader>, int)>(
          'waveOutUnprepareHeader');
  late final int Function(int) _close = _libOf().lookupFunction<
      Int32 Function(IntPtr),
      int Function(int)>('waveOutClose');

  DynamicLibrary _load() {
    try {
      return DynamicLibrary.open('winmm.dll');
    } catch (_) {
      throw StateError('winmm.dll unavailable');
    }
  }

  @override
  String get sinkName => 'waveOut (Windows)';

  @override
  Future<void> start(double sampleRate) async {
    await stop();
    if (!sampleRate.isFinite || sampleRate < 8000 || sampleRate > 192000) {
      throw ArgumentError('Invalid sample rate $sampleRate');
    }
    final rate = sampleRate.round();
    final devicePtr = mallocBytes(8).cast<IntPtr>();
    final fmtPtr = mallocBytes(sizeOf<_WaveFormat>()).cast<_WaveFormat>();
    try {
      final fmt = fmtPtr.ref;
      fmt.formatTag = 1; // PCM
      fmt.channels = 2;
      fmt.samplesPerSec = rate;
      fmt.avgBytesPerSec = rate * 4;
      fmt.blockAlign = 4;
      fmt.bitsPerSample = 16;
      fmt.extraSize = 0;
      final rc = _openFn(devicePtr, _waveMapper, fmtPtr, 0, 0, _callbackNull);
      if (rc != 0) throw StateError('waveOutOpen failed (code $rc)');
      _device = devicePtr.value;
    } finally {
      freeBytes(devicePtr);
      freeBytes(fmtPtr);
    }
    try {
      for (var i = 0; i < _bufferCount; i++) {
        final buf = mallocBytes(_bufferBytes);
        final hdr = mallocBytes(sizeOf<_WaveHeader>()).cast<_WaveHeader>();
        hdr.ref.data = buf;
        hdr.ref.bufferLength = _bufferBytes;
        hdr.ref.flags = _whdrDone; // free until first prepared write
        _buffers.add(buf);
        _headers.add(hdr);
      }
    } catch (_) {
      await stop();
      rethrow;
    }
    _open = true;
  }

  @override
  Future<void> write(Uint8List stereoS16) async {
    if (!_open) throw StateError('Output not started');
    if (stereoS16.length % 4 != 0) {
      throw ArgumentError('Incomplete stereo PCM');
    }
    var offset = 0;
    var remaining = stereoS16.length;
    while (remaining > 0) {
      final hdr = _headers[_cursor];
      // Wait briefly for the buffer to finish playing, then drop.
      var waited = 0;
      while ((hdr.ref.flags & _whdrDone) == 0 && waited < 40) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        waited += 2;
      }
      if ((hdr.ref.flags & _whdrDone) == 0) return;
      _unprepare(_device, hdr, sizeOf<_WaveHeader>());
      final chunk =
          remaining > _bufferBytes ? _bufferBytes : remaining;
      _buffers[_cursor]
          .asTypedList(_bufferBytes)
          .setRange(0, chunk, stereoS16, offset);
      hdr.ref.bufferLength = chunk;
      hdr.ref.flags = 0;
      var rc = _prepare(_device, hdr, sizeOf<_WaveHeader>());
      if (rc != 0) throw StateError('waveOutPrepareHeader failed ($rc)');
      rc = _write(_device, hdr, sizeOf<_WaveHeader>());
      if (rc != 0) throw StateError('waveOutWrite failed ($rc)');
      _cursor = (_cursor + 1) % _bufferCount;
      offset += chunk;
      remaining -= chunk;
    }
  }

  @override
  Future<void> stop() async {
    if (_open) {
      for (final hdr in _headers) {
        _unprepare(_device, hdr, sizeOf<_WaveHeader>());
      }
      _close(_device);
      _device = 0;
      _open = false;
    }
    for (final hdr in _headers) {
      freeBytes(hdr);
    }
    for (final buf in _buffers) {
      freeBytes(buf);
    }
    _headers.clear();
    _buffers.clear();
    _cursor = 0;
  }
}

// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

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

/// The Win32 `WAVEHDR` a driver reads and writes (mirrored at
/// runtime/external/miniaudio/miniaudio.h:27134).
///
/// The last two fields belong to the driver, not to this sink:
/// `waveOutWrite` stores a null `lpNext` and `waveOutPrepareHeader` writes
/// driver data through `reserved`. Without them the struct is 32 bytes where
/// Win32 expects 48, so the driver either writes 8 and 16 bytes past the
/// allocation or rejects the header when it validates `cbwh`.
///
/// Layout on 64-bit Windows: 48 bytes, with `lpNext` at offset 32 and
/// `reserved` at offset 40.
final class WinmmWaveHeader extends Struct {
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

  /// `LPWAVEHDR lpNext`: the next header in the driver's queue.
  external Pointer<WinmmWaveHeader> lpNext;

  /// `DWORD_PTR reserved`: driver scratch space.
  @UintPtr()
  external int reserved;
}

/// The winmm entry points this sink calls, bound lazily from `winmm.dll`.
///
/// It exists so the stop path can run on a host without winmm; the
/// production binding is [WinmmPcmOutput]'s default and is unchanged.
abstract interface class WinmmApi {
  /// `waveOutOpen` on the wave mapper. [format] points at a `WAVEFORMATEX`;
  /// [device] receives the handle.
  int open(Pointer<IntPtr> device, Pointer<Uint8> format);

  int prepare(int device, Pointer<WinmmWaveHeader> header);
  int write(int device, Pointer<WinmmWaveHeader> header);
  int unprepare(int device, Pointer<WinmmWaveHeader> header);

  /// `waveOutReset`: stops playback and returns every queued buffer.
  int reset(int device);

  /// `waveOutClose`: refuses while buffers are still queued.
  int close(int device);
}

/// winmm.dll binding. Symbols are looked up on first use, so constructing
/// the sink off Windows never opens the library.
final class _Winmm implements WinmmApi {
  _Winmm(this._libOf);

  final DynamicLibrary Function() _libOf;
  DynamicLibrary? _lib;

  static const _waveMapper = 0xFFFFFFFF;
  static const _callbackNull = 0;

  DynamicLibrary _library() {
    var lib = _lib;
    lib ??= _libOf();
    _lib = lib;
    return lib;
  }

  late final int Function(
    Pointer<IntPtr>,
    int,
    Pointer<_WaveFormat>,
    int,
    int,
    int,
  )
  _openFn = _library()
      .lookupFunction<
        Int32 Function(
          Pointer<IntPtr>,
          UintPtr,
          Pointer<_WaveFormat>,
          IntPtr,
          IntPtr,
          Int32,
        ),
        int Function(Pointer<IntPtr>, int, Pointer<_WaveFormat>, int, int, int)
      >('waveOutOpen');
  late final int Function(int, Pointer<WinmmWaveHeader>, int) _prepare =
      _library().lookupFunction<
        Int32 Function(IntPtr, Pointer<WinmmWaveHeader>, Int32),
        int Function(int, Pointer<WinmmWaveHeader>, int)
      >('waveOutPrepareHeader');
  late final int Function(int, Pointer<WinmmWaveHeader>, int) _write = _library()
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<WinmmWaveHeader>, Int32),
        int Function(int, Pointer<WinmmWaveHeader>, int)
      >('waveOutWrite');
  late final int Function(int, Pointer<WinmmWaveHeader>, int) _unprepare =
      _library().lookupFunction<
        Int32 Function(IntPtr, Pointer<WinmmWaveHeader>, Int32),
        int Function(int, Pointer<WinmmWaveHeader>, int)
      >('waveOutUnprepareHeader');
  late final int Function(int) _reset = _library().lookupFunction<
    Int32 Function(IntPtr),
    int Function(int)
  >('waveOutReset');
  late final int Function(int) _close = _library()
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'waveOutClose',
      );

  @override
  int open(Pointer<IntPtr> device, Pointer<Uint8> format) => _openFn(
    device,
    _waveMapper,
    format.cast<_WaveFormat>(),
    0,
    0,
    _callbackNull,
  );

  @override
  int prepare(int device, Pointer<WinmmWaveHeader> header) =>
      _prepare(device, header, sizeOf<WinmmWaveHeader>());

  @override
  int write(int device, Pointer<WinmmWaveHeader> header) =>
      _write(device, header, sizeOf<WinmmWaveHeader>());

  @override
  int unprepare(int device, Pointer<WinmmWaveHeader> header) =>
      _unprepare(device, header, sizeOf<WinmmWaveHeader>());

  @override
  int reset(int device) => _reset(device);

  @override
  int close(int device) => _close(device);
}

/// Windows PCM sink over the classic waveOut API (winmm.dll, always
/// present). Four 32 KiB buffers round-robin; a chunk whose buffer is still
/// playing is dropped and counted rather than stalling the frame loop.
/// [stop] resets the device first, so queued buffers cannot make close fail
/// with `WAVERR_STILLPLAYING` and leak the handle.
class WinmmPcmOutput implements PcmOutput {
  WinmmPcmOutput({DynamicLibrary? lib, WinmmApi? api})
    : _api = api ?? _Winmm(() => lib ?? _load());

  final WinmmApi _api;

  static const _whdrDone = 0x00000001;
  static const _bufferBytes = 32768;
  static const _bufferCount = 4;

  int _device = 0;
  bool _open = false;
  int _cursor = 0;
  final List<Pointer<WinmmWaveHeader>> _headers = [];
  final List<Pointer<Uint8>> _buffers = [];

  /// Chunks dropped because no buffer was free, since construction. A rising
  /// count is audio the device could not take; a caller can show it instead
  /// of the drop being invisible.
  int _droppedChunks = 0;
  int get droppedChunks => _droppedChunks;

  /// The last winmm call that failed where there was no caller to throw to.
  ///
  /// [stop] records here because pause and session close call it while
  /// already unwinding. [start] throws it rather than open a second device
  /// beside the handle a failed close left behind.
  String? lastError;

  static DynamicLibrary _load() {
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
    if (_open) {
      // The retry above could not release the previous device; opening a
      // second one beside it would leak the first.
      throw StateError(lastError ?? 'waveOut device still open');
    }
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
      final rc = _api.open(devicePtr, fmtPtr.cast<Uint8>());
      if (rc != 0) throw StateError('waveOutOpen failed (code $rc)');
      _device = devicePtr.value;
      lastError = null;
    } finally {
      freeBytes(devicePtr);
      freeBytes(fmtPtr);
    }
    try {
      for (var i = 0; i < _bufferCount; i++) {
        final buf = mallocBytes(_bufferBytes);
        final hdr = mallocBytes(sizeOf<WinmmWaveHeader>())
            .cast<WinmmWaveHeader>();
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
      // Never wait here: this runs on the frame timer, so sleeping would
      // stutter the emulator. A busy buffer means the device is behind, and
      // the chunk it would have played is dropped and counted.
      if ((hdr.ref.flags & _whdrDone) == 0) {
        _droppedChunks++;
        return;
      }
      _api.unprepare(_device, hdr);
      final chunk = remaining > _bufferBytes ? _bufferBytes : remaining;
      _buffers[_cursor]
          .asTypedList(_bufferBytes)
          .setRange(0, chunk, stereoS16, offset);
      hdr.ref.bufferLength = chunk;
      hdr.ref.flags = 0;
      var rc = _api.prepare(_device, hdr);
      if (rc != 0) throw StateError('waveOutPrepareHeader failed ($rc)');
      rc = _api.write(_device, hdr);
      if (rc != 0) throw StateError('waveOutWrite failed ($rc)');
      _cursor = (_cursor + 1) % _bufferCount;
      offset += chunk;
      remaining -= chunk;
    }
  }

  /// Releases the device and every buffer.
  ///
  /// Safe to call twice, and safe before [start]. Reset comes first because
  /// close and unprepare both return `WAVERR_STILLPLAYING` while a buffer is
  /// queued. If close still fails the device stays open and the buffers stay
  /// allocated, so the handle is not leaked; [lastError] records why, and the
  /// next [stop] or [start] retries.
  @override
  Future<void> stop() async {
    // _device alone counts too: a start whose buffer allocation failed never
    // set _open, and its device must still be closed here.
    if (_open || _device != 0) {
      // Ignore the result: reset only fails on a dead handle, and close
      // reports that case with a code this path already handles.
      _api.reset(_device);
      for (final hdr in _headers) {
        _api.unprepare(_device, hdr);
      }
      final rc = _api.close(_device);
      if (rc != 0) {
        lastError = 'waveOutClose failed ($rc)';
        return;
      }
      _device = 0;
      _open = false;
      lastError = null;
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

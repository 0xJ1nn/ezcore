// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/emu/native_mem.dart';
import 'package:ezcore/emu/pcm_windows.dart';

/// Byte offset of a pointer-sized field, read back through the allocation so
/// the assertion covers the layout the driver sees rather than the Dart name.
int _wordAt(Pointer<Uint8> base, int offset) {
  final bytes = base.asTypedList(offset + 8);
  var value = 0;
  for (var i = 7; i >= 0; i--) {
    value = (value << 8) | bytes[offset + i];
  }
  return value;
}

/// winmm stand-in: records every call and lets a test make close fail.
final class _FakeWinmm implements WinmmApi {
  _FakeWinmm({this.closeResult = 0});

  /// Returned by [close]; non-zero is `WAVERR_STILLPLAYING` and the values
  /// Win32 reports for a device that cannot be released.
  int closeResult;

  /// Called in order, so a test can assert reset comes before unprepare and
  /// close.
  final List<String> calls = [];

  @override
  int open(Pointer<IntPtr> device, Pointer<Uint8> format) {
    calls.add('open');
    device.value = 42;
    return 0;
  }

  @override
  int prepare(int device, Pointer<WinmmWaveHeader> header) {
    calls.add('prepare');
    // A device that is still playing leaves WHDR_DONE clear.
    header.ref.flags = 0;
    return 0;
  }

  @override
  int write(int device, Pointer<WinmmWaveHeader> header) {
    calls.add('write');
    return 0;
  }

  @override
  int unprepare(int device, Pointer<WinmmWaveHeader> header) {
    calls.add('unprepare');
    return 0;
  }

  @override
  int reset(int device) {
    calls.add('reset');
    return 0;
  }

  @override
  int close(int device) {
    calls.add('close');
    return closeResult;
  }
}

void main() {
  test('the wave header is the 48 bytes Win32 reads', () {
    // WAVEHDR adds LPWAVEHDR lpNext and DWORD_PTR reserved after dwLoops.
    // Without them the struct is 32 bytes and the driver writes past it.
    expect(sizeOf<WinmmWaveHeader>(), 48);
  });

  test('the header fields the driver owns sit at their Win32 offsets', () {
    final hdr = mallocBytes(sizeOf<WinmmWaveHeader>()).cast<WinmmWaveHeader>();
    addTearDown(() => freeBytes(hdr));
    final raw = hdr.cast<Uint8>();

    hdr.ref.lpNext = Pointer<WinmmWaveHeader>.fromAddress(0x1122334455667788);
    expect(_wordAt(raw, 32), 0x1122334455667788);

    hdr.ref.reserved = 0xf1e2d3c4b5a6978;
    expect(_wordAt(raw, 40), 0xf1e2d3c4b5a6978);
  });

  test('stop before start does nothing and can be repeated', () async {
    final api = _FakeWinmm();
    final sink = WinmmPcmOutput(api: api);

    await sink.stop();
    await sink.stop();

    expect(api.calls, isEmpty);
    expect(sink.lastError, isNull);
  });

  test('stop resets the device before releasing it, and runs once', () async {
    final api = _FakeWinmm();
    final sink = WinmmPcmOutput(api: api);
    await sink.start(48000);
    api.calls.clear();

    await sink.stop();

    // Reset first: unprepare and close answer WAVERR_STILLPLAYING while a
    // buffer is queued.
    expect(api.calls.first, 'reset');
    expect(api.calls.last, 'close');
    expect(api.calls.where((c) => c == 'unprepare').length, 4);

    api.calls.clear();
    await sink.stop();
    expect(api.calls, isEmpty);
  });

  test('a failed close keeps the device and retries on the next stop', () async {
    final api = _FakeWinmm(closeResult: 5); // WAVERR_STILLPLAYING
    final sink = WinmmPcmOutput(api: api);
    await sink.start(48000);
    api.calls.clear();

    await sink.stop();
    expect(api.calls, contains('close'));
    expect(sink.lastError, 'waveOutClose failed (5)');

    // The buffers and the handle are still owned, so start refuses to open a
    // second device and reports why.
    await expectLater(sink.start(48000), throwsA(isA<StateError>()));
    expect(sink.lastError, 'waveOutClose failed (5)');

    // The next stop retries the close; once it succeeds the sink is free.
    api.closeResult = 0;
    api.calls.clear();
    await sink.stop();
    expect(api.calls.first, 'reset');
    expect(api.calls.last, 'close');
    expect(sink.lastError, isNull);

    api.calls.clear();
    await sink.stop();
    expect(api.calls, isEmpty);
  });

  test('write drops a chunk instead of waiting for a busy buffer', () async {
    final api = _FakeWinmm();
    final sink = WinmmPcmOutput(api: api);
    await sink.start(48000);
    // 32 KiB of stereo 16-bit, the size of one buffer.
    final chunk = Uint8List(32768);

    // Every buffer stays busy because the fake device never reports done.
    for (var i = 0; i < 4; i++) {
      await sink.write(chunk);
    }
    expect(sink.droppedChunks, 0);

    final watch = Stopwatch()..start();
    await sink.write(chunk);
    watch.stop();

    expect(sink.droppedChunks, 1);
    expect(watch.elapsedMilliseconds, lessThan(20));
    expect(api.calls.where((c) => c == 'write').length, 4);

    await sink.stop();
  });
}

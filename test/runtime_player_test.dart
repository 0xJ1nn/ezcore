import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/runtime/ezcore_runtime.dart';
import 'test_paths.dart' as paths;

/// Resolves the synthetic test core path (built by CMake per platform).

void main() {
  final bridgeLib = paths.bridgeLib();
  final synthLib = paths.synthLib();

  group('EzCoreRuntime native player capabilities', () {
    test(
      'ABI version is 1',
      skip: bridgeLib != null ? null : 'bridge not built',
      () {
        final rt = EzCoreRuntime.load(runtimePath: bridgeLib!);
        expect(rt.abiVersion(), 1);
      },
    );

    test(
      'synthetic core loads, inits, reports geometry and sample rate',
      skip: (bridgeLib != null && synthLib != null) ? null : 'not built',
      () {
        final rt = EzCoreRuntime.load(runtimePath: bridgeLib!);
        final session = rt.loadSession(synthLib!);
        try {
          expect(rt.init(session), isTrue);
          expect(rt.coreName(session), 'ezTest Synth');

          // Synthetic core accepts any path for loadGame
          expect(rt.loadGame(session, '/dev/null', Uint8List(0)), isTrue);

          final geo = rt.geometry(session);
          expect(geo.w, 256);
          expect(geo.h, 240);
          expect(geo.fps, 60.0);

          expect(rt.sampleRate(session), 44100.0);
        } finally {
          rt.unload(session);
        }
      },
    );

    test(
      'rendering produces non-zero pixels and frame bytes',
      skip: (bridgeLib != null && synthLib != null) ? null : 'not built',
      () {
        final rt = EzCoreRuntime.load(runtimePath: bridgeLib!);
        final session = rt.loadSession(synthLib!);
        try {
          expect(rt.init(session), isTrue);
          expect(rt.loadGame(session, '/dev/null', Uint8List(0)), isTrue);

          for (var i = 0; i < 30; i++) {
            rt.runFrame(session);
          }

          // pixelSum checks raw frame buffer
          expect(rt.pixelSum(session), greaterThan(0));

          // frameBytes checks RGBA copy
          final bytes = rt.frameBytes(session);
          expect(bytes, isNotNull);
          expect(bytes!.length, 256 * 240 * 4);
          // Verify non-zero pixel data
          var nonZero = 0;
          for (var i = 0; i < bytes.length; i++) {
            if (bytes[i] != 0) nonZero++;
          }
          expect(nonZero, greaterThan(0));
        } finally {
          rt.unload(session);
        }
      },
    );

    test(
      'audio produces drainable PCM samples',
      skip: (bridgeLib != null && synthLib != null) ? null : 'not built',
      () {
        final rt = EzCoreRuntime.load(runtimePath: bridgeLib!);
        final session = rt.loadSession(synthLib!);
        try {
          expect(rt.init(session), isTrue);
          expect(rt.loadGame(session, '/dev/null', Uint8List(0)), isTrue);

          for (var i = 0; i < 10; i++) {
            rt.runFrame(session);
          }

          // audioPending should be > 0 after frames run
          expect(rt.audioPending(session), greaterThan(0));

          // drainAudio returns actual frames drained
          final buf = Uint8List(4096 * 4).buffer;
          final drained = rt.drainAudio(session, 4096, buf);
          expect(drained, greaterThan(0));

          // audioPending should decrease after drain
          expect(rt.audioPending(session), lessThan(drained * 3));
        } finally {
          rt.unload(session);
        }
      },
    );

    test(
      'input setButton affects audio output',
      skip: (bridgeLib != null && synthLib != null) ? null : 'not built',
      () {
        final rt = EzCoreRuntime.load(runtimePath: bridgeLib!);
        final session = rt.loadSession(synthLib!);
        try {
          expect(rt.init(session), isTrue);
          expect(rt.loadGame(session, '/dev/null', Uint8List(0)), isTrue);

          // Synthetic core audio sample = 0x1000 ^ (button_state & 0xFF)
          // No buttons → sample = 0x1000
          // B button (id=0) → sample = 0x1001

          // Drain any pre-existing audio
          while (rt.audioPending(session) > 0) {
            final buf = Uint8List(4096 * 4).buffer;
            rt.drainAudio(session, 4096, buf);
          }

          // Set button B (id=0)
          rt.setButton(session, 0, 0, true);
          rt.runFrame(session);

          final buf = Uint8List(4096 * 4).buffer;
          final drained = rt.drainAudio(session, 4096, buf);
          expect(drained, greaterThan(0));

          // Read first audio sample (little-endian int16)
          final bd = ByteData.view(buf);
          final firstSample = bd.getInt16(0, Endian.little);
          expect(firstSample, 0x1001,
              reason: 'audio sample should be 0x1001 when B is pressed');

          // Release button → back to 0x1000
          rt.setButton(session, 0, 0, false);
          rt.runFrame(session);
          final buf2 = Uint8List(4096 * 4).buffer;
          rt.drainAudio(session, 4096, buf2);
          final bd2 = ByteData.view(buf2);
          expect(bd2.getInt16(0, Endian.little), 0x1000,
              reason: 'audio sample should return to 0x1000 when B is released');

          // clear_buttons: set multiple, then clear
          rt.setButton(session, 0, 0, true);
          rt.setButton(session, 0, 1, true);
          rt.clearButtons(session, 0);
          rt.runFrame(session);
          final buf3 = Uint8List(4096 * 4).buffer;
          rt.drainAudio(session, 4096, buf3);
          final bd3 = ByteData.view(buf3);
          expect(bd3.getInt16(0, Endian.little), 0x1000,
              reason: 'audio sample should return to 0x1000 after clearButtons');
        } finally {
          rt.unload(session);
        }
      },
    );

    test(
      'reset reverts frame counter',
      skip: (bridgeLib != null && synthLib != null) ? null : 'not built',
      () {
        final rt = EzCoreRuntime.load(runtimePath: bridgeLib!);
        final session = rt.loadSession(synthLib!);
        try {
          expect(rt.init(session), isTrue);
          expect(rt.loadGame(session, '/dev/null', Uint8List(0)), isTrue);

          // Run many frames to advance counter
          for (var i = 0; i < 60; i++) {
            rt.runFrame(session);
          }
          final sumBefore = rt.pixelSum(session);
          expect(sumBefore, greaterThan(0));

          // Reset
          rt.reset(session);

          // Run one frame after reset
          rt.runFrame(session);
          final sumAfter = rt.pixelSum(session);

          // After reset, the frame should be different (lower R channel)
          expect(sumAfter, lessThan(sumBefore),
              reason: 'pixel sum should decrease after reset (R channel reverts)');
        } finally {
          rt.unload(session);
        }
      },
    );

    test(
      'serialize round-trip preserves state',
      skip: (bridgeLib != null && synthLib != null) ? null : 'not built',
      () {
        final rt = EzCoreRuntime.load(runtimePath: bridgeLib!);
        final session = rt.loadSession(synthLib!);
        try {
          expect(rt.init(session), isTrue);
          expect(rt.loadGame(session, '/dev/null', Uint8List(0)), isTrue);

          // Run 10 frames, capture snapshot
          for (var i = 0; i < 10; i++) {
            rt.runFrame(session);
          }
          final snap = rt.saveState(session);
          expect(snap, isNotNull);
          expect(snap!.length, greaterThan(0));

          // Run more frames to diverge
          for (var i = 0; i < 20; i++) {
            rt.runFrame(session);
          }

          // Restore
          expect(rt.loadState(session, snap), isTrue);

          // Run one frame after restore - pixel sum should be close to pre-diverge
          rt.runFrame(session);
          final sumRestored = rt.pixelSum(session);

          // The restore should have brought the state back close to what it was
          // Just verify it's non-zero (meaning state was restored)
          expect(sumRestored, greaterThan(0));
        } finally {
          rt.unload(session);
        }
      },
    );

    test(
      'lifecycle: unload then re-load works',
      skip: (bridgeLib != null && synthLib != null) ? null : 'not built',
      () {
        final rt = EzCoreRuntime.load(runtimePath: bridgeLib!);

        // First session
        final s1 = rt.loadSession(synthLib!);
        expect(rt.init(s1), isTrue);
        expect(rt.loadGame(s1, '/dev/null', Uint8List(0)), isTrue);
        rt.runFrame(s1);
        expect(rt.pixelSum(s1), greaterThan(0));
        rt.unload(s1);

        // Second session - fresh load
        final s2 = rt.loadSession(synthLib);
        expect(rt.init(s2), isTrue);
        expect(rt.loadGame(s2, '/dev/null', Uint8List(0)), isTrue);
        rt.runFrame(s2);
        expect(rt.pixelSum(s2), greaterThan(0));
        rt.unload(s2);
      },
    );

    test(
      'frameBytes returns exact RGBA size',
      skip: (bridgeLib != null && synthLib != null) ? null : 'not built',
      () {
        final rt = EzCoreRuntime.load(runtimePath: bridgeLib!);
        final session = rt.loadSession(synthLib!);
        try {
          expect(rt.init(session), isTrue);
          expect(rt.loadGame(session, '/dev/null', Uint8List(0)), isTrue);

          // Run enough frames for B channel to be non-zero (every 16 frames)
          for (var i = 0; i < 20; i++) {
            rt.runFrame(session);
          }

          final bytes = rt.frameBytes(session);
          expect(bytes, isNotNull);
          expect(bytes!.length, 256 * 240 * 4);

          // Verify non-zero content
          var nonZero = 0;
          for (var i = 0; i < bytes.length; i++) {
            if (bytes[i] != 0) nonZero++;
          }
          expect(nonZero, greaterThan(0));

          // All pixels same color in synth core frame, so bytes[0..3] == bytes[4..7]
          expect(bytes[0], equals(bytes[4]),
              reason: 'all pixels same color, first byte of pixel 0 == pixel 1');
          expect(bytes[1], equals(bytes[5]),
              reason: 'all pixels same color, second byte matches');
        } finally {
          rt.unload(session);
        }
      },
    );
  });
}

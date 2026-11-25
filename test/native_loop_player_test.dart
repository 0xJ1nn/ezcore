// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

// The native run thread owns emulation. The player only starts and stops it,
// writes input into its atomics, and reads a slow statistics stream for the
// display. These tests use fakes so they run without a built runtime.

import 'dart:typed_data';

import 'package:ezcore/emu/core_session_backend.dart';
import 'package:ezcore/emu/native_loop_session.dart';
import 'package:ezcore/emu/pcm_output.dart';
import 'package:ezcore/emu/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const Map<String, String?> _runtimeRef = {'kind': 'path', 'path': 'runtime'};

class _SilentAudio implements PcmOutput {
  @override
  String get sinkName => 'silent';
  @override
  Future<void> start(double rate) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> write(Uint8List pcm) async {}
}

class _FakeBackend implements CoreSessionBackend {
  @override
  Future<bool> attachVideo(int window, int width, int height) async => false;
  int frames = 0;
  int buttons = 0;
  bool paused = false;

  @override
  Future<Map<String, dynamic>> open({
    required Map<String, String?> runtimeRef,
    required String corePath,
    required String contentPath,
    required String systemDir,
    required String saveDir,
    Map<String, String> coreOptions = const {},
  }) async {
    return {
      'name': 'fake',
      'width': 2,
      'height': 2,
      'fps': 60.0,
      'sampleRate': 48000.0,
      'canSave': true,
      'sessionAddress': 4242,
    };
  }

  @override
  Future<Map<String, dynamic>?> frame({int count = 1}) async {
    frames++;
    return {
      'width': 2,
      'height': 2,
      'rgba': Uint8List.fromList(List<int>.filled(16, 255)),
      'pcm': Uint8List(0),
    };
  }

  @override
  Future<void> pause(bool value) async => paused = value;
  @override
  Future<void> button(int id, bool pressed, {int port = 0}) async => buttons++;
  @override
  Future<void> analog(int port, int stick, int axis, int value) async {}
  @override
  Future<void> mouseMove(int dx, int dy) async {}
  @override
  Future<void> mouseButton(int id, bool pressed) async {}
  @override
  Future<void> key(
    int keycode,
    bool pressed, {
    int character = 0,
    int modifiers = 0,
  }) async {}
  @override
  Future<void> pointer(int x, int y, bool pressed) async {}
  @override
  Future<Uint8List> save() async => Uint8List(0);
  @override
  Future<void> restore(Uint8List bytes) async {}
  @override
  Future<List<int>> applyCheats(List<List<Object>> cheats) async => const [];
  @override
  Future<void> reset() async {}
  @override
  Future<List<Map<String, String>>> coreOptions() async => const [];
  @override
  Future<bool> setCoreOption(String key, String value) async => true;
  @override
  Future<void> close() async {}
}

class _FakeBinding implements NativeLoopBinding {
  bool symbols = true;
  bool video = true;
  int starts = 0;
  int stops = 0;
  int _frames = 0;
  final buttonsWritten = <String>[];
  final pauseCalls = <bool>[];
  final speedCalls = <int>[];

  @override
  bool get symbolsPresent => symbols;
  @override
  bool get videoBridgePresent => video;
  @override
  int start(int sessionAddress, {int fps = 60}) {
    starts++;
    return 99;
  }

  @override
  void stop(int loop) => stops++;
  @override
  void setButton(int loop, int port, int id, bool pressed) =>
      buttonsWritten.add('$port:$id:$pressed');
  @override
  void clearButtons(int loop, int port) => buttonsWritten.add('$port:clear');
  @override
  void setAnalog(int loop, int port, int stick, int axis, int value) =>
      buttonsWritten.add('$port:$stick:$axis:$value');
  @override
  NativeLoopStats stats(int loop) => NativeLoopStats(
        framesRun: ++_frames,
        droppedFrames: 0,
        audioUnderruns: 0,
        frameMeanMs: 8.0,
        frameP95Ms: 9.0,
      );
  @override
  bool pause(int loop, bool paused) {
    pauseCalls.add(paused);
    return true;
  }

  @override
  bool fastForward(int loop, int factor) {
    speedCalls.add(factor);
    return true;
  }
}

Future<void> _pump(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

PlayerController _player({
  required _FakeBackend backend,
  required NativeLoopProbe probe,
  Map<String, dynamic> settings = const {},
}) {
  final player = PlayerController(
    audio: _SilentAudio(),
    nativeLoopProbe: probe,
    settings: settings,
  );
  player.useBackend(backend);
  return player;
}

Future<void> _open(PlayerController player) => player.open(
      runtimeRef: _runtimeRef,
      corePath: 'core',
      contentPath: 'content',
      systemDir: '.',
      saveDir: '.',
    );

void main() {
  test('the loop session reads input without waiting for a frame', () async {
    final binding = _FakeBinding();
    final session = NativeLoopSession(
      binding: binding,
      sessionAddress: 4242,
      statsInterval: const Duration(milliseconds: 20),
    );
    expect(session.supported, isTrue);
    session.start();
    expect(binding.starts, 1);
    session.setButton(1, 3, true);
    session.setAnalog(0, 1, 0, 12000);
    expect(binding.buttonsWritten, ['1:3:true', '0:1:0:12000']);

    final first = await session.statsStream.first.timeout(
      const Duration(seconds: 1),
    );
    expect(first.framesRun, 1);
    expect(session.lastStats?.framesRun, 1);
    session.stop();
    expect(binding.stops, 1);
    session.setButton(0, 0, true);
    expect(binding.buttonsWritten, hasLength(2));
  });

  test('the player runs on the loop and stops the per-frame timer', () async {
    final backend = _FakeBackend();
    final binding = _FakeBinding();
    NativeLoopSession? session;
    final player = _player(
      backend: backend,
      probe: ({required runtimeRef, required sessionAddress, required fps}) {
        session = NativeLoopSession(
          binding: binding,
          sessionAddress: sessionAddress,
          fps: fps,
          statsInterval: const Duration(milliseconds: 20),
        );
        return session;
      },
    );
    try {
      await _open(player);
      await _pump(80);
      expect(player.usingNativeLoop, isTrue);
      expect(binding.starts, 1);
      expect(backend.frames, 0);

      await player.button(3, true, port: 1);
      expect(binding.buttonsWritten, ['1:3:true']);
      expect(backend.buttons, 0);

      await player.setPaused(true);
      expect(binding.pauseCalls, [true]);
      expect(backend.paused, isFalse);
      await player.setPaused(false);
      expect(binding.pauseCalls, [true, false]);

      player.fastForward = true;
      expect(binding.speedCalls, [4]);

      final stats = await player.loopStatsStream.first.timeout(
        const Duration(seconds: 1),
      );
      expect(stats.framesRun, greaterThan(0));
      expect(player.loopStats, isNotNull);
    } finally {
      await player.close();
      player.dispose();
    }
    expect(binding.stops, 1);
  });

  test('a hidden setting keeps the original timer path', () async {
    final backend = _FakeBackend();
    var probed = false;
    final player = _player(
      backend: backend,
      settings: const {kLegacyFrameLoopSetting: 'timer'},
      probe: ({required runtimeRef, required sessionAddress, required fps}) {
        probed = true;
        return null;
      },
    );
    try {
      await _open(player);
      await _pump(80);
      expect(probed, isFalse);
      expect(player.usingNativeLoop, isFalse);
      expect(backend.frames, greaterThan(0));
    } finally {
      await player.close();
      player.dispose();
    }
  });

  for (final target in const [
    'ios',
    'android',
    'macos',
    'linux',
    'windows',
  ]) {
    test('$target stays on the timer path without a video bridge', () async {
      final binding = _FakeBinding()..video = false;
      expect(nativeLoopReady(binding, target), isFalse);

      final backend = _FakeBackend();
      final player = _player(
        backend: backend,
        probe: ({required runtimeRef, required sessionAddress, required fps}) =>
            nativeLoopReady(binding, target)
                ? NativeLoopSession(
                    binding: binding,
                    sessionAddress: sessionAddress,
                  )
                : null,
      );
      try {
        await _open(player);
        await _pump(80);
        expect(binding.starts, 0);
        expect(player.usingNativeLoop, isFalse);
        expect(backend.frames, greaterThan(0));
      } finally {
        await player.close();
        player.dispose();
      }
    });
  }

  test('symbols missing in the loaded runtime keep the timer path', () async {
    final binding = _FakeBinding()..symbols = false;
    for (final target in const [
      'ios',
      'android',
      'macos',
      'linux',
      'windows',
    ]) {
      expect(nativeLoopReady(binding, target), isFalse);
    }
  });
}

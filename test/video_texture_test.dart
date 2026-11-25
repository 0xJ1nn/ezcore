// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/emu/core_session_backend.dart';
import 'package:ezcore/emu/pcm_output.dart';
import 'package:ezcore/emu/player_controller.dart';
import 'package:ezcore/emu/video_texture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ezcore/video');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'create':
          return {
            'textureId': 7,
            'window': 123456,
            'width': call.arguments['width'],
            'height': call.arguments['height'],
          };
        case 'frameReady':
          return {'frames': 1};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('creates a surface texture and exposes the native window', () async {
    final video = VideoTextureController(enabled: true);
    await video.create(240, 160);
    expect(video.textureId, 7);
    expect(video.window, 123456);
    expect(calls.single.method, 'create');
    expect(calls.single.arguments['width'], 240);
    await video.release();
    expect(calls.last.method, 'release');
  });

  test('tells the platform to present each new frame', () async {
    final video = VideoTextureController(enabled: true);
    await video.create(240, 160);
    await video.markFrame();
    await video.markFrame();
    expect(video.framesPresented, 2);
    expect(calls.where((c) => c.method == 'frameReady').length, 2);
    expect(video.view(), isA<Texture>());
    await video.release();
  });

  test('player presents into the texture and records frame times', () async {
    final video = VideoTextureController(enabled: true);
    final backend = _PresentingBackend();
    final player = PlayerController(
      audio: _QuietAudio(),
      video: video,
    )..useBackend(backend);
    try {
      await player.open(
        runtimeRef: const {'kind': 'process'},
        corePath: 'synthetic',
        contentPath: 'synthetic',
        systemDir: '',
        saveDir: '',
      );
      expect(player.usingTexture, isTrue);
      expect(backend.attached, isTrue);
      for (var i = 0; i < 20 && video.framesPresented < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(video.framesPresented, greaterThanOrEqualTo(10));
      expect(player.frameStats.count, greaterThanOrEqualTo(10));
      expect(player.frame, isNotNull); // the layout stand-in
    } finally {
      await player.close();
      player.dispose();
    }
  });

  test('disabled texture never touches the channel', () async {
    final video = VideoTextureController(enabled: false);
    await video.create(240, 160);
    await video.markFrame();
    expect(video.textureId, isNull);
    expect(video.view(), isNull);
    expect(calls, isEmpty);
  });

  test('falls back to decoded frames when the surface cannot attach', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'create') {
        return {'textureId': 7, 'window': 123456};
      }
      return null;
    });
    final video = VideoTextureController(enabled: true);
    final backend = _PresentingBackend()..refuseAttach = true;
    final player = PlayerController(
      audio: _QuietAudio(),
      video: video,
    )..useBackend(backend);
    try {
      await player.open(
        runtimeRef: const {'kind': 'process'},
        corePath: 'synthetic',
        contentPath: 'synthetic',
        systemDir: '',
        saveDir: '',
      );
      expect(player.usingTexture, isFalse);
      expect(video.textureId, isNull);
    } finally {
      await player.close();
      player.dispose();
    }
  });

  test('frame stats report count, mean and p99', () {
    final stats = FrameStats();
    for (var i = 0; i < 100; i++) {
      stats.sample(Duration(microseconds: 1000 + i * 100));
    }
    expect(stats.count, 100);
    expect(stats.meanMs, closeTo(5.95, 0.001));
    expect(stats.p99Ms, closeTo(10.8, 0.001));
    expect(stats.toString(), contains('p99='));
  });
}

class _QuietAudio implements PcmOutput {
  @override
  String get sinkName => 'test sink';
  @override
  Future<void> start(double rate) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> write(Uint8List pcm) async {}
}

class _PresentingBackend implements CoreSessionBackend {
  bool attached = false;
  bool refuseAttach = false;

  @override
  Future<Map<String, dynamic>> open({
    required Map<String, String?> runtimeRef,
    required String corePath,
    required String contentPath,
    required String systemDir,
    required String saveDir,
    Map<String, String> coreOptions = const {},
  }) async => {
    'name': 'synthetic',
    'width': 240,
    'height': 160,
    'fps': 60.0,
    'sampleRate': 44100.0,
    'canSave': false,
  };

  @override
  Future<Map<String, dynamic>?> frame({int count = 1}) async => {
    'width': 240,
    'height': 160,
    'rgba': null,
    'pcm': Uint8List(0),
    'presented': !refuseAttach,
  };

  @override
  Future<bool> attachVideo(int window, int width, int height) async {
    attached = true;
    return !refuseAttach;
  }

  @override
  Future<void> pause(bool value) async {}
  @override
  Future<void> button(int id, bool pressed, {int port = 0}) async {}
  @override
  Future<void> analog(int port, int stick, int axis, int value) async {}
  @override
  Future<void> mouseMove(int dx, int dy) async {}
  @override
  Future<void> mouseButton(int id, bool pressed) async {}
  @override
  Future<void> key(int keycode, bool pressed,
      {int character = 0, int modifiers = 0}) async {}
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
  Future<bool> setCoreOption(String key, String value) async => false;
  @override
  Future<void> close() async {}
}

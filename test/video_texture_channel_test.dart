// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/emu/video_texture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(videoChannelName);
  final calls = <MethodCall>[];
  int? attachedAddress;
  bool publishResult = true;

  setUp(() {
    calls.clear();
    attachedAddress = null;
    publishResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'attach':
          attachedAddress = call.arguments as int;
          return true;
        case 'create':
          return 42;
        case 'frameReady':
          return publishResult;
        case 'stats':
          return <String, int>{
            'framesPublished': 7,
            'framesDropped': 1,
            'width': 256,
            'height': 240,
          };
        default:
          return null;
      }
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  test('open attaches the session before creating the texture', () async {
    final texture = DesktopVideoTexture(isDesktop: true);
    expect(await texture.open(0x1234), 42);
    expect(texture.textureId, 42);
    expect(attachedAddress, 0x1234);
    expect(calls.map((c) => c.method), ['attach', 'create']);
  });

  test('frameReady reports the measured publish result', () async {
    final texture = DesktopVideoTexture(isDesktop: true);
    await texture.open(0x1234);
    calls.clear();
    publishResult = false;
    expect(await texture.frameReady(), isFalse);
    expect(calls.map((c) => c.method), ['frameReady']);
    publishResult = true;
    expect(await texture.frameReady(), isTrue);
  });

  test('stats reads the native counters as integers', () async {
    final texture = DesktopVideoTexture(isDesktop: true);
    await texture.open(1);
    final stats = await texture.stats();
    expect(stats, {
      'framesPublished': 7,
      'framesDropped': 1,
      'width': 256,
      'height': 240,
    });
  });

  test('a missing native channel leaves the player on decoded frames',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final texture = DesktopVideoTexture(isDesktop: true);
    expect(await texture.open(0x1234), isNull);
    expect(texture.textureId, isNull);
    expect(await texture.frameReady(), isFalse);
  });

  test('non-desktop targets never call the desktop channel', () async {
    final texture = DesktopVideoTexture(isDesktop: false);
    expect(await texture.open(0x1234), isNull);
    expect(calls, isEmpty);
  });
}

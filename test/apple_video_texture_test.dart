// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

// The Apple video bridge is Swift and can only be compiled on a Mac. These
// checks run on every host and hold the contract that the two runners and the
// shared source must agree on: one IOSurface-backed FlutterTexture source,
// compiled into both targets, installed on the same method channel by both
// platform entry points. They do not claim a build or a rendered frame.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Directory _packageRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('no pubspec.yaml above ${Directory.current.path}');
    }
    dir = parent;
  }
}

void main() {
  final root = _packageRoot().path;
  final shared = File('$root/apple/EzcoreVideoTexture.swift');
  final iosProject = File('$root/ios/Runner.xcodeproj/project.pbxproj');
  final macosProject = File('$root/macos/Runner.xcodeproj/project.pbxproj');
  final iosEntry = File('$root/ios/Runner/AppDelegate.swift');
  final macosEntry = File('$root/macos/Runner/MainFlutterWindow.swift');

  group('Apple video texture bridge', () {
    test('one shared Swift source presents an IOSurface pixel-buffer pool',
        () {
      expect(shared.existsSync(), isTrue,
          reason: 'the Swift bridge must be a single shared source');
      final source = shared.readAsStringSync();
      expect(source, contains('FlutterTexture'));
      expect(source, contains('copyPixelBuffer'));
      expect(source, contains('kCVPixelBufferIOSurfacePropertiesKey'));
      expect(source, contains('kCVPixelFormatType_32BGRA'));
      expect(source, contains('CVPixelBufferCreate'));
      expect(source, contains('textureFrameAvailable'));
      expect(source, contains('ezcore/video'));
      for (final method in <String>['create', 'frame', 'release']) {
        expect(source, contains('case "$method":'),
            reason: 'the video channel must handle $method');
      }
      expect(source, contains('withLockedBuffer'),
          reason: 'the runtime must be able to write a locked buffer directly');
    });

    test('both Xcode targets compile the shared Swift source', () {
      for (final project in <File>[iosProject, macosProject]) {
        expect(project.existsSync(), isTrue);
        final pbx = project.readAsStringSync();
        expect(pbx, contains('EzcoreVideoTexture.swift'),
            reason: '${project.path} must reference the shared source');
        expect(pbx,
            contains('EzcoreVideoTexture.swift in Sources'),
            reason: '${project.path} must compile the shared source');
        expect(pbx, contains('../apple/EzcoreVideoTexture.swift'),
            reason: '${project.path} must point at the one shared file');
      }
    });

    test('both platform entry points install the video channel', () {
      for (final entry in <File>[iosEntry, macosEntry]) {
        expect(entry.existsSync(), isTrue);
        final source = entry.readAsStringSync();
        expect(source, contains('EzcoreVideoTextureBridge('),
            reason: '${entry.path} must construct the shared bridge');
        expect(source, contains('registerTexture'),
            reason: '${entry.path} must register the texture');
      }
    });
  });
}

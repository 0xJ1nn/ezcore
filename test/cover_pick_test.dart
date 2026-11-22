// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ezcore/services/cover_art.dart';
import 'package:ezcore/services/game_art.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  // Just enough container framing to pass isImageBytes: a JPEG SOI and EOI.
  final onePixelJpeg = Uint8List.fromList(<int>[
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
    0x49, 0x46, 0x00, 0x01, 0xFF, 0xD9,
  ]);

  late Directory data;

  setUp(() {
    data = Directory.systemTemp.createTempSync('ezcore-cover-pick-');
    PlatformLocalDataDirProvider.pinStartupDir(data.path);
  });

  tearDown(() {
    data.deleteSync(recursive: true);
  });

  File source(String name, List<int> bytes) {
    final file = File('${data.path}/$name');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return file;
  }

  GameArtRequest request(String id) => GameArtRequest(
    id: id,
    title: 'Pocket Rally',
    system: 'nes',
  );

  test('a chosen PNG is pinned where the resolver finds it', () async {
    final chosen = source('chosen.png', onePixelPng);

    final written = await setCoverFromFile('cover-pick-a', chosen.path);

    expect(written, isNotNull);
    expect(written!.path, '${data.path}/art/cover-pick-a.png');
    expect(written.readAsBytesSync(), onePixelPng);
    expect(
      GameArtResolver(localDataPath: data.path).resolve(request('cover-pick-a'))?.path,
      written.path,
    );
  });

  test('a text file or a missing source is refused without writing', () async {
    final text = source('notes.txt', utf8.encode('this is not an image'));

    expect(await setCoverFromFile('cover-pick-b', text.path), isNull);
    expect(File('${data.path}/art/cover-pick-b.png').existsSync(), isFalse);
    expect(
      await setCoverFromFile('cover-pick-b', '${data.path}/missing.png'),
      isNull,
      reason: 'an unreadable source is refused, not thrown',
    );
  });

  test('resetCover drops one cover and leaves the other games alone', () async {
    final chosen = source('chosen.png', onePixelPng);
    await setCoverFromFile('cover-pick-c', chosen.path);
    await setCoverFromFile('cover-pick-other', chosen.path);
    final resolver = GameArtResolver(localDataPath: data.path);
    expect(resolver.resolve(request('cover-pick-c')), isNotNull);
    expect(resolver.resolve(request('cover-pick-other')), isNotNull);

    await resetCover('cover-pick-c');

    expect(File('${data.path}/art/cover-pick-c.png').existsSync(), isFalse);
    expect(resolver.resolve(request('cover-pick-c')), isNull);
    expect(resolver.resolve(request('cover-pick-other')), isNotNull);
  });

  test('a second cover replaces the first with no stale file behind', () async {
    final first = source('first.jpg', onePixelJpeg);
    final second = source('second.png', onePixelPng);

    final jpg = await setCoverFromFile('cover-pick-d', first.path);
    final png = await setCoverFromFile('cover-pick-d', second.path);

    expect(jpg!.path, endsWith('.jpg'));
    expect(png!.path, endsWith('.png'));
    expect(File('${data.path}/art/cover-pick-d.jpg').existsSync(), isFalse);
    expect(png.readAsBytesSync(), onePixelPng);
    expect(
      GameArtResolver(localDataPath: data.path).resolve(request('cover-pick-d'))?.path,
      png.path,
    );
  });
}

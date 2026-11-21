import 'dart:convert';
import 'dart:io';

import 'package:ezcore/models/game_entry.dart' show GameEntry;
import 'package:ezcore/screens/settings_screen.dart'
    show artLookupNoWorkMessage;
import 'package:ezcore/services/cover_art.dart' show invalidateCoverFile;
import 'package:ezcore/services/game_art.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:ezcore/state/app_state.dart' show contentPresentFor;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  late Directory data;

  setUp(() {
    data = Directory.systemTemp.createTempSync('ezcore-art-identity-');
    PlatformLocalDataDirProvider.pinStartupDir(data.path);
  });

  tearDown(() {
    data.deleteSync(recursive: true);
  });

  File writeImage(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(onePixelPng);
    return file;
  }

  test('cached art is keyed by game id as well as title and system', () {
    const first = GameArtRequest(
      id: 'rom-a',
      title: 'Shared Title (USA).zip',
      system: 'nes',
    );
    const second = GameArtRequest(
      id: 'rom-b',
      title: 'Shared Title (USA).zip',
      system: 'nes',
    );

    expect(
      artCacheKeyFor(first.id, first.system, first.title),
      isNot(artCacheKeyFor(second.id, second.system, second.title)),
    );
    expect(
      artCacheKeyFor(first.id, first.system, first.title),
      artCacheKeyFor(first.id, first.system, first.title),
    );
  });

  test('game A art is not shown for game B with the same title and system', () {
    const first = GameArtRequest(
      id: 'shared-a',
      title: 'Shared Title',
      system: 'nes',
    );
    const second = GameArtRequest(
      id: 'shared-b',
      title: 'Shared Title',
      system: 'nes',
    );
    invalidateCoverFile(first.id);
    invalidateCoverFile(second.id);
    final resolver = GameArtResolver(
      localDataPath: data.path,
      settings: const GameArtSettings(artLookup: true),
    );
    writeImage('${data.path}/art/${first.id}.png');
    writeImage(resolver.cachePath(first));

    expect(resolver.resolve(first), isNotNull);
    expect(resolver.resolve(second), isNull);
  });

  test('content that is gone keeps the procedural cover', () {
    const request = GameArtRequest(
      id: 'missing-content',
      title: 'Shared Title',
      system: 'nes',
      contentPresent: false,
    );
    invalidateCoverFile(request.id);
    writeImage('${data.path}/art/${request.id}.png');
    final resolver = GameArtResolver(
      localDataPath: data.path,
      settings: const GameArtSettings(artLookup: true),
    );
    writeImage(resolver.cachePath(request));

    expect(resolver.resolve(request), isNull);
  });

  test('an empty library is not told every game already has art', () {
    expect(artLookupNoWorkMessage(0), isNot('Every game already has art'));
    expect(artLookupNoWorkMessage(2), 'Every game already has art');
  });

  // e) File gone, registered folder still on disk: the rescan prunes it.
  test('contentPresentFor is false for a pruned entry', () {
    final root = Directory('${data.path}/roms-live')
      ..createSync(recursive: true);
    final game = GameEntry(
      id: 'pruned',
      title: 'Deleted ROM',
      system: 'nes',
      filePath: '${root.path}/deleted.zip',
      extension: 'zip',
    );
    expect(File(game.filePath).existsSync(), isFalse);
    expect(contentPresentFor(game, [root.path]), isFalse);
  });

  // f) A file on disk is present regardless of the folder list.
  test('contentPresentFor is true when the file exists', () {
    final root = Directory('${data.path}/roms-here')
      ..createSync(recursive: true);
    final file = File('${root.path}/here.zip')..writeAsStringSync('rom bytes');
    final game = GameEntry(
      id: 'here',
      title: 'Present ROM',
      system: 'nes',
      filePath: file.path,
      extension: 'zip',
    );
    expect(contentPresentFor(game, [root.path]), isTrue);
  });

  // g) File gone, folder not registered: an unplugged drive is kept.
  test('contentPresentFor is true for an unregistered (unplugged) folder', () {
    final root = Directory('${data.path}/roms-unplugged')
      ..createSync(recursive: true);
    final game = GameEntry(
      id: 'unplugged',
      title: 'Unplugged ROM',
      system: 'nes',
      filePath: '${root.path}/away.zip',
      extension: 'zip',
    );
    expect(File(game.filePath).existsSync(), isFalse);
    expect(
      contentPresentFor(game, ['${data.path}/roms-somewhere-else']),
      isTrue,
    );
  });
}

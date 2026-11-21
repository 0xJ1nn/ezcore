import 'dart:convert';
import 'dart:io';

import 'package:ezcore/services/art_fetcher.dart';
import 'package:ezcore/services/cover_art.dart';
import 'package:ezcore/services/game_art.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  Directory data = Directory.systemTemp;
  Directory media = Directory.systemTemp;

  setUp(() {
    data = Directory.systemTemp.createTempSync('ezcore-game-art-data-');
    media = Directory.systemTemp.createTempSync('ezcore-game-art-media-');
    PlatformLocalDataDirProvider.pinStartupDir(data.path);
  });

  tearDown(() {
    data.deleteSync(recursive: true);
    media.deleteSync(recursive: true);
  });

  File writeImage(String path, [List<int>? bytes]) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes ?? onePixelPng);
    return file;
  }

  const request = GameArtRequest(
    id: 'imp-art-test',
    title: 'Lanterns of Vell (USA).zip',
    system: 'nes',
  );

  test('normaliseArtTitle folds case, separators, region tags and extensions', () {
    expect(normaliseArtTitle('Lanterns of Vell (USA).zip'), 'lanterns of vell');
    expect(normaliseArtTitle('Lanterns_of_Vell-USA.png'), 'lanterns of vell usa');
    expect(normaliseArtTitle('Lanterns: of Vell [Europe]'), 'lanterns of vell');
    expect(normaliseArtTitle('  Pocket_Rally  '), 'pocket rally');
  });

  test('sha1Hex matches a known vector and cache keys hide the title', () {
    expect(sha1Hex('abc'), 'a9993e364706816aba3e25717850c26c9cd0d89d');
    final key = artCacheKey(request);
    expect(key, matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(key.toLowerCase().contains('lanterns'), isFalse);
    expect(key, artCacheKeyFor(request.id, 'NES', 'Lanterns of Vell (USA).zip'));
  });

  test('precedence: pinned screenshot wins over media folder and cache', () {
    invalidateCoverFile(request.id);
    final pinned = writeImage('${data.path}/art/${request.id}.png');
    writeImage('${media.path}/NES/Lanterns_of_Vell(USA).png');
    final cache = writeImage(
      '${data.path}/art-cache/${artCacheKey(request)}.img',
    );
    final resolver = GameArtResolver(
      localDataPath: data.path,
      settings: GameArtSettings(artFolder: media.path, artLookup: true),
    );

    expect(resolver.resolve(request)?.path, pinned.path);
    expect(resolver.resolve(request)?.path, isNot(cache.path));
  });

  test('precedence: media folder wins over the opt-in cache', () {
    invalidateCoverFile(request.id);
    final userArt = writeImage('${media.path}/NES/Lanterns_of_Vell(USA).png');
    writeImage('${data.path}/art-cache/${artCacheKey(request)}.img');
    final resolver = GameArtResolver(
      localDataPath: data.path,
      settings: GameArtSettings(artFolder: media.path, artLookup: true),
    );

    expect(resolver.resolve(request)?.path, userArt.path);
  });

  test('precedence: cache is used only when nothing local qualifies', () {
    invalidateCoverFile(request.id);
    final cache = writeImage(
      '${data.path}/art-cache/${artCacheKey(request)}.img',
    );
    final resolver = GameArtResolver(
      localDataPath: data.path,
      settings: const GameArtSettings(artLookup: true),
    );

    expect(resolver.resolve(request)?.path, cache.path);
  });

  test('corrupt and non-image files are rejected', () {
    invalidateCoverFile(request.id);
    // Plain text wearing an image extension must not be shown.
    writeImage(
      '${data.path}/art/${request.id}.png',
      utf8.encode('this is not an image'),
    );
    final userArt = writeImage('${media.path}/nes/Lanterns_of_Vell.png');
    final resolver = GameArtResolver(
      localDataPath: data.path,
      settings: GameArtSettings(artFolder: media.path),
    );

    expect(resolver.resolve(request)?.path, userArt.path);

    // A truncated PNG (valid header, missing IEND) is rejected too.
    writeImage('${data.path}/art/${request.id}.png', onePixelPng.sublist(0, 20));
    expect(resolver.resolve(request)?.path, userArt.path);

    // With no valid art anywhere the procedural cover is chosen.
    final bare = GameArtResolver(localDataPath: data.path);
    expect(bare.resolve(request), isNull);
  });

  test('media folder matches case-insensitively and tolerates separators', () {
    final userArt = writeImage('${media.path}/NES/Lanterns_of_Vell-(USA).jpg');
    final resolver = GameArtResolver(
      localDataPath: data.path,
      settings: GameArtSettings(artFolder: media.path),
    );

    expect(resolver.resolve(request)?.path, userArt.path);
  });

  test('lookup is off by default and never reads the cache', () {
    invalidateCoverFile(request.id);
    writeImage('${data.path}/art-cache/${artCacheKey(request)}.img');
    final resolver = GameArtResolver(localDataPath: data.path);

    expect(resolver.lookupEnabled, isFalse);
    expect(resolver.resolve(request), isNull);
    expect(GameArtSettings.fromMap(const {}).artLookup, isFalse);
  });

  test('no library identity means no art', () {
    writeImage('${data.path}/art/imp-art-test.png');
    final resolver = GameArtResolver(
      localDataPath: data.path,
      settings: GameArtSettings(artFolder: media.path, artLookup: true),
    );

    expect(
      resolver.resolve(const GameArtRequest(id: '', title: 'Lanterns of Vell', system: 'nes')),
      isNull,
    );
    expect(
      resolver.resolve(const GameArtRequest(id: 'x', title: '   ', system: 'nes')),
      isNull,
    );
  });

  test('fetcher is disabled by default and makes no request', () async {
    final resolver = GameArtResolver(
      localDataPath: data.path,
      settings: const GameArtSettings(artLookup: false),
    );
    expect(await fetchArtFor(request, resolver: resolver), ArtFetchOutcome.disabled);
    expect(File(resolver.cachePath(request)).existsSync(), isFalse);
  });

  test('fetcher caches valid images and silently ignores bad responses', () async {
    final resolver = GameArtResolver(
      localDataPath: data.path,
      settings: const GameArtSettings(artLookup: true),
    );
    Future<List<int>> respondWith(List<int> bytes) async => bytes;

    expect(
      await fetchArtFor(
        request,
        resolver: resolver,
        fetchBytes: (_, _, _) => respondWith(utf8.encode('not an image')),
      ),
      ArtFetchOutcome.failed,
    );
    expect(File(resolver.cachePath(request)).existsSync(), isFalse);
    expect(resolver.resolve(request), isNull, reason: 'procedural cover stays');

    expect(
      await fetchArtFor(
        request,
        resolver: resolver,
        fetchBytes: (_, _, _) => respondWith(onePixelPng),
      ),
      ArtFetchOutcome.saved,
    );
    expect(resolver.resolve(request)?.path, resolver.cachePath(request));
  });

  test('fetcher honours the size cap and swallows transport errors', () async {
    final resolver = GameArtResolver(
      localDataPath: data.path,
      settings: const GameArtSettings(artLookup: true),
    );

    expect(
      await fetchArtFor(
        request,
        resolver: resolver,
        maxBytes: 4,
        fetchBytes: (_, _, _) async => throw StateError('response too large'),
      ),
      ArtFetchOutcome.failed,
    );
    expect(File(resolver.cachePath(request)).existsSync(), isFalse);
  });
}

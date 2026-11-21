import 'dart:convert';
import 'dart:io';

import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/services/art_backfill.dart';
import 'package:ezcore/services/art_fetcher.dart';
import 'package:ezcore/services/game_art.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  late Directory data;

  setUp(() {
    data = Directory.systemTemp.createTempSync('ezcore-art-backfill-');
    PlatformLocalDataDirProvider.pinStartupDir(data.path);
  });

  tearDown(() {
    data.deleteSync(recursive: true);
  });

  GameEntry game(String id, String title, {String system = 'nes'}) {
    return GameEntry(
      id: id,
      title: title,
      system: system,
      filePath: '/games/$id.zip',
      extension: 'zip',
    );
  }

  GameArtResolver enabledResolver() => GameArtResolver(
    localDataPath: data.path,
    settings: const GameArtSettings(artLookup: true),
  );

  test('only games without local art are looked up', () {
    final resolver = enabledResolver();
    final present = File('${data.path}/art/g2.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(onePixelPng);

    final requests = missingArtRequests([
      game('g1', 'Lanterns of Vell'),
      game('g2', 'Pocket Rally'),
      game('', 'No identity'),
      game('g3', '   '),
      game('g4', 'Lanterns of Vell (USA)'),
    ], resolver: resolver);

    expect(present.existsSync(), isTrue);
    // g4 folds to the same title as g1, so it is not requested twice.
    expect(requests.map((r) => r.id), ['g1']);
    expect(requests.first.title, 'Lanterns of Vell');
  });

  test('a duplicate title is only requested once', () {
    final resolver = enabledResolver();
    final requests = missingArtRequests([
      game('a', 'Same Game (USA)'),
      game('b', 'Same Game (Europe)'),
    ], resolver: resolver);
    expect(requests.length, 1);
  });

  test('backfill is a no-op while the setting is off', () async {
    final resolver = GameArtResolver(
      localDataPath: data.path,
      settings: const GameArtSettings(),
    );
    final result = await backfillMissingArt([
      game('g1', 'Lanterns of Vell'),
    ], resolver: resolver);
    expect(result.ran, isFalse);
    expect(result.saved, 0);
    expect(Directory('${data.path}/art-cache').existsSync(), isFalse);
  });

  test('backfill saves art and reports the count', () async {
    final resolver = enabledResolver();
    final result = await backfillMissingArt(
      [game('g1', 'Lanterns of Vell'), game('g2', 'Pocket Rally')],
      resolver: resolver,
      fetchBytes: (_, _, _) async => onePixelPng,
    );
    expect(result.attempted, 2);
    expect(result.saved, 2);
    expect(
      resolver.resolve(
        const GameArtRequest(
          id: 'g1',
          title: 'Lanterns of Vell',
          system: 'nes',
        ),
      ),
      isNotNull,
    );
  });

  test('backfill stops after consecutive failures', () async {
    final resolver = enabledResolver();
    var calls = 0;
    final result = await backfillMissingArt(
      [
        for (var i = 0; i < 10; i++) game('g$i', 'Game $i'),
      ],
      resolver: resolver,
      maxFailures: 2,
      fetchBytes: (_, _, _) async {
        calls++;
        throw const SocketException('offline');
      },
    );
    expect(calls, 2);
    expect(result.attempted, 2);
    expect(result.saved, 0);
  });

  test('a saved image resets the failure count', () async {
    final resolver = enabledResolver();
    var calls = 0;
    final result = await backfillMissingArt(
      [
        for (var i = 0; i < 8; i++) game('g$i', 'Game $i'),
      ],
      resolver: resolver,
      maxFailures: 2,
      fetchBytes: (_, _, _) async {
        calls++;
        if (calls == 1 || calls > 2) throw const SocketException('offline');
        return onePixelPng;
      },
    );
    // fail, save (resets), fail, fail (stops)
    expect(calls, 4);
    expect(result.saved, 1);
    expect(result.attempted, 4);
  });

  test('artFolderHasImages finds images in system sub-folders only', () {
    final empty = Directory.systemTemp.createTempSync('ezcore-art-empty-');
    addTearDown(() => empty.deleteSync(recursive: true));
    Directory('${empty.path}/nes').createSync(recursive: true);
    File('${empty.path}/nes/notes.txt').writeAsStringSync('not an image');
    expect(artFolderHasImages(empty.path), isFalse);

    File('${empty.path}/nes/a.png').writeAsBytesSync(onePixelPng);
    expect(artFolderHasImages(empty.path), isTrue);
    expect(artFolderHasImages('${empty.path}/missing'), isFalse);
  });

  test('a fetched image lands in the cache the resolver reads', () async {
    final resolver = enabledResolver();
    const request = GameArtRequest(
      id: 'g9',
      title: 'Pocket Rally',
      system: 'gb',
    );
    final outcome = await fetchArtFor(
      request,
      resolver: resolver,
      fetchBytes: (_, _, _) async => onePixelPng,
    );
    expect(outcome, ArtFetchOutcome.saved);
    expect(resolver.resolve(request)?.path, resolver.cachePath(request));
  });
}

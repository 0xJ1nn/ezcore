import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/cover_art.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:ezcore/widgets/orbit_widgets.dart';

class _CacheMarker extends ImageStreamCompleter {}

void main() {
  final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  final redPixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
  );

  test('cover spec is deterministic per game id', () {
    final a = coverSpecFor('imp-test-rom');
    final b = coverSpecFor('imp-test-rom');
    expect(a.top, b.top);
    expect(a.bottom, b.bottom);
    expect(a.motif, b.motif);
    expect(a.accent, b.accent);
  });

  test('cover spec stays inside the approved identity ranges', () {
    for (final id in ['a', 'zelda', 'mario-kart-64', 'imp-xyz', 'homebrew']) {
      final spec = coverSpecFor(id);
      expect(spec.motif, inInclusiveRange(0, 4));
      expect(
        [
          spec.top,
          spec.bottom,
        ].every((c) => c >= 0xFF0A0A0A && c <= 0xFF2A3542),
        isTrue,
        reason: 'palette must stay dark navy/slate for $id',
      );
    }
  });

  test('different games spread across palettes and motifs', () {
    final ids = List.generate(24, (i) => 'game-$i');
    final tops = ids.map((id) => coverSpecFor(id).top).toSet();
    final motifs = ids.map((id) => coverSpecFor(id).motif).toSet();
    expect(tops.length, greaterThan(1));
    expect(motifs.length, greaterThan(1));
  });

  test('no pinned screenshot cover resolves to null', () {
    expect(coverFileFor('definitely-not-a-real-game-id-12345'), isNull);
  });

  test('cached cover lookup refreshes after a screenshot is pinned', () {
    final dir = Directory.systemTemp.createTempSync('ezcore-cover-cache-');
    addTearDown(() => dir.deleteSync(recursive: true));
    PlatformLocalDataDirProvider.pinStartupDir(dir.path);
    const id = 'cover-cache-test';
    final art = File('${dir.path}/art/$id.png');

    invalidateCoverFile(id);
    expect(coverFileFor(id), isNull);
    art.parent.createSync(recursive: true);
    art.writeAsBytesSync(onePixelPng);
    expect(coverFileFor(id), isNull, reason: 'the cache avoids disk churn');

    invalidateCoverFile(id);
    expect(coverFileFor(id)?.path, art.path);
  });

  testWidgets('a mounted cover refreshes after a screenshot is pinned', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ezcore-cover-widget-');
    addTearDown(() => dir.deleteSync(recursive: true));
    PlatformLocalDataDirProvider.pinStartupDir(dir.path);
    const id = 'cover-widget-test';
    final art = File('${dir.path}/art/$id.png');
    invalidateCoverFile(id);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameCover(
            gameId: id,
            title: 'Fixture',
            system: 'test',
            width: 120,
            height: 160,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsNothing);

    art.parent.createSync(recursive: true);
    art.writeAsBytesSync(onePixelPng);
    invalidateCoverFile(id);
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a mounted cover replaces bytes at the same screenshot path', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ezcore-cover-replace-');
    addTearDown(() => dir.deleteSync(recursive: true));
    PlatformLocalDataDirProvider.pinStartupDir(dir.path);
    const id = 'cover-replace-test';
    final art = File('${dir.path}/art/$id.png');
    art.parent.createSync(recursive: true);
    art.writeAsBytesSync(onePixelPng);
    invalidateCoverFile(id);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameCover(
            gameId: id,
            title: 'Fixture',
            system: 'test',
            width: 120,
            height: 160,
          ),
        ),
      ),
    );
    final firstRevision = coverRevision.value;
    expect(find.byType(Image), findsOneWidget);
    final firstProvider = tester.widget<Image>(find.byType(Image)).image;
    expect(firstProvider, isA<FileImage>());
    expect((firstProvider as FileImage).file.path, art.path);

    // Seed the cache with a marker that has no file bytes. A replacement must
    // evict it and make the mounted Image resolve the new same-path provider.
    final cache = PaintingBinding.instance.imageCache;
    final key = FileImage(art);
    cache.evict(key);
    final marker = _CacheMarker();
    final markerHandle = marker.keepAlive();
    addTearDown(() {
      cache.evict(key);
      markerHandle.dispose();
    });
    cache.putIfAbsent(key, () => marker);
    expect(cache.statusForKey(key).tracked, isTrue);

    // The screenshot path is unchanged; only its bytes are replaced.
    art.writeAsBytesSync(redPixelPng);
    invalidateCoverFile(id);
    await tester.pump();

    expect(coverRevision.value, greaterThan(firstRevision));
    expect(find.byType(Image), findsOneWidget);
    expect(cache.statusForKey(key).tracked, isTrue);
    final secondProvider = tester.widget<Image>(find.byType(Image)).image;
    expect(secondProvider, isA<FileImage>());
    expect((secondProvider as FileImage).file.path, art.path);
    expect(art.readAsBytesSync(), redPixelPng);
  });
}

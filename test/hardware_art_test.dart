import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/widgets/hardware_art.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const activeCoreIds = {
    'pocketbit',
    'gambatte',
    'advancebit',
    'nesbyte',
    'superfx',
    'blastproc',
    'joystick',
    'realmode',
    'cardcon',
    'geometry1',
    'rcp64',
    'dualscreen',
    'portcomp',
    'dreamarc',
    'powercube',
    'twinsh',
    'coinbox',
    'pointclick',
  };

  test('active catalog cores have project artwork assets', () {
    final registry =
        jsonDecode(File('cores/registry.json').readAsStringSync())
            as Map<String, dynamic>;
    final active = (registry['cores'] as List)
        .map((id) => id.toString())
        .where((id) => !id.endsWith('_hold'))
        .toSet();

    expect(active, activeCoreIds);
    for (final id in active) {
      final artwork = hardwareArtworkAsset(id);
      expect(artwork, 'assets/core_art/$id.webp', reason: id);
      expect(File(artwork).existsSync(), isTrue, reason: '$id artwork exists');
    }
    expect(File('assets/core_art/generic.webp').existsSync(), isTrue);
  });

  test('every bundled artwork file has a structured provenance record', () {
    final record =
        jsonDecode(File('docs/CORE_ART_PROVENANCE.json').readAsStringSync())
            as Map<String, dynamic>;
    final recorded = (record['files'] as Map).keys.toSet();
    final entries = Directory('assets/core_art').listSync();
    expect(entries.whereType<Directory>(), isEmpty);
    expect(
      entries.whereType<File>().where((file) => !file.path.endsWith('.webp')),
      isEmpty,
    );
    final actual = entries
        .whereType<File>()
        .where((file) => file.path.endsWith('.webp'))
        .map((file) => file.uri.pathSegments.last)
        .toSet();

    expect(recorded, actual);
    expect(recorded, isNotEmpty);
    expect((record['rights'] as Map)['maintainer_review'], 'approved');
  });

  test('every bundled WebP decodes as an image', () async {
    final files = Directory(
      'assets/core_art',
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.webp'));

    for (final file in files) {
      final asset = 'assets/core_art/${file.uri.pathSegments.last}';
      final bytes = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(0), reason: asset);
      expect(frame.image.height, greaterThan(0), reason: asset);
      frame.image.dispose();
      codec.dispose();
    }
  });

  testWidgets('artwork decoding is capped for catalog-sized images', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: CoreArtwork(coreId: 'pocketbit')),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).width, 640);
  });

  test('new cores use system-family artwork without a per-core image', () {
    expect(
      hardwareArtworkAsset('future-pocket-core', systems: ['gba']),
      'assets/core_art/advancebit.webp',
    );
    expect(
      hardwareArtworkAsset('future-dual-screen-core', systems: ['3ds']),
      'assets/core_art/dualscreen.webp',
    );
    expect(
      hardwareArtworkAsset('future-arcade-core', systems: ['neogeo']),
      'assets/core_art/coinbox.webp',
    );
    expect(
      hardwareArtworkAsset('future-pc-core', systems: ['dos']),
      'assets/core_art/realmode.webp',
    );
    expect(
      hardwareArtworkAsset('future-home-computer-core', systems: ['msx']),
      'assets/core_art/realmode.webp',
    );
    expect(
      hardwareArtworkAsset('citra_hold', systems: ['3ds']),
      'assets/core_art/dualscreen.webp',
    );
    expect(
      hardwareArtworkAsset('unknown-core'),
      'assets/core_art/generic.webp',
    );
  });
}

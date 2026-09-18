import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/widgets/hardware_art.dart';

void main() {
  const cores = [
    'sameboy', 'gambatte', 'mgba', 'mesen', 'snes9x', 'mupen64plus',
    'melonds', 'dolphin', 'swanstation', 'ppsspp', 'genesis_plus_gx',
    'beetle_saturn', 'flycast', 'beetle_pce', 'stella', 'fbneo',
    'dosbox_pure', 'scummvm',
  ];

  test('renderer count matches the finalized set', () {
    expect(hardwareArtCores, cores.length);
  });

  test('every core renders a namespaced silhouette', () {
    for (final id in cores) {
      final svg = hardwareSvg(id);
      expect(svg, contains('<svg'), reason: id);
      expect(svg, contains('viewBox="0 0 320 240"'), reason: id);
      expect(svg, contains('ha_'), reason: '$id gradient ids namespaced');
      expect(svg.length, greaterThan(500), reason: id);
    }
  });

  test('unknown ids (legal holds) fall back to a labeled card', () {
    final svg = hardwareSvg('citra_hold');
    expect(svg, contains('<svg'));
    expect(svg, contains('citra_hold'));
  });

  testWidgets('silhouettes parse and render without errors', (tester) async {
    for (final id in [
      'sameboy', 'mgba', 'snes9x', 'mupen64plus', 'dolphin', 'swanstation',
      'ppsspp', 'flycast', 'stella', 'fbneo', 'dosbox_pure', 'scummvm',
      'citra_hold',
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SvgPicture.string(hardwareSvg(id))),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: id);
    }
  });
}

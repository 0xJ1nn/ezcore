import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/widgets/hardware_art.dart';

void main() {
  const cores = [
    'pocketbit', 'gambatte', 'advancebit', 'nesbyte', 'superfx', 'rcp64',
    'dualscreen', 'powercube', 'geometry1', 'portcomp', 'blastproc',
    'twinsh', 'dreamarc', 'cardcon', 'joystick', 'coinbox',
    'realmode', 'pointclick',
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

  test('unknown ids (hold cores) fall back to a labeled card', () {
    final svg = hardwareSvg('citra_hold');
    expect(svg, contains('<svg'));
    expect(svg, contains('citra_hold'));
  });

  testWidgets('silhouettes parse and render without errors', (tester) async {
    for (final id in [
      'pocketbit', 'advancebit', 'superfx', 'rcp64', 'powercube', 'geometry1',
      'portcomp', 'dreamarc', 'joystick', 'coinbox', 'realmode', 'pointclick',
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

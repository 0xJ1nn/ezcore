import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/theme/system_hues.dart';
import 'package:ezcore/widgets/orbit_cover.dart';

const _w = 270.0;
const _h = 360.0;

/// Renders [cover] at a fixed size and returns its raster, so the generated
/// art can be checked pixel by pixel (the design is the spec).
///
/// The raster read-out runs in [tester.runAsync]: inside a test's fake async
/// zone the engine's image future never completes.
Future<_Shot> _shoot(WidgetTester tester, Widget cover) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: _w, height: _h, child: cover),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final bytes = await tester.runAsync(() async {
    final ro = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await ro.toImage(pixelRatio: 1);
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    return data.buffer.asUint8List();
  });
  return _Shot(bytes!);
}

class _Shot {
  _Shot(this.bytes);

  final List<int> bytes; // raw RGBA, _w x _h

  Color at(int x, int y) {
    final i = (y * _w + x).round() * 4;
    return Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
  }
}

const _ndsCover = OrbitCover(
  title: 'Lanterns of Vell',
  systemId: 'nds',
  sysShort: 'NDS',
  year: 2008,
);

void main() {
  testWidgets('renders the design copy: top row, title, system name', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: _w, height: _h, child: _ndsCover),
        ),
      ),
    );
    expect(find.text('NDS'), findsOneWidget);
    expect(find.text('2008'), findsOneWidget);
    expect(find.text('Lanterns of Vell'), findsOneWidget);
    expect(find.text('NINTENDO DS'), findsOneWidget);
  });

  testWidgets('a missing year renders nothing in the top row', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: _w,
            height: _h,
            child: OrbitCover(title: 'T', systemId: 'nds', sysShort: 'NDS'),
          ),
        ),
      ),
    );
    expect(find.text('NDS'), findsOneWidget);
    expect(find.text('2008'), findsNothing);
  });

  testWidgets('favourite, New and state badges, in that priority order', (
    tester,
  ) async {
    Widget cover({bool favorite = false, bool isNew = false, String? badge}) =>
        OrbitCover(
          title: 'T',
          systemId: 'nds',
          sysShort: 'NDS',
          favorite: favorite,
          isNew: isNew,
          badgeText: badge,
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: _w, height: _h, child: cover(favorite: true)),
        ),
      ),
    );
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: _w, height: _h, child: cover(isNew: true)),
        ),
      ),
    );
    expect(find.text('New'), findsOneWidget);

    // An explicit state badge (the screen's decision) wins over both.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: _w,
            height: _h,
            child: cover(favorite: true, isNew: true, badge: 'Needs BIOS'),
          ),
        ),
      ),
    );
    expect(find.text('Needs BIOS'), findsOneWidget);
    expect(find.text('New'), findsNothing);
    expect(find.byIcon(Icons.favorite), findsNothing);
  });

  testWidgets('paints the system hue block clipped to the mark cut', (
    tester,
  ) async {
    final shot = await _shoot(tester, _ndsCover);
    final block = SystemHues.blockFor('nds');

    // Inside the cut (top band, left half and right edge): the system hue.
    final left = shot.at(135, 80);
    expect(left.r8, closeTo(block.r8, 3));
    expect(left.g8, closeTo(block.g8, 3));
    expect(left.b8, closeTo(block.b8, 3));
    final right = shot.at(250, 60);
    expect(right.b8, closeTo(block.b8, 3));

    // Below the cut (bottom left, clear of the text column): the base
    // gradient, not the hue.
    final below = shot.at(5, 330);
    expect(below.r8, lessThan(40));
    expect(below.g8, lessThan(45));
    expect(below.b8, lessThan(60));
    final distance =
        (below.r8 - block.r8).abs() +
        (below.g8 - block.g8).abs() +
        (below.b8 - block.b8).abs();
    expect(distance, greaterThan(30));

    // Bottom right corner: darkest base stop.
    final corner = shot.at(250, 348);
    expect(corner.r8, lessThan(30));
    expect(corner.g8, lessThan(30));
    expect(corner.b8, lessThan(40));
  });

  testWidgets('draws the blue light line along the cut', (tester) async {
    final shot = await _shoot(tester, _ndsCover);
    // The cut at x=50% sits at y=47% of the height; the line peaks #7DB9FF.
    final line = shot.at(135, 169);
    expect(line.r8, greaterThan(90));
    expect(line.g8, greaterThan(140));
    expect(line.b8, greaterThan(200));
  });

  testWidgets('hairline stripes cross the hue block', (tester) async {
    final shot = await _shoot(tester, _ndsCover);
    // A horizontal scan through the block (y=60) crosses every stripe; the
    // block is solid, so lighter pixels can only be the 7% white hairlines.
    var light = 0;
    for (var x = 10; x < 260; x++) {
      if (shot.at(x, 60).r8 >= 12) light++;
    }
    expect(light, greaterThan(5));
  });

  testWidgets('every system id gets its own hue, unknown ids a neutral', (
    tester,
  ) async {
    expect(SystemHues.blockFor('nes'), const Color(0xFF88433F));
    expect(SystemHues.blockFor('snes'), const Color(0xFF634D88));
    expect(SystemHues.blockFor('n64'), const Color(0xFF2D693D));
    expect(SystemHues.blockFor('gb'), const Color(0xFF596117));
    expect(SystemHues.blockFor('gbc'), const Color(0xFF804367));
    expect(SystemHues.blockFor('gba'), const Color(0xFF465790));
    expect(SystemHues.blockFor('nds'), const Color(0xFF00677C));
    expect(SystemHues.blockFor('psx'), const Color(0xFF245F8C));
    expect(SystemHues.blockFor('dc'), const Color(0xFF834B20));
    expect(SystemHues.blockFor('psp'), const Color(0xFF006B67));
    // Unknown systems: neutral slate, not a crash or a random hue.
    expect(SystemHues.blockFor('switch'), SystemHues.fallbackBlock);
    expect(SystemHues.roomTintFor('switch'), SystemHues.fallbackTint);
    // Room tints are the darker sibling of the block.
    expect(SystemHues.roomTintFor('nds'), const Color(0xFF005A72));

    // And the widget really paints a different hue per system.
    final nds = await _shoot(
      tester,
      const OrbitCover(title: 'T', systemId: 'nds', sysShort: 'NDS'),
    );
    final dc = await _shoot(
      tester,
      const OrbitCover(title: 'T', systemId: 'dc', sysShort: 'DC'),
    );
    expect(nds.at(135, 80), isNot(equals(dc.at(135, 80))));
  });
}

/// 0–255 channels without the deprecated `Color.r8/green/blue` getters.
extension _Channels on Color {
  int get r8 => (r * 255.0).round().clamp(0, 255);
  int get g8 => (g * 255.0).round().clamp(0, 255);
  int get b8 => (b * 255.0).round().clamp(0, 255);
}

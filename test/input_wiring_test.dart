// P3b: real devices reach the core. Picture touches become the pointer (the
// DS bottom screen maps to the frame's lower half), sticks become analog
// with a dead zone, and each backend reports libretro's axis convention.
import 'package:ezcore/controls/control_layout.dart';
import 'package:ezcore/controls/control_overlay.dart';
import 'package:ezcore/services/gamepad.dart';
import 'package:ezcore/services/gamepad_linux.dart';
import 'package:ezcore/services/gamepad_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('picture to frame', () {
    test('a single screen maps straight across', () {
      const s = ScreenSpec(rect: NormRect(0, 0, 1, 1));
      final at = frameCoordinate(s, const Size(400, 300), 4 / 3, const Offset(100, 150))!;
      expect(at.dx, closeTo(0.25, 1e-9));
      expect(at.dy, closeTo(0.5, 1e-9));
      expect(frameCoordinate(s, const Size(400, 400), 4 / 3, const Offset(200, 5)), isNull,
          reason: 'letterbox bar is off the picture');
    });

    test('the DS lower screen maps to the lower half of the frame', () {
      const stacked = ScreenSpec(rect: NormRect(0, 0, 1, 1), split: 2, arrange: 'stacked');
      final rects = pictureRects(stacked, const Size(300, 500), 256 / 384);
      final bottom = frameCoordinate(stacked, const Size(300, 500), 256 / 384, rects[1].center)!;
      expect(bottom.dy, closeTo(0.75, 1e-9));
      const side = ScreenSpec(rect: NormRect(0, 0, 1, 1), split: 2, arrange: 'side');
      final r2 = pictureRects(side, const Size(800, 300), 256 / 384);
      final right = frameCoordinate(side, const Size(800, 300), 256 / 384, r2[1].center)!;
      expect(right.dy, closeTo(0.75, 1e-9), reason: 'side by side, same frame half');
    });

    test('frame fractions become libretro pointer coordinates', () {
      expect(toPointer(const Offset(0, 0)), (-32767, -32767));
      expect(toPointer(const Offset(1, 1)), (32767, 32767));
      expect(toPointer(const Offset(0.5, 0.5)), (0, 0));
    });
  });

  testWidgets('a finger on the picture is the pointer; on a button it is not',
      (t) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final layout = ControlLayout.parse({
      'format': 'ezcore.controls/1', 'id': 'x', 'name': 'x', 'systems': ['nds'],
      'orientation': 'portrait', 'screen': {'x': 0, 'y': 0, 'w': 1, 'h': 0.5},
      'controls': [
        {'id': 'a', 'type': 'button', 'input': 'a', 'x': 0.6, 'y': 0.7, 'w': 0.3, 'h': 0.2},
      ],
    }).layout!;
    final picture = <(Offset, bool)>[];
    final buttons = <String>[];
    await t.pumpWidget(MaterialApp(
      home: ControlOverlay(
        layout: layout,
        onInput: (i, p) => buttons.add('$i:$p'),
        toFrame: (p, sz) => frameCoordinate(layout.screen, sz, 1, p),
        onPicture: (at, pressed) => picture.add((at, pressed)),
      ),
    ));
    final g = await t.startGesture(const Offset(200, 200));
    await g.moveTo(const Offset(300, 200));
    await g.up();
    expect(picture.map((e) => e.$2), [true, true, false]);
    expect(picture[1].$1.dx, greaterThan(picture[0].$1.dx));
    expect(buttons, isEmpty);
    await t.tapAt(const Offset(300, 640));
    expect(buttons, ['a:true', 'a:false']);
    expect(picture, hasLength(3), reason: 'a button press is not a pointer');
  });

  group('sticks', () {
    test('a resting stick reads exactly centred; full travel stays full', () {
      expect(GamepadService.applyDeadZone(0.08), 0);
      expect(GamepadService.applyDeadZone(-0.1), 0);
      expect(GamepadService.applyDeadZone(1), 1);
      expect(GamepadService.applyDeadZone(-1), -1);
      expect(GamepadService.applyDeadZone(0.56), closeTo(0.5, 1e-9));
    });

    test('axes map to libretro stick and axis indexes', () {
      expect(const GamepadAxisEvent('lx', 0).retro, (0, 0));
      expect(const GamepadAxisEvent('ry', 0).retro, (1, 1));
      expect(const GamepadAxisEvent('lt', 0).retro, isNull);
    });

    test('Linux and Windows both report down/right as positive', () {
      expect(LinuxEvdevPads.normalizeAxis(255, 0, 255), 1);
      expect(LinuxEvdevPads.normalizeAxis(0, 0, 255), -1);
      expect(LinuxEvdevPads.normalizeAxis(5, 5, 5), 0, reason: 'degenerate range');
      final xin = WindowsXInputPoller.stickAxes(lx: 32767, ly: 32767, rx: 0, ry: -32767);
      expect(xin['lx'], 1);
      expect(xin['ly'], -1, reason: 'XInput up is libretro up (negative)');
      expect(xin['ry'], 1);
    });
  });
}

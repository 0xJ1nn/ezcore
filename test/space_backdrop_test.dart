import 'package:ezcore/widgets/space_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The backdrop is the one always-on animated surface in the app, so the
/// behaviours that matter are: it paints at any size, it schedules no
/// frames when motion is off, and it respects the OS reduced-motion ask.
void main() {
  Future<void> pumpBackdrop(
    WidgetTester tester, {
    required Size size,
    bool motion = true,
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(body: SpaceBackdrop(motion: motion)),
        ),
      ),
    );
  }

  testWidgets('paints at phone, tablet and desktop sizes', (tester) async {
    for (final size in const [
      Size(390, 844),
      Size(1024, 768),
      Size(1600, 1000),
    ]) {
      await pumpBackdrop(tester, size: size);
      expect(tester.takeException(), isNull, reason: 'at $size');
    }
  });

  testWidgets('motion off schedules no animation frames', (tester) async {
    await pumpBackdrop(tester, size: const Size(800, 600), motion: false);
    await tester.pump();
    // Nothing is animating, so the binding has no reason to keep a frame
    // pending. This is what makes the setting meaningful for battery.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('motion on keeps painting frames', (tester) async {
    await pumpBackdrop(tester, size: const Size(800, 600));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('OS reduced motion wins over the motion setting', (tester) async {
    await pumpBackdrop(
      tester,
      size: const Size(800, 600),
      motion: true,
      reduceMotion: true,
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('survives a zero-size box', (tester) async {
    // Defensive: a hidden pane must not throw from the painters.
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(child: SpaceBackdrop()),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('star field is deterministic', () {
    // Two painters built in sequence must agree, otherwise the sky would
    // reshuffle itself on every rebuild.
    final a = StarfieldPainter(t: 0.5);
    final b = StarfieldPainter(t: 0.5);
    expect(a.shouldRepaint(b), isFalse);
    expect(StarfieldPainter(t: 0.6).shouldRepaint(a), isTrue);
  });
}

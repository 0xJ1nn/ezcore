import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/gamepad_windows.dart';

/// Deadzone / trigger calibration for the Windows XInput backend.
///
/// Both thresholds are pure arithmetic over the raw `XINPUT_GAMEPAD`
/// values that `WindowsXInputPoller._poll` reads straight out of the DLL
/// struct with no rescaling: triggers are `view[6]` / `view[7]`, i.e. a
/// single unsigned byte (0..255), and stick axes are `getInt16` at offsets
/// 8/10/12/14, i.e. -32768..32767. These tests therefore need no hardware.
void main() {
  group('stick deadzone', () {
    test('is a small fraction of int16 full scale, not a third of it', () {
      // Full scale on the positive side of an int16 axis.
      const fullScale = 32767;
      expect(WindowsXInputPoller.stickDeadzone, lessThan(fullScale ~/ 4));
      // ...and above 0, so it is a real deadzone at all.
      expect(WindowsXInputPoller.stickDeadzone, greaterThan(0));
    });

    test('resting drift and small noise register as no direction', () {
      // A pad at rest reporting pure sensor noise.
      expect(WindowsXInputPoller.stickCodes(0, 0), isEmpty);
      expect(WindowsXInputPoller.stickCodes(1200, -900), isEmpty);
      // Drifting/worn pads that idle a few thousand counts off centre.
      expect(WindowsXInputPoller.stickCodes(3000, 0), isEmpty);
      expect(WindowsXInputPoller.stickCodes(0, -4500), isEmpty);
      // The old threshold was 12000, so 3000 used to be inside it too — but
      // the values the old threshold killed were 12001..32767, and those
      // now register. That is the visible half of the bug.
      expect(WindowsXInputPoller.stickCodes(12001, 0), {'right'});
      expect(WindowsXInputPoller.stickCodes(-12001, 0), {'left'});
    });

    test('a real push just past the deadzone does register', () {
      final d = WindowsXInputPoller.stickDeadzone;
      expect(WindowsXInputPoller.stickCodes(d + 1, 0), {'right'});
      expect(WindowsXInputPoller.stickCodes(-(d + 1), 0), {'left'});
      expect(WindowsXInputPoller.stickCodes(0, d + 1), {'up'});
      expect(WindowsXInputPoller.stickCodes(0, -(d + 1)), {'down'});
      // Comfortably past it, and at full deflection.
      expect(WindowsXInputPoller.stickCodes(16000, 0), {'right'});
      expect(WindowsXInputPoller.stickCodes(32767, -32768),
          {'right', 'down'});
    });

    test('the boundary itself is exact: at the deadzone is silent', () {
      final d = WindowsXInputPoller.stickDeadzone;
      // Exactly at +/- the threshold is NOT past it (strictly greater-than),
      // so no direction is emitted on any axis.
      expect(WindowsXInputPoller.stickCodes(d, 0), isEmpty);
      expect(WindowsXInputPoller.stickCodes(-d, 0), isEmpty);
      expect(WindowsXInputPoller.stickCodes(0, d), isEmpty);
      expect(WindowsXInputPoller.stickCodes(0, -d), isEmpty);
      // One count further out is past it.
      expect(WindowsXInputPoller.stickCodes(d + 1, 0), {'right'});
      expect(WindowsXInputPoller.stickCodes(0, -(d + 1)), {'down'});
    });
  });

  group('trigger threshold', () {
    test('is a quarter of the 0..255 range, not a tenth', () {
      expect(WindowsXInputPoller.triggerThreshold, 64);
      expect(WindowsXInputPoller.triggerThreshold, greaterThan(255 ~/ 5));
    });

    test('a trigger just under the threshold does not fire', () {
      final t = WindowsXInputPoller.triggerThreshold;
      // At rest.
      expect(WindowsXInputPoller.codesFor(
        buttons: 0,
        leftTrigger: 0,
        rightTrigger: 0,
        lx: 0,
        ly: 0,
        rx: 0,
        ry: 0,
      ), isEmpty);
      // Resting drift of 40 — under the OLD threshold of 30? no, over it:
      // this is exactly the bug, a drifted trigger read as permanently held.
      expect(WindowsXInputPoller.codesFor(
        buttons: 0,
        leftTrigger: 40,
        rightTrigger: 40,
        lx: 0,
        ly: 0,
        rx: 0,
        ry: 0,
      ), isEmpty);
      // Exactly at the threshold: strict greater-than, so still silent.
      expect(WindowsXInputPoller.codesFor(
        buttons: 0,
        leftTrigger: t,
        rightTrigger: t,
        lx: 0,
        ly: 0,
        rx: 0,
        ry: 0,
      ), isEmpty);
    });

    test('a trigger just over the threshold does fire', () {
      final t = WindowsXInputPoller.triggerThreshold;
      expect(WindowsXInputPoller.codesFor(
        buttons: 0,
        leftTrigger: t + 1,
        rightTrigger: 0,
        lx: 0,
        ly: 0,
        rx: 0,
        ry: 0,
      ), {'lt'});
      expect(WindowsXInputPoller.codesFor(
        buttons: 0,
        leftTrigger: 0,
        rightTrigger: t + 1,
        lx: 0,
        ly: 0,
        rx: 0,
        ry: 0,
      ), {'rt'});
      // Both together, and at full pull.
      expect(WindowsXInputPoller.codesFor(
        buttons: 0,
        leftTrigger: 255,
        rightTrigger: 255,
        lx: 0,
        ly: 0,
        rx: 0,
        ry: 0,
      ), {'lt', 'rt'});
    });

    test('the new threshold rejects the old one accepted', () {
      // The whole defect in one assertion: 40 used to be "lt" and "rt"
      // because the old gate was > 30.
      expect(40, greaterThan(30));
      expect(40, lessThanOrEqualTo(WindowsXInputPoller.triggerThreshold));
    });
  });

  group('deadzone and triggers are independent', () {
    test('trigger state never adds a direction and vice versa', () {
      final t = WindowsXInputPoller.triggerThreshold;
      // Triggers pinned on, sticks centred.
      expect(WindowsXInputPoller.codesFor(
        buttons: 0,
        leftTrigger: t + 1,
        rightTrigger: t + 1,
        lx: 0,
        ly: 0,
        rx: 0,
        ry: 0,
      ), {'lt', 'rt'});
      // Stick pushed well past both the old (12000) and new (8000)
      // deadzones, triggers at rest drift — only directions, no lt/rt.
      expect(WindowsXInputPoller.codesFor(
        buttons: 0,
        leftTrigger: 40,
        rightTrigger: 40,
        lx: 20000,
        ly: -20000,
        rx: 0,
        ry: 0,
      ), {'right', 'down'});
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/gamepad_linux.dart';

/// Stands in for `_EvdevDevice`'s bookkeeping: seed the observed window
/// from the first sample, then only ever widen it, and ask the pure
/// helper for the code. [deviceLo]/[deviceHi] are the EVIOCGABS values,
/// or null when that ioctl did not answer.
class _Observed {
  int lo = 0;
  int hi = 0;
  bool seeded = false;

  String? code(int value, {int? deviceLo, int? deviceHi}) {
    if (!seeded) {
      seeded = true;
      lo = value;
      hi = value;
    }
    if (value < lo) lo = value;
    if (value > hi) hi = value;
    return LinuxEvdevPads.absStickCode(
      value: value,
      deviceMin: deviceLo,
      deviceMax: deviceHi,
      observedMin: lo,
      observedMax: hi,
      positive: 'right',
      negative: 'left',
    );
  }
}

/// Absolute-axis (stick) calibration over the kernel's true travel range.
///
/// The device used to seed `absMin`/`absMax` from the FIRST OBSERVED
/// SAMPLE and only ever widen them, so:
///
///  * a stick at rest (first sample 0) gave min == max == 0 and the
///    ratio maths was degenerate until the first real deflection;
///  * one anomalous spike at connect permanently widened the window, so
///    every later reading at rest became a small ratio and latched a
///    direction for the rest of the session.
///
/// EVIOCGABS reports each axis's real minimum/maximum, and calibration
/// now normalizes against that. No device is needed for these tests:
/// [LinuxEvdevPads.absStickCode] takes the kernel range (null when the
/// ioctl failed) plus the observed window, so nothing here touches
/// /dev/input and no ioctl runs.
///
/// Threshold semantics under test (UNCHANGED by this fix): the reading is
/// normalized to 0..1 over the range; > 0.75 is the positive direction,
/// < 0.25 the negative one, and 0.25..0.75 inclusive is silence.
void main() {
  // A typical 16-bit signed ABS axis as EVIOCGABS reports it. The range
  // is NOT symmetric (-32768..32767) and does NOT start at 0, which is
  // exactly why seeding from the first sample was wrong.
  const devLo = -32768;
  const devHi = 32767;
  const span = devHi - devLo; // 65535

  group('absolute stick range from EVIOCGABS', () {
    test('centred stick with a real device range reports NO direction', () {
      // 0 is the resting reading of a 16-bit centred axis. Normalized
      // over the true range that is ratio 32768/65535 = 0.5000076, i.e.
      // dead centre, so no direction is reported.
      final obs = _Observed();
      expect(obs.code(0, deviceLo: devLo, deviceHi: devHi), isNull);

      // Small residual drift either side of centre is still centre.
      expect(obs.code(-8, deviceLo: devLo, deviceHi: devHi), isNull);
      expect(obs.code(9, deviceLo: devLo, deviceHi: devHi), isNull);

      // The effective range is the DEVICE's, not the observed one. This
      // is the regression: before the fix the range at rest was (0, 0),
      // a degenerate window that reports nothing and then latches on
      // the first spike.
      expect(
          LinuxEvdevPads.absRange(
              deviceMin: devLo,
              deviceMax: devHi,
              observedMin: 0,
              observedMax: 0),
          (devLo, devHi));
    });

    test('an anomalous spike at connect no longer latches a direction', () {
      // One wild sample at open. Under the old observed-only seeding the
      // window became (0, 30000) forever, so the stick returning to rest
      // read as ratio 0.0 and latched 'left' for the whole session. With
      // the kernel range the spike is just a reading.
      final obs = _Observed();
      expect(obs.code(30000, deviceLo: devLo, deviceHi: devHi), 'right');

      // Back to rest: centre again, no direction. Pre-fix this returned
      // 'left' and stayed there.
      expect(obs.code(0, deviceLo: devLo, deviceHi: devHi), isNull);
      expect(obs.code(0, deviceLo: devLo, deviceHi: devHi), isNull);

      // The observed window is still the poisoned (0, 30000)...
      expect((obs.lo, obs.hi), (0, 30000));
      // ...and is ignored because the device range is usable.
      expect(
          LinuxEvdevPads.absRange(
              deviceMin: devLo,
              deviceMax: devHi,
              observedMin: 0,
              observedMax: 30000),
          (devLo, devHi));

      // Control: with no device range at all the SAME poisoned window
      // does latch. This is the old behaviour, kept as the fallback.
      // The stand-in seeds lo/hi from its first sample, so the opening
      // spike both seeds AND is judged against that window -- ask twice so
      // the assertion is about the latched direction, not the degenerate
      // first read (max <= min yields null).
      final noIoctl = _Observed()
        ..code(0)
        ..code(30000);
      expect(noIoctl.code(30000), 'right'); // top of the 0..30000 window
      expect(noIoctl.code(0), 'left'); // bottom -- the latched direction
    });

    test('small deflection inside the dead band reports nothing', () {
      final obs = _Observed();
      // The dead band over a real 16-bit range is -16384..24575, so a
      // small nudge either side of centre is silence: ratios 0.4847 and
      // 0.5153.
      expect(obs.code(-1000, deviceLo: devLo, deviceHi: devHi), isNull);
      expect(obs.code(1000, deviceLo: devLo, deviceHi: devHi), isNull);

      // Comfortably inside the band, 30% and 70% of travel.
      final thirty = devLo + 0.30 * span; // -13107.5
      final seventy = devLo + 0.70 * span; // 13106.5
      expect(obs.code(thirty.round(), deviceLo: devLo, deviceHi: devHi),
          isNull);
      expect(obs.code(seventy.round(), deviceLo: devLo, deviceHi: devHi),
          isNull);
    });

    test('the 0.25 and 0.75 edges are themselves silent (strict compare)', () {
      // 0..400 divides exactly, so 0.25 and 0.75 of travel land on whole
      // numbers and the strictness of the comparisons is pinned without
      // float fuzz. Thresholds are NOT changed by this fix.
      //
      // Each reading needs its own stand-in, and the stand-in's FIRST call
      // is a seeding read (it sets lo=hi=thatValue, so the window is
      // 0-wide and stickCode returns null). Seed with a mid-travel value
      // first, then assert the reading under test.
      // The stand-in only ever widens from its first sample, so a usable
      // window requires feeding BOTH extremes first. Critically, the reading
      // under test must not itself widen the window: asking about 99 would
      // leave the window 0..99 and report ratio 1.0, which says nothing
      // about the 0.25 edge. So each reading gets its own stand-in whose
      // window is pinned to 0..400 by the two extremes alone.
      String? at(int v) {
        final o = _Observed();
        o.code(0, deviceLo: 0, deviceHi: 400);
        o.code(400, deviceLo: 0, deviceHi: 400);
        return LinuxEvdevPads.absStickCode(
          value: v,
          deviceMin: 0,
          deviceMax: 400,
          observedMin: o.lo,
          observedMax: o.hi,
          positive: 'right',
          negative: 'left',
        );
      }

      // The band is 0.25..0.75 INCLUSIVE of silence, so the edges
      // themselves are silent and only values strictly outside are a
      // direction. Over 0..400: 100 -> .25 and 300 -> .75 are silent;
      // 99 -> .2475 is already BELOW 0.25 and 101 -> .2525 is just
      // inside the band.
      expect(at(100), isNull); // .25  -- lower edge, silent
      expect(at(300), isNull); // .75  -- upper edge, silent
      expect(at(101), isNull); // .2525 -- just inside the band
      expect(at(299), isNull); // .7475 -- just inside the band
      // Strictly outside the band is a direction, not silence.
      expect(at(99), 'left'); // .2475
      expect(at(98), 'left'); // .245
      expect(at(301), 'right'); // .7525
      expect(at(302), 'right'); // .755
    });

    test('large deflection reports the correct direction', () {
      final obs = _Observed();
      // 0.80 and 0.20 of travel are 19660 and -19661.
      final eighty = (devLo + 0.80 * span).round();
      final twenty = (devLo + 0.20 * span).round();
      expect(obs.code(eighty, deviceLo: devLo, deviceHi: devHi), 'right');
      expect(obs.code(twenty, deviceLo: devLo, deviceHi: devHi), 'left');
    });

    test('positive and negative extremes map to opposite directions', () {
      final obs = _Observed();
      expect(obs.code(devHi, deviceLo: devLo, deviceHi: devHi), 'right');
      expect(obs.code(devLo, deviceLo: devLo, deviceHi: devHi), 'left');
      // A push past the reported maximum is still that direction rather
      // than wrapping or going silent.
      expect(obs.code(devHi + 5000, deviceLo: devLo, deviceHi: devHi),
          'right');
      expect(obs.code(devLo - 5000, deviceLo: devLo, deviceHi: devHi), 'left');
    });

    test('an 8-bit axis (0..255) calibrates the same way', () {
      // Many pads report 0..255 with the rest position at ~128, not 0.
      // Observed-only seeding is at its worst here: the first sample 128
      // would split the axis at the middle of its real travel.
      final obs = _Observed();
      expect(obs.code(128, deviceLo: 0, deviceHi: 255), isNull);
      expect(obs.code(250, deviceLo: 0, deviceHi: 255), 'right');
      expect(obs.code(5, deviceLo: 0, deviceHi: 255), 'left');
    });
  });

  group('ioctl failure falls back to observed sampling', () {
    test('null device range uses the observed window, inert at rest', () {
      // EVIOCGABS answered nothing for this axis. At rest the observed
      // window is zero-width, so the effective range is (0, 0) and the
      // degenerate guard reports no direction instead of a spurious one.
      expect(
          LinuxEvdevPads.absRange(
              deviceMin: null,
              deviceMax: null,
              observedMin: 0,
              observedMax: 0),
          (0, 0));
      expect(
          LinuxEvdevPads.absStickCode(
              value: 0,
              deviceMin: null,
              deviceMax: null,
              observedMin: 0,
              observedMax: 0,
              positive: 'right',
              negative: 'left'),
          isNull);
    });

    test('fallback is sane once the axis has actually moved', () {
      // Same ioctl failure, no device range at any point. The very first
      // sample is degenerate by construction, so it stays silent...
      final obs = _Observed();
      expect(obs.code(-20000), isNull);
      // ...then a real push opens the window and directions work.
      expect(obs.code(20000), 'right');
      expect((obs.lo, obs.hi), (-20000, 20000));
      // Centre of a symmetric observed window is ratio 0.5: silent, not
      // latched to either side.
      expect(obs.code(0), isNull);
      expect(obs.code(100), isNull);
      // The window ends still resolve to opposite directions.
      expect(obs.code(-20000), 'left');
      expect(obs.code(20000), 'right');
    });

    test('a zero or inverted device range is rejected, not trusted', () {
      // Some drivers report 0..0. Trusting that would make every sample
      // degenerate, so the axis falls back to observed sampling.
      expect(
          LinuxEvdevPads.absRange(
              deviceMin: 0,
              deviceMax: 0,
              observedMin: -100,
              observedMax: 100),
          (-100, 100));
      expect(
          LinuxEvdevPads.absRange(
              deviceMin: 10,
              deviceMax: 5,
              observedMin: -100,
              observedMax: 100),
          (-100, 100));
      // Nothing usable anywhere: inert, not a spurious direction.
      expect(
          LinuxEvdevPads.absRange(
              deviceMin: 0, deviceMax: 0, observedMin: 0, observedMax: 0),
          (0, 0));
    });

    test('a partial answer keeps the axes that did answer', () {
      // readAbsRanges can succeed for some axes and not others; each
      // axis is resolved independently.
      expect(
          LinuxEvdevPads.absRange(
              deviceMin: -32768,
              deviceMax: 32767,
              observedMin: 0,
              observedMax: 0),
          (-32768, 32767));
      // This axis was missing from the map, so it uses observations.
      expect(
          LinuxEvdevPads.absRange(
              deviceMin: null,
              deviceMax: null,
              observedMin: 0,
              observedMax: 255),
          (0, 255));
    });
  });

  group('EVIOCGABS ioctl encoding', () {
    test('request numbers follow _IOC(READ, E, 0x40 + axis, 24 bytes)', () {
      // ABS_X(0), ABS_Y(1), ABS_RX(3), ABS_RY(4) are the tracked axes.
      for (final axis in LinuxEvdevPads.absAxes) {
        final req = LinuxEvdevPads.evioCgabs(axis);
        expect(req & 0xff, 0x40 + axis, reason: 'direction/type + axis');
        expect((req >> 8) & 0xff, 0x45, reason: "ioctl group 'E'");
        expect((req >> 16) & 0x3fff, 24,
            reason: 'size of struct input_absinfo');
        expect((req >> 30) & 0x3, 2, reason: 'read direction');
      }
      // The four tracked axes produce four distinct requests.
      expect(
          LinuxEvdevPads.absAxes
              .map(LinuxEvdevPads.evioCgabs)
              .toSet()
              .length,
          LinuxEvdevPads.absAxes.length);
    });

    test('the known request numbers are the kernel constants', () {
      // _IOR('E', 0x40, struct input_absinfo) == 0x80184540 on the
      // asm-generic ioctl encoding. Spelled out so a wrong constant
      // fails loudly instead of silently returning no ranges.
      expect(LinuxEvdevPads.evioCgabs(0), 0x80184540); // ABS_X
      expect(LinuxEvdevPads.evioCgabs(1), 0x80184541); // ABS_Y
      expect(LinuxEvdevPads.evioCgabs(3), 0x80184543); // ABS_RX
      expect(LinuxEvdevPads.evioCgabs(4), 0x80184544); // ABS_RY
    });
  });
}

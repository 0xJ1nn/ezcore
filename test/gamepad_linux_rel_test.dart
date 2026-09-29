import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/gamepad_linux.dart';

/// Builds a synthetic 24-byte `struct input_event` (native endianness:
/// timeval sec/nsec at 0..15, type at 16, code at 18, value at 20).
Uint8List inputEvent(int type, int code, int value) {
  final data = ByteData(24);
  data.setUint16(16, type, Endian.host);
  data.setUint16(18, code, Endian.host);
  data.setInt32(20, value, Endian.host);
  return data.buffer.asUint8List();
}

void main() {
  const evRel = 2;
  const relX = 0;
  const relY = 1;
  const relHwheel = 6;
  const relWheel = 8;
  const evAbs = 3;
  const evKey = 1;

  group('evdev EV_REL decoding', () {
    test('REL_X decodes from a 24-byte input_event struct', () {
      // Synthetic mouse motion: type=EV_REL(2) code=REL_X(0) value=+7.
      final raw = inputEvent(evRel, relX, 7);
      expect(raw.length, 24);

      // 1. The raw struct parses back to (type, code, value).
      final parsed = LinuxEvdevPads.parseEvent(raw);
      expect(parsed, (2, 0, 7));

      // 2. The decoder maps it to the rel_x axis with the signed delta.
      expect(LinuxEvdevPads.relDelta(parsed!.$1, parsed.$2, parsed.$3),
          ('rel_x', 7));
    });

    test('negative and large deltas pass through unthresholded', () {
      expect(LinuxEvdevPads.relDelta(evRel, relX, -9), ('rel_x', -9));
      expect(LinuxEvdevPads.relDelta(evRel, relY, -1200), ('rel_y', -1200));
      expect(
          LinuxEvdevPads.relDelta(evRel, relWheel, 1), ('rel_wheel', 1));
    });

    test('untracked relative codes and other event types are dropped', () {
      // REL_HWHEEL(6) is outside the mapped set for this slice.
      expect(LinuxEvdevPads.relDelta(evRel, relHwheel, 1), isNull);
      // A key press is never a pointer delta.
      expect(LinuxEvdevPads.relDelta(evKey, relX, 1), isNull);
      // An absolute stick axis is not a pointer delta either.
      expect(LinuxEvdevPads.relDelta(evAbs, 0, 128), isNull);
    });

    test('tracked axes are exactly REL_X, REL_Y and REL_WHEEL', () {
      expect(LinuxEvdevPads.relCodes,
          {0: 'rel_x', 1: 'rel_y', 8: 'rel_wheel'});
    });
  });
}

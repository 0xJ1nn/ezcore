// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'package:ezcore/theme/accessibility.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => MotionPreference.shared.reset());
  tearDown(() => MotionPreference.shared.reset());

  test(
    'missing and legacy reduce-motion values normalise without new states',
    () {
      expect(normalizeReducedMotion(null), ReducedMotion.system);
      expect(normalizeReducedMotion('legacy'), ReducedMotion.system);
      expect(normalizeReducedMotion(true), ReducedMotion.on);
      expect(normalizeReducedMotion(false), ReducedMotion.off);
      expect(normalizeReducedMotion('on'), ReducedMotion.on);
      expect(normalizeReducedMotion('Off'), ReducedMotion.off);

      expect(reducedMotionToken(ReducedMotion.system), isNull);
      expect(reducedMotionToken(ReducedMotion.on), isTrue);
      expect(reducedMotionToken(ReducedMotion.off), isFalse);
    },
  );

  test('Follow system defers to the OS; On and Off override it', () {
    expect(ReducedMotion.system.resolve(true), isTrue);
    expect(ReducedMotion.system.resolve(false), isFalse);
    expect(ReducedMotion.on.resolve(false), isTrue);
    expect(ReducedMotion.off.resolve(true), isFalse);
    expect(
      [
        ReducedMotion.system,
        ReducedMotion.on,
        ReducedMotion.off,
      ].map((state) => state.next),
      [ReducedMotion.on, ReducedMotion.off, ReducedMotion.system],
    );
  });

  test('the switch walks all three states back to Follow system', () {
    var value = ReducedMotion.system;
    final visited = <ReducedMotion>[value];
    for (var i = 0; i < 3; i++) {
      value = value.next;
      visited.add(value);
    }
    expect(
      visited,
      [
        ReducedMotion.system,
        ReducedMotion.on,
        ReducedMotion.off,
        ReducedMotion.system,
      ],
    );
    expect(reducedMotionToken(value), isNull);
  });

  test('text scale only accepts 100, 115 and 130', () {
    expect(textScaleOptions, [100, 115, 130]);
    expect(normalizeTextScale(115), 115);
    expect(normalizeTextScale('130'), 130);
    expect(normalizeTextScale(140), 100);
    expect(normalizeTextScale(null), 100);
  });

  test('the motion preference swaps Tokens durations and curves', () {
    MotionPreference.shared.set(ReducedMotion.off);
    expect(Tokens.fastDur, Tokens.fullFastDur);
    expect(Tokens.baseDur, Tokens.fullBaseDur);
    expect(Tokens.ambientDur, Tokens.fullAmbientDur);
    expect(Tokens.sceneDur, Tokens.fullSceneDur);
    expect(Tokens.ease, Tokens.fullEase);

    MotionPreference.shared.set(ReducedMotion.on);
    expect(Tokens.fastDur, Duration.zero);
    expect(Tokens.baseDur, Tokens.reducedFadeDur);
    expect(Tokens.moveDur, Tokens.reducedFadeDur);
    expect(Tokens.ambientDur, Tokens.reducedFadeDur);
    expect(Tokens.easeDur, Tokens.ambientDur);
    expect(Tokens.sceneDur, Duration.zero);
    expect(Tokens.ease.transform(0.5), closeTo(0.5, 0.001));
  });

  testWidgets('the accessibility scope writes both MediaQuery settings', (
    tester,
  ) async {
    late MediaQueryData seen;
    await tester.pumpWidget(
      MaterialApp(
        home: AccessibilityScope(
          reducedMotion: ReducedMotion.on,
          textScale: 1.3,
          child: Builder(
            builder: (context) {
              seen = MediaQuery.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(seen.disableAnimations, isTrue);
    expect(seen.textScaler.scale(100), 130);

    await tester.pumpWidget(
      MaterialApp(
        home: AccessibilityScope(
          reducedMotion: ReducedMotion.system,
          textScale: 1.0,
          child: Builder(
            builder: (context) {
              seen = MediaQuery.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(seen.disableAnimations, isFalse);
    expect(seen.textScaler.scale(100), 100);
  });
}

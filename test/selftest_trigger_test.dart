// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/selftest/selftest_trigger.dart';

void main() {
  group('self-check startup trigger', () {
    test('release builds ignore every trigger', () {
      expect(
        requestedSelftestPlan(
          releaseMode: true,
          arguments: const ['--selftest', 'synthetic'],
          environment: const {'EZCORE_SELFTEST': 'synthetic'},
          compileTime: 'synthetic',
        ),
        isNull,
      );
    });

    test('the command-line argument names the plan that follows it', () {
      expect(
        requestedSelftestPlan(
          releaseMode: false,
          arguments: const ['--other', 'x', '--selftest', 'synthetic'],
        ),
        'synthetic',
      );
      expect(
        requestedSelftestPlan(
          releaseMode: false,
          arguments: const ['--selftest'],
        ),
        isNull,
      );
    });

    test('environment and compile-time settings are ordered fallbacks', () {
      expect(
        requestedSelftestPlan(releaseMode: false, environment: const {
          'EZCORE_SELFTEST': 'synthetic'
        }, compileTime: 'another'),
        'synthetic',
      );
      expect(
        requestedSelftestPlan(releaseMode: false, compileTime: 'synthetic'),
        'synthetic',
      );
      expect(requestedSelftestPlan(releaseMode: false), isNull);
    });
  });

  group('self-check availability', () {
    test('release builds are unavailable on every target', () {
      const host = SelftestHost(
        operatingSystem: 'linux',
        releaseMode: true,
        harnessPresent: true,
      );
      expect(selftestAvailability(host).available, isFalse);
      expect(selftestAvailability(host).reason, contains('release'));
    });

    test('unsupported targets report their own name and never claim success', () {
      for (final system in ['windows', 'macos', 'android', 'ios']) {
        final availability = selftestAvailability(SelftestHost(
          operatingSystem: system,
          releaseMode: false,
          harnessPresent: true,
        ));
        expect(availability.available, isFalse, reason: system);
        expect(availability.reason, contains(system));
        expect(availability.reason, isNotEmpty);
      }
    });

    test('a missing harness is reported as unavailable', () {
      final availability = selftestAvailability(const SelftestHost(
        operatingSystem: 'linux',
        releaseMode: false,
        harnessPresent: false,
      ));
      expect(availability.available, isFalse);
      expect(availability.reason, contains('harness'));
    });

    test('Linux with a harness is the one runnable host', () {
      final availability = selftestAvailability(const SelftestHost(
        operatingSystem: 'linux',
        releaseMode: false,
        harnessPresent: true,
      ));
      expect(availability.available, isTrue);
      expect(availability.reason, isEmpty);
    });
  });
}

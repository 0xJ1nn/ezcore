// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Dart suite needs two native inputs a fresh clone does not carry: a
/// pinned libretro header and a built host runtime. These checks keep the
/// setup that provides them tied to the pin and ahead of the test leg.
void main() {
  const pinPath = 'scripts/test_prerequisites.json';
  const setupPath = 'scripts/setup_test_prerequisites.sh';
  const workflowPath = '.github/workflows/ci.yml';

  group('native test prerequisites', () {
    late Map<String, dynamic> pin;
    late String setup;
    late String workflow;

    setUpAll(() {
      pin = File(pinPath).existsSync()
          ? jsonDecode(File(pinPath).readAsStringSync()) as Map<String, dynamic>
          : <String, dynamic>{};
      setup = File(setupPath).existsSync()
          ? File(setupPath).readAsStringSync()
          : '';
      workflow = File(workflowPath).readAsStringSync();
    });

    test('one pinned libretro header is recorded', () {
      expect(
        pin['libretro_header'],
        isA<Map<String, dynamic>>(),
        reason: '$pinPath must pin libretro_header',
      );
      final header = pin['libretro_header'] as Map<String, dynamic>;
      expect(
        header['commit'],
        matches(RegExp(r'^[0-9a-f]{40}$')),
        reason: 'libretro-common must be pinned to one commit',
      );
      expect(header['path'], 'include/libretro.h');
      expect(
        header['sha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
        reason: 'the pinned header must carry its SHA-256',
      );
    });

    test('the setup script reads the pin and builds the host runtime', () {
      expect(setup, isNotEmpty, reason: '$setupPath is missing');
      expect(setup, contains(pinPath));
      expect(setup, contains('scripts/build_runtime.sh'));
      expect(setup, contains('--check'));
    });

    test('the Dart gate provisions prerequisites before it runs tests', () {
      final setupAt = workflow.indexOf(setupPath);
      final testAt = workflow.indexOf(
        'flutter test',
        setupAt < 0 ? 0 : setupAt,
      );
      expect(
        setupAt,
        greaterThan(0),
        reason: '$workflowPath must run $setupPath before the Dart suite',
      );
      expect(
        testAt,
        greaterThan(setupAt),
        reason: 'prerequisites must exist before flutter test starts',
      );
    });
  });
}

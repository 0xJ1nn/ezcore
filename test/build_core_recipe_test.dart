// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

// Integrates the offline core-recipe suite with `flutter test`. Network
// resolution is checked separately so a test pass does not depend on an
// upstream service being reachable.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core recipes keep pinned sources and exclude held cores', () {
    if (Platform.isWindows) {
      markTestSkipped('python3 is not available on Windows');
      return;
    }
    final probe = Process.runSync('python3', ['--version']);
    if (probe.exitCode != 0) {
      markTestSkipped('python3 is not available');
      return;
    }

    final result = Process.runSync(
      'python3',
      [
        '-m',
        'unittest',
        'scripts.tests.test_build_core_urls.BuildCoreRecipeTest',
        '-v',
      ],
      workingDirectory: Directory.current.path,
    );
    final output = '${result.stdout}${result.stderr}';
    expect(
      result.exitCode,
      0,
      reason: 'build recipe checks failed:\n$output',
    );
    expect(output, contains('Ran '));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

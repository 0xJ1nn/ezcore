// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

// Runs test/check_clean_script_test.sh as part of `flutter test`.
//
// scripts/check_clean.sh is a repository hygiene gate whose behaviour must keep
// working wherever it is invoked. The project's automated gate is `flutter
// test`, hence this wrapper: a shell suite nothing invokes is a suite that
// stops running the first time someone edits the script.
//
// Skipped, not failed, when bash is unavailable: the suite is bash-only, and
// the script under test is run through `sh` on the platforms that matter.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('check_clean.sh passes its own behavioural suite', () {
    if (Platform.isWindows) {
      markTestSkipped('bash is not available on Windows');
      return;
    }

    final probe = Process.runSync('bash', ['--version']);
    if (probe.exitCode != 0) {
      markTestSkipped('bash is not available');
      return;
    }

    final result = Process.runSync(
      'bash',
      ['test/check_clean_script_test.sh', 'scripts/check_clean.sh'],
      workingDirectory: Directory.current.path,
    );

    final output = '${result.stdout}${result.stderr}';
    expect(
      result.exitCode,
      0,
      reason: 'check_clean_script_test.sh reported failures:\n$output',
    );
    expect(
      output,
      contains('failed=0'),
      reason: 'the suite must report zero failures, not merely exit 0.\n$output',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

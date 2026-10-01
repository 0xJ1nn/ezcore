// Runs test/ios_frameworks_script_test.sh as part of `flutter test`.
//
// Why a Dart wrapper for a shell test: the project's only automated gate is
// `flutter test`, so a shell test that nothing invokes is a test that quietly
// stops running the first time someone touches it. The 16 assertions inside
// cover the ios_frameworks.sh logic on any host, including a Linux CI box
// with no Apple toolchain.
//
// Skipped, not failed, when bash is unavailable: the script under test is
// bash-only anyway, and a missing bash means the script cannot run regardless.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ios_frameworks.sh passes its own behavioural suite', () {
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
      ['test/ios_frameworks_script_test.sh', 'scripts/ios_frameworks.sh'],
      workingDirectory: Directory.current.path,
    );

    final output = '${result.stdout}${result.stderr}';
    expect(
      result.exitCode,
      0,
      reason: 'ios_frameworks_script_test.sh reported failures:\n$output',
    );
    expect(
      output,
      contains('failed=0'),
      reason: 'the suite must report zero failures, not merely exit 0.\n$output',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

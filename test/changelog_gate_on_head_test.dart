// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

// Runs the repository hygiene gate on this checkout as part of `flutter test`.
//
// The promotion check and the merge gate both run the test suite on the exact
// pull-request head. Running the gate here makes its changelog rule part of
// that suite: a change to shipped code with no new entry under `## [Unreleased]`
// fails the pull request, not just a later review. The gate's own behaviour is
// covered separately by check_clean_test.dart on throwaway repositories.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the repository hygiene and changelog gate passes on this checkout', () {
    if (Platform.isWindows) {
      markTestSkipped('the hygiene gate is a POSIX shell script');
      return;
    }

    final root = Directory.current;
    final dotGit = File('${root.path}/.git');
    if (!dotGit.existsSync() && !Directory('${root.path}/.git').existsSync()) {
      markTestSkipped('not a git checkout');
      return;
    }

    final result = Process.runSync(
      'sh',
      ['scripts/check_clean.sh'],
      workingDirectory: root.path,
    );
    final output = '${result.stdout}${result.stderr}';
    expect(
      result.exitCode,
      0,
      reason: 'scripts/check_clean.sh failed on this checkout:\n$output',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

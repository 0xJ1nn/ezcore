// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/local_data_dir.dart';
import 'selftest_runner.dart';
import 'selftest_trigger.dart';
import 'selftest_verdict.dart';

/// The startup setting that names a self-check plan.
const selftestSetting = 'EZCORE_SELFTEST';

/// The directory holding the built harness and its spec fixtures.
const selftestDirectorySetting = 'EZCORE_SELFTEST_DIR';

/// Runs the requested self-check in place of the shell.
///
/// Returns null when no self-check was requested, so an ordinary launch and a
/// release build follow exactly the same path on every platform.
Future<SelftestVerdict?> runStartupSelftest(
  LocalDataDirProvider dirProvider,
) async {
  final plan = requestedSelftestPlan(
    releaseMode: kReleaseMode,
    environment: Platform.environment,
    compileTime: const String.fromEnvironment('EZCORE_SELFTEST'),
  );
  if (plan == null) return null;

  final harnessDirectory =
      Platform.environment[selftestDirectorySetting] ?? 'runtime/build-linux';
  final dataDirectory = await dirProvider.localDataDir();
  final runner = SelftestRunner(
    harnessDirectory: harnessDirectory,
    sinkDirectory: dataDirectory.path,
    host: SelftestHost.current(harnessDirectory),
  );

  final verdict = await runner.run(plan);
  stdout.writeln(
    'self-check ${verdict.plan}: ${verdict.claim.name} — ${verdict.reason}',
  );
  return verdict;
}

// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';

import 'selftest_trigger.dart';
import 'selftest_verdict.dart';

/// Runs one native harness process and returns its result. Injected in tests so
/// a self-check can be graded without a compiled core.
typedef SelftestProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

Future<ProcessResult> _runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) =>
    Process.run(executable, arguments, workingDirectory: workingDirectory);

class SelftestRunner {
  SelftestRunner({
    required this.harnessDirectory,
    required this.sinkDirectory,
    required this.host,
    SelftestProcessRunner? processRunner,
  }) : processRunner = processRunner ?? _runProcess;

  final String harnessDirectory;
  final String sinkDirectory;
  final SelftestHost host;
  final SelftestProcessRunner processRunner;

  Future<SelftestVerdict> run(String planName) async {
    final availability = selftestAvailability(host);
    if (!availability.available) {
      return _persist(SelftestVerdict(
        plan: planName,
        claim: SelftestClaim.unavailable,
        reason: availability.reason,
      ));
    }

    final plan = findSelftestPlan(planName);
    if (plan == null) {
      return _persist(SelftestVerdict(
        plan: planName,
        claim: SelftestClaim.fail,
        reason: 'Unknown self-check plan "$planName".',
      ));
    }

    final executable = Platform.isWindows ? 'ezplay.exe' : 'ezplay';
    final coreFile =
        Platform.isWindows ? 'synth_libretro.dll' : 'libsynth_libretro.so';
    final arguments = <String>[
      '--core',
      '$harnessDirectory/$coreFile',
      '--content',
      '$harnessDirectory/${plan.contentFile}',
      '--system-dir',
      '$harnessDirectory/ezplay-system',
      '--save-dir',
      '$harnessDirectory/ezplay-save',
      '--spec',
      '$harnessDirectory/${plan.specFile}',
    ];

    ProcessResult process;
    try {
      process = await processRunner(
        '$harnessDirectory/$executable',
        arguments,
        workingDirectory: harnessDirectory,
      );
    } catch (error) {
      return _persist(SelftestVerdict(
        plan: planName,
        claim: SelftestClaim.fail,
        reason: 'The self-check harness could not start: $error',
      ));
    }

    final text = process.stdout is String
        ? process.stdout as String
        : '${process.stdout}';
    if (text.trim().isEmpty) {
      return _persist(SelftestVerdict(
        plan: planName,
        claim: SelftestClaim.fail,
        reason: 'The harness exited ${process.exitCode} without a result.',
        exitCode: process.exitCode,
      ));
    }

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return _persist(SelftestVerdict(
        plan: planName,
        claim: SelftestClaim.fail,
        reason: 'The harness did not return a readable JSON result.',
        exitCode: process.exitCode,
      ));
    }
    if (decoded is! Map) {
      return _persist(SelftestVerdict(
        plan: planName,
        claim: SelftestClaim.fail,
        reason: 'The harness result was not a JSON object.',
        exitCode: process.exitCode,
      ));
    }

    final result = decoded.map((key, value) => MapEntry('$key', value));
    return _persist(gradeSelftestResult(plan, result));
  }

  Future<SelftestVerdict> _persist(SelftestVerdict verdict) async {
    final directory = Directory(sinkDirectory);
    if (!directory.existsSync()) await directory.create(recursive: true);
    final file = File('${directory.path}/selftest-result.json');
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(verdict.toJson())}\n',
    );
    return verdict;
  }
}

// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/selftest/selftest_runner.dart';
import 'package:ezcore/selftest/selftest_trigger.dart';
import 'package:ezcore/selftest/selftest_verdict.dart';

Map<String, Object?> harnessResult() => {
      'schema': 1,
      'system': 'synth',
      'core': 'synthetic test core',
      'verdict': 'PASS',
      'exit_code': 0,
      'frames': 120,
      'error': '',
      'frame_checkpoints': [
        {'frame': 0, 'sha256': 'a' * 64, 'colours': 4},
        {'frame': 60, 'sha256': 'b' * 64, 'colours': 9},
      ],
      'checks': {
        'video_changes_after_input': 'PASS',
        'min_colours': 'PASS',
      },
    };

void main() {
  group('self-check runner', () {
    late Directory sink;

    setUp(() {
      sink = Directory.systemTemp.createTempSync('selftest-runner-');
    });

    tearDown(() {
      if (sink.existsSync()) sink.deleteSync(recursive: true);
    });

    SelftestRunner runnerFor(
      SelftestHost host,
      List<List<String>> calls,
      ProcessResult Function(List<String>) respond,
    ) =>
        SelftestRunner(
          harnessDirectory: '/build',
          sinkDirectory: sink.path,
          host: host,
          processRunner: (executable, arguments, {workingDirectory}) async {
            calls.add([executable, ...arguments]);
            return respond(arguments);
          },
        );

    const runnable = SelftestHost(
      operatingSystem: 'linux',
      releaseMode: false,
      harnessPresent: true,
    );

    test('a runnable host writes a result file and reports tested', () async {
      final calls = <List<String>>[];
      final runner = runnerFor(
        runnable,
        calls,
        (_) => ProcessResult(0, 0, jsonEncode(harnessResult()), ''),
      );

      final verdict = await runner.run('synthetic');

      expect(verdict.claim, SelftestClaim.tested);
      expect(calls, hasLength(1));
      expect(calls.single.first, '/build/ezplay');
      expect(calls.single, contains('--core'));
      expect(calls.single, contains('--content'));
      expect(calls.single, contains('--spec'));
      expect(calls.single.last, endsWith('ezplay_spec_synth.json'));

      final file = File('${sink.path}/selftest-result.json');
      expect(file.existsSync(), isTrue);
      final written = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(written['plan'], 'synthetic');
      expect(written['claim'], 'tested');
      expect(written['frames'], 120);
      expect(written['distinctFrames'], 2);
    });

    test('an unavailable host writes a result without starting the harness',
        () async {
      final calls = <List<String>>[];
      final runner = runnerFor(
        const SelftestHost(
          operatingSystem: 'windows',
          releaseMode: false,
          harnessPresent: true,
        ),
        calls,
        (_) => ProcessResult(0, 0, '', ''),
      );

      final verdict = await runner.run('synthetic');

      expect(verdict.claim, SelftestClaim.unavailable);
      expect(verdict.reason, contains('windows'));
      expect(calls, isEmpty);
      final written = jsonDecode(
        File('${sink.path}/selftest-result.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(written['claim'], 'unavailable');
    });

    test('an unknown plan fails without starting the harness', () async {
      final calls = <List<String>>[];
      final runner = runnerFor(
        runnable,
        calls,
        (_) => ProcessResult(0, 0, '', ''),
      );

      final verdict = await runner.run('not-a-plan');

      expect(verdict.claim, SelftestClaim.fail);
      expect(verdict.reason, contains('Unknown'));
      expect(calls, isEmpty);
    });

    test('a harness that cannot start is a reported failure', () async {
      final runner = SelftestRunner(
        harnessDirectory: '/build',
        sinkDirectory: sink.path,
        host: runnable,
        processRunner: (executable, arguments, {workingDirectory}) =>
            throw StateError('harness could not start'),
      );

      final verdict = await runner.run('synthetic');

      expect(verdict.claim, SelftestClaim.fail);
      expect(verdict.reason, contains('could not start'));
      expect(File('${sink.path}/selftest-result.json').existsSync(), isTrue);
    });

    test('harness output that is not JSON is a reported failure', () async {
      final runner = SelftestRunner(
        harnessDirectory: '/build',
        sinkDirectory: sink.path,
        host: runnable,
        processRunner: (executable, arguments, {workingDirectory}) async =>
            ProcessResult(0, 0, 'not json', ''),
      );

      final verdict = await runner.run('synthetic');

      expect(verdict.claim, SelftestClaim.fail);
      expect(verdict.reason, contains('JSON'));
    });
  });

  test('a built harness produces a real result on this host', () async {
    final buildDir = Platform.environment['EZCORE_SELFTEST_DIR'] ?? '';
    if (buildDir.isEmpty || !File('$buildDir/ezplay').existsSync()) {
      markTestSkipped('set EZCORE_SELFTEST_DIR to a built native harness');
      return;
    }
    final sink = Directory.systemTemp.createTempSync('selftest-live-');
    addTearDown(() {
      if (sink.existsSync()) sink.deleteSync(recursive: true);
    });
    final host = SelftestHost.current(buildDir);
    final runner = SelftestRunner(
      harnessDirectory: buildDir,
      sinkDirectory: sink.path,
      host: host,
    );

    final verdict = await runner.run('synthetic');

    expect(verdict.claim, SelftestClaim.tested);
    expect(verdict.rawVerdict, 'PASS');
    expect(verdict.exitCode, 0);
    expect(verdict.frames, greaterThanOrEqualTo(30));
    expect(verdict.distinctFrames, greaterThanOrEqualTo(2));
    expect(
      File('${sink.path}/selftest-result.json').existsSync(),
      isTrue,
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}

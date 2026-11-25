// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/selftest/selftest_verdict.dart';

/// A complete native harness result with two distinct frame hashes.
Map<String, Object?> passingResult({
  int frames = 120,
  List<String> hashes = const ['aaaa', 'bbbb'],
  String verdict = 'PASS',
  int exitCode = 0,
  String error = '',
  Map<String, String>? checks,
}) =>
    {
      'schema': 1,
      'system': 'synth',
      'core': 'synthetic test core',
      'verdict': verdict,
      'exit_code': exitCode,
      'frames': frames,
      'error': error,
      'frame_checkpoints': [
        for (var i = 0; i < hashes.length; i++)
          {'frame': i * 60, 'sha256': hashes[i], 'colours': 4 + i},
      ],
      'checks': checks ?? <String, String>{
        'video_changes_after_input': 'PASS',
        'min_colours': 'PASS',
        'audio_rms': 'PASS',
        'speed': 'PASS',
        'save_state_roundtrip': 'PASS',
        'battery_save_roundtrip': 'SKIP',
        'fast_forward': 'PASS',
        'cheat': 'SKIP',
      },
    };

SelftestPlan planWith(SelftestClaim ceiling) => SelftestPlan(
      name: 'probe',
      system: 'synth',
      specFile: 'spec.json',
      contentFile: 'content.synth',
      highestClaim: ceiling,
    );

void main() {
  group('self-check verdict grading', () {
    test('a passing synthetic run claims tested, never boots or plays', () {
      final verdict = gradeSelftestResult(syntheticPlan, passingResult());

      expect(verdict.claim, SelftestClaim.tested);
      expect(verdict.rawVerdict, 'PASS');
      expect(verdict.exitCode, 0);
      expect(verdict.frames, 120);
      expect(verdict.distinctFrames, 2);
      expect(verdict.checks, hasLength(8));
      expect(verdict.checks.values.where((v) => v == 'PASS'), hasLength(6));
      expect(verdict.reason, contains('not a game boot'));
    });

    test('one frame hash cannot claim a boot even on a boot plan', () {
      final verdict = gradeSelftestResult(
        planWith(SelftestClaim.boots),
        passingResult(hashes: const ['same', 'same']),
      );

      expect(verdict.distinctFrames, 1);
      expect(verdict.claim, SelftestClaim.implemented);
      expect(verdict.reason, contains('distinct frames'));
    });

    test('a short run cannot claim a boot', () {
      final verdict = gradeSelftestResult(
        planWith(SelftestClaim.boots),
        passingResult(frames: 12),
      );

      expect(verdict.claim, SelftestClaim.implemented);
      expect(verdict.reason, contains('30'));
    });

    test('distinct frames on a boot plan claim boots but not plays', () {
      final verdict = gradeSelftestResult(
        planWith(SelftestClaim.boots),
        passingResult(),
      );

      expect(verdict.claim, SelftestClaim.boots);
    });

    test('a play plan without stage evidence is demoted to boots', () {
      final verdict = gradeSelftestResult(
        planWith(SelftestClaim.plays),
        passingResult(),
      );

      expect(verdict.claim, SelftestClaim.boots);
      expect(verdict.reason, contains('stage'));
    });

    test('a play plan with recorded stage evidence can claim plays', () {
      final result = passingResult();
      result['stage_reached'] = true;
      final verdict = gradeSelftestResult(planWith(SelftestClaim.plays), result);

      expect(verdict.claim, SelftestClaim.plays);
    });

    test('a failed native check is a failed self-check with its reason', () {
      final verdict = gradeSelftestResult(
        syntheticPlan,
        passingResult(
          verdict: 'FAIL',
          exitCode: 11,
          error: 'a mandatory play check failed',
        ),
      );

      expect(verdict.claim, SelftestClaim.fail);
      expect(verdict.exitCode, 11);
      expect(verdict.reason, contains('mandatory play check'));
    });

    test('a failing check inside a passing envelope is still a failure', () {
      final checks = <String, String>{
        'video_changes_after_input': 'FAIL',
        'min_colours': 'PASS',
      };
      final verdict =
          gradeSelftestResult(syntheticPlan, passingResult(checks: checks));

      expect(verdict.claim, SelftestClaim.fail);
      expect(verdict.reason, contains('video_changes_after_input'));
    });

    test('the shipped catalog has one plan capped at tested', () {
      expect(selftestPlans, hasLength(1));
      expect(selftestPlans.single, same(syntheticPlan));
      expect(syntheticPlan.highestClaim, SelftestClaim.tested);
      expect(findSelftestPlan('synthetic'), same(syntheticPlan));
      expect(findSelftestPlan('unknown-plan'), isNull);
    });
  });
}

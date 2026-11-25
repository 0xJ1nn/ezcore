// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/// The claims a self-check may make, ordered from weakest to strongest.
///
/// A claim never transfers between targets, and none of the stronger claims is
/// earned by a passing synthetic run. The evidence for each step is recorded
/// in the result file so a reader can see why a run stopped where it did.
enum SelftestClaim {
  unavailable,
  fail,
  implemented,
  tested,
  boots,
  plays,
}

/// One named play spec and the highest claim a run of it may earn.
class SelftestPlan {
  const SelftestPlan({
    required this.name,
    required this.system,
    required this.specFile,
    required this.contentFile,
    required this.highestClaim,
  });

  final String name;
  final String system;
  final String specFile;
  final String contentFile;
  final SelftestClaim highestClaim;
}

/// The deterministic spec uses a synthetic core and invented content. It proves
/// the runtime path only, so its ceiling stops below a game boot.
const SelftestPlan syntheticPlan = SelftestPlan(
  name: 'synthetic',
  system: 'synth',
  specFile: 'ezplay_spec_synth.json',
  contentFile: 'ezplay_content.synth',
  highestClaim: SelftestClaim.tested,
);

const List<SelftestPlan> selftestPlans = <SelftestPlan>[syntheticPlan];

SelftestPlan? findSelftestPlan(String name) {
  for (final plan in selftestPlans) {
    if (plan.name == name) return plan;
  }
  return null;
}

/// A graded self-check result, ready to write to the app's documents folder.
class SelftestVerdict {
  const SelftestVerdict({
    required this.plan,
    required this.claim,
    required this.reason,
    this.rawVerdict = '',
    this.exitCode = -1,
    this.frames = 0,
    this.distinctFrames = 0,
    this.checks = const <String, String>{},
    this.core = '',
  });

  final String plan;
  final SelftestClaim claim;
  final String reason;
  final String rawVerdict;
  final int exitCode;
  final int frames;
  final int distinctFrames;
  final Map<String, String> checks;
  final String core;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': 1,
        'plan': plan,
        'claim': claim.name,
        'reason': reason,
        'nativeVerdict': rawVerdict,
        'nativeExitCode': exitCode,
        'frames': frames,
        'distinctFrames': distinctFrames,
        'checks': checks,
        'core': core,
      };
}

/// Grades the native harness result against what the plan is allowed to claim.
///
/// A passing envelope with one fixed frame has not booted anything, and a
/// synthetic core has not booted a game. Both are demoted rather than reported
/// with a stronger word than the evidence supports.
SelftestVerdict gradeSelftestResult(
  SelftestPlan plan,
  Map<String, Object?> result,
) {
  final rawVerdict = result['verdict'] as String? ?? '';
  final exitCode = result['exit_code'] is int ? result['exit_code'] as int : -1;
  final frames = result['frames'] is int ? result['frames'] as int : 0;
  final core = result['core'] as String? ?? '';
  final error = result['error'] as String? ?? '';

  final checks = <String, String>{};
  final rawChecks = result['checks'];
  if (rawChecks is Map) {
    rawChecks.forEach((key, value) => checks['$key'] = '$value');
  }

  final hashes = <String>{};
  final checkpoints = result['frame_checkpoints'];
  if (checkpoints is List) {
    for (final checkpoint in checkpoints) {
      if (checkpoint is! Map) continue;
      final hash = checkpoint['sha256'];
      if (hash is String && hash.isNotEmpty) hashes.add(hash);
    }
  }

  SelftestVerdict verdict({
    required SelftestClaim claim,
    required String reason,
  }) =>
      SelftestVerdict(
        plan: plan.name,
        claim: claim,
        reason: reason,
        rawVerdict: rawVerdict,
        exitCode: exitCode,
        frames: frames,
        distinctFrames: hashes.length,
        checks: checks,
        core: core,
      );

  final failingChecks = checks.entries
      .where((entry) => entry.value == 'FAIL')
      .map((entry) => entry.key)
      .toList();

  if (exitCode != 0 || rawVerdict != 'PASS' || failingChecks.isNotEmpty) {
    final detail = failingChecks.isNotEmpty
        ? failingChecks.join(', ')
        : error.isNotEmpty
            ? error
            : 'native exit code $exitCode';
    return verdict(
      claim: SelftestClaim.fail,
      reason: 'The self-check failed: $detail.',
    );
  }

  final evidence = '$frames frames and ${hashes.length} distinct frame hashes';
  if (frames < 30) {
    return verdict(
      claim: SelftestClaim.implemented,
      reason: 'The native checks passed after $evidence; at least 30 frames '
          'are needed before a boot can be claimed.',
    );
  }
  if (hashes.length < 2) {
    return verdict(
      claim: SelftestClaim.implemented,
      reason: 'The native checks passed with fewer than two distinct frames '
          '($evidence); one fixed image is not a boot.',
    );
  }

  if (plan.highestClaim == SelftestClaim.plays) {
    if (result['stage_reached'] == true) {
      return verdict(
        claim: SelftestClaim.plays,
        reason: 'Scripted input reached the next stage with $evidence.',
      );
    }
    return verdict(
      claim: SelftestClaim.boots,
      reason: 'Distinct frames were recorded, but no stage completion was '
          'reported ($evidence).',
    );
  }
  if (plan.highestClaim == SelftestClaim.boots) {
    return verdict(
      claim: SelftestClaim.boots,
      reason: 'Distinct frames were recorded with $evidence.',
    );
  }
  return verdict(
    claim: SelftestClaim.tested,
    reason: 'The synthetic play spec passed with $evidence; this proves the '
        'runtime path, not a game boot.',
  );
}

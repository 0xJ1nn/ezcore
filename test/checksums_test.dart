// Runs scripts/tests/test_checksums.py as part of `flutter test`, and pins the
// repository-side decision that test suite protects.
//
// scripts/checksums.py writes and verifies the checksum file a release
// publishes beside its downloads. Its suite lives next to the other script
// suites under scripts/tests/, which is not part of the Dart test tree, so this
// wrapper invokes it, following the same pattern as ios_frameworks_test.dart: a
// suite that nothing runs is a suite that quietly stops running.
//
// A record of the whole source tree is deliberately not committed, and the
// second test fails if one comes back. Such a record goes stale the moment any
// pull request edits a tracked file, so every contribution would have to
// regenerate it; it also proves nothing git's own content addressing does not.
// A gate that verifies it rejects every pull request while it is behind, so
// returning one needs a deliberate decision, not a stray `--write`.
//
// Both tests are skipped, not failed, when python3 or git is unavailable.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Root-level tracked files whose contents look like a checksum record over the
/// tree, found by shape rather than by name so a renamed record is still seen.
List<String> _rootRecords(List<String> tracked) {
  final trackedPaths = tracked.toSet();
  final records = <String>[];
  for (final path in tracked) {
    if (path.contains('/')) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    String text;
    try {
      text = file.readAsStringSync();
    } on FormatException {
      continue; // Binary file; not a text record.
    }
    final listed = <String>{};
    for (final line in text.split('\n')) {
      final match =
          RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(line.trim());
      if (match == null) continue;
      if (trackedPaths.contains(match.group(2)!.trim())) {
        listed.add(match.group(2)!.trim());
      }
    }
    // A handful of lines could be a fixture. A record of the tree is the tree.
    if (listed.length >= 20) records.add(path);
  }
  return records;
}

void main() {
  test('checksums.py passes its own behavioural suite', () {
    final probe = Process.runSync('python3', ['--version']);
    if (probe.exitCode != 0) {
      markTestSkipped('python3 is not available');
      return;
    }

    final result = Process.runSync(
      'python3',
      ['-m', 'unittest', 'discover', '-s', 'scripts/tests', '-p',
       'test_checksums.py'],
      workingDirectory: Directory.current.path,
    );

    final output = '${result.stdout}${result.stderr}';
    expect(
      result.exitCode,
      0,
      reason: 'test_checksums.py reported failures:\n$output',
    );
    expect(
      output,
      contains('OK'),
      reason: 'unittest must report OK, not merely exit 0.\n$output',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the repository commits no whole-tree checksum record', () {
    final probe = Process.runSync('git', ['--version']);
    if (probe.exitCode != 0) {
      markTestSkipped('git is not available');
      return;
    }

    final tracked = Process.runSync(
      'git',
      ['ls-files', '-z'],
      workingDirectory: Directory.current.path,
    );
    expect(
      tracked.exitCode,
      0,
      reason: 'git ls-files failed:\n${tracked.stderr}',
    );
    final paths = (tracked.stdout as String)
        .split('\u0000')
        .where((path) => path.isNotEmpty)
        .toList();

    expect(
      _rootRecords(paths),
      isEmpty,
      reason: 'A root checksum record lists the files in the tree, so it is '
          'stale as soon as any pull request changes one, and a gate that '
          'verifies it rejects every pull request until someone regenerates '
          'all of it. Releases publish their own record instead: '
          'python3 scripts/checksums.py --write --root dist '
          '--record SHA256SUMS.txt. If a whole-tree record is genuinely '
          'wanted, remove this test in the same change, explain why the '
          'regeneration cost on every pull request is worth it, and document '
          'how a contributor regenerates it.',
    );
  });
}

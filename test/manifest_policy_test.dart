import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/cores/cheat_validators.dart';
import 'package:ezcore/models/core_manifest.dart';

/// Policy gates over the shipped manifests (data, not code):
/// cheat families must exist as validators, execution strategies must be
/// declared, iOS must never resolve to dynarec.
void main() {
  List<CoreManifest> loadManifests() {
    final dir = Directory('cores');
    return dir
        .listSync()
        .whereType<Directory>()
        .map((d) => File('${d.path}/manifest.json'))
        .where((f) => f.existsSync())
        .map((f) => CoreManifest.fromJson(
            json.decode(f.readAsStringSync()) as Map<String, dynamic>))
        .toList();
  }

  test('all manifests validate clean', () {
    final manifests = loadManifests();
    expect(manifests.length, greaterThanOrEqualTo(21));
    for (final m in manifests) {
      expect(m.validate(), isEmpty, reason: m.id);
    }
  });

  test('cheat families resolve to real validators', () {
    for (final m in loadManifests()) {
      if (m.cheatsSupported) {
        expect(m.cheatFamilies, isNotEmpty, reason: m.id);
        for (final f in m.cheatFamilies) {
          expect(CheatValidators.families, contains(f), reason: '${m.id}:$f');
        }
      }
    }
  });

  test('execution declared for every shippable core/os', () {
    const desktop = ['macos', 'windows', 'linux', 'android'];
    for (final m in loadManifests()) {
      if (m.blocked) {
        expect(m.execution, isEmpty, reason: m.id);
        continue;
      }
      for (final os in desktop) {
        expect(['interpreter', 'dynarec'], contains(m.executionFor(os)),
            reason: '${m.id}:$os');
      }
      if (m.delivery['ios'] != 'absent') {
        expect(m.executionFor('ios'), 'interpreter', reason: m.id);
      }
      expect(m.executionFor('ios'), isNot('dynarec'), reason: m.id);
    }
  });
}

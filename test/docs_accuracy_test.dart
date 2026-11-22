// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _guidePath = 'docs/CUSTOM-CORES.md';

/// Every top-level key used by at least one committed manifest.
Set<String> _realManifestKeys() {
  final keys = <String>{};
  for (final entity in Directory('cores').listSync()) {
    if (entity is! Directory) continue;
    final manifest = File('${entity.path}/manifest.json');
    if (!manifest.existsSync()) continue;
    final decoded = jsonDecode(manifest.readAsStringSync());
    if (decoded is Map) {
      keys.addAll(decoded.keys.map((key) => '$key'));
    }
  }
  return keys;
}

/// Text of a `##` section, up to the next section or subsection heading.
String? _section(String text, String heading) {
  final lines = text.split('\n');
  final start = lines.indexWhere((line) => line.startsWith('## $heading'));
  if (start < 0) return null;
  final body = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.startsWith('## ') || line.startsWith('### ')) break;
    body.add(line);
  }
  return body.join('\n');
}

void main() {
  group('custom core guide accuracy', () {
    late File guide;
    late String text;
    late Set<String> realKeys;

    setUpAll(() {
      guide = File(_guidePath);
      text = guide.readAsStringSync();
      realKeys = _realManifestKeys();
    });

    test('the guide exists', () {
      expect(guide.existsSync(), isTrue);
      expect(realKeys, isNotEmpty);
    });

    test('the guide has a parseable example manifest', () {
      final section = _section(text, 'Manifest fields');
      expect(section, isNotNull);
      final example = RegExp(
        r'```json\s*\n(.*?)\n```',
        dotAll: true,
      ).firstMatch(section!);
      expect(example, isNotNull);
      final decoded = jsonDecode(example!.group(1)!);
      expect(decoded, isA<Map>());
      expect((decoded as Map).keys, isNotEmpty);
    });

    test('every manifest field the guide names is a real manifest key', () {
      final section = _section(text, 'Manifest fields');
      final named = <String>{};

      // Field reference table: rows whose first column is a backticked name.
      final row = RegExp(
        r'^\|\s*`([a-z][a-z0-9_]*)`\s*\|',
        multiLine: true,
      );
      for (final match in row.allMatches(section!)) {
        named.add(match.group(1)!);
      }

      // Top-level keys of the example manifest.
      final example = RegExp(
        r'```json\s*\n(.*?)\n```',
        dotAll: true,
      ).firstMatch(section)!;
      final decoded = jsonDecode(example.group(1)!) as Map;
      named.addAll(decoded.keys.map((key) => '$key'));

      expect(named, isNotEmpty);
      final unknown = named.where((key) => !realKeys.contains(key)).toList()
        ..sort();
      expect(
        unknown,
        isEmpty,
        reason: 'guide names fields no manifest has: $unknown',
      );
    });

    test('the guide names every real top-level manifest key', () {
      final section = _section(text, 'Manifest fields')!;
      final named = <String>{};
      final row = RegExp(r'^\|\s*`([a-z][a-z0-9_]*)`\s*\|', multiLine: true);
      for (final match in row.allMatches(section)) {
        named.add(match.group(1)!);
      }
      final missing = realKeys.where((key) => !named.contains(key)).toList()
        ..sort();
      expect(
        missing,
        isEmpty,
        reason: 'real manifest fields missing from the guide: $missing',
      );
    });
  });
}

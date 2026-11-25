// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _guidePath = 'docs/CUSTOM-CORES.md';
const String _matrixPath = 'docs/MATRIX.md';

/// The levels a matrix cell may record, with PLAYS as the top of the ladder.
const Set<String> _matrixLevels = {
  'BUILT',
  'IDENTIFIES',
  'BOOTS',
  'RENDERS',
  'PLAYS',
};

/// Trimmed, non-empty cells of a Markdown table row.
List<String> _cells(String line) => line
    .split('|')
    .map((cell) => cell.trim())
    .where((cell) => cell.isNotEmpty)
    .toList();

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

  group('core matrix accuracy', () {
    late String matrix;
    late List<String> lines;

    setUpAll(() {
      matrix = File(_matrixPath).readAsStringSync();
      lines = matrix.split('\n');
    });

    test('every level has one short definition', () {
      for (final level in _matrixLevels) {
        final definition =
            lines.where((line) => line.startsWith('| $level |')).toList();
        expect(definition, hasLength(1), reason: '$level has one definition');
        expect(
          definition.single.length,
          lessThan(160),
          reason: '$level definition is one short line',
        );
      }
    });

    test('the page is a reference table, not a work log', () {
      expect(lines.length, lessThan(150));
    });

    test('each row has one word per platform and a last verified date', () {
      final headerAt = lines.indexWhere(
        (line) => line.startsWith('| Core |') && line.contains('Linux x64'),
      );
      expect(headerAt, isNonNegative, reason: 'the core table has a header');
      final headings = _cells(lines[headerAt]);
      expect(headings.last, 'Last verified');

      final allowed = <Matcher>[
        for (final level in _matrixLevels) equals(level),
        equals('—'),
        equals('holds'),
      ];
      for (final line in lines.skip(headerAt + 2)) {
        if (!line.startsWith('|')) break;
        final row = _cells(line);
        expect(row, hasLength(headings.length), reason: '$row is a full row');
        for (final cell in row.sublist(1, row.length - 1)) {
          expect(cell, anyOf(allowed), reason: '${row.first}: $cell is a level');
        }
        expect(
          RegExp(r'^\d{4}-\d{2}-\d{2}$|^—$').hasMatch(row.last),
          isTrue,
          reason: '${row.first} records a last verified date',
        );
      }
    });

    test('the five release targets and the date column head the table', () {
      final headerAt = lines.indexWhere(
        (line) => line.startsWith('| Core |') && line.contains('Linux x64'),
      );
      expect(headerAt, isNonNegative, reason: 'the core table has a header');
      expect(
        _cells(lines[headerAt]),
        equals([
          'Core',
          'macOS arm64',
          'iOS arm64',
          'Android arm64',
          'Linux x64',
          'Windows x64',
          'Last verified',
        ]),
        reason: 'the table spans exactly the five release targets',
      );
    });

    test('definitions read as a ladder with PLAYS at the top', () {
      final tableAt = lines.indexWhere((line) => line.startsWith('| Core |'));
      final order = <String>[];
      for (final line in lines) {
        final match = RegExp(r'^\| (BUILT|IDENTIFIES|BOOTS|RENDERS|PLAYS) \|')
            .firstMatch(line);
        if (match != null) order.add(match.group(1)!);
      }
      expect(
        order,
        equals(['BUILT', 'IDENTIFIES', 'BOOTS', 'RENDERS', 'PLAYS']),
      );
      final definitions = lines
          .asMap()
          .entries
          .where(
            (entry) =>
                RegExp(r'^\| (BUILT|IDENTIFIES|BOOTS|RENDERS|PLAYS) \|')
                    .hasMatch(entry.value),
          )
          .map((entry) => entry.key);
      for (final at in definitions) {
        expect(at, lessThan(tableAt), reason: 'definitions precede the table');
      }
    });

    test('public text carries no private evidence or internal markers', () {
      final forbidden = <RegExp, String>{
        RegExp(r'docs/evidence/'): 'a private evidence path',
        RegExp(r'github\.com/', caseSensitive: false): 'a repository link',
        RegExp(r'\b(?:LP|ADR|PS)-\d+\b'): 'a task ID',
        RegExp(
          r'\b(?:agent|swarm|handoff|worker|assistant|hermes|claude|copilot|codex)\b',
          caseSensitive: false,
        ): 'an internal process name',
        RegExp(r'~/|/home/|native/test-roms/|runtime/build-linux/'):
            'a local path',
      };
      for (final entry in forbidden.entries) {
        expect(
          entry.key.hasMatch(matrix),
          isFalse,
          reason: 'the public matrix contains ${entry.value}',
        );
      }
    });

    test('evidence stays with the maintainers', () {
      expect(matrix, contains('kept by the maintainers'));
      expect(matrix, isNot(contains('docs/evidence/')));
      expect(
        RegExp(r'\b[a-f0-9]{64}\b').hasMatch(matrix),
        isFalse,
        reason: 'no evidence hash in public text',
      );
    });
  });
}

// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The README's lineup is a public claim; `docs/MATRIX.md` is its evidence.
///
/// The lineup paragraph defines two words. **boots** means the core loaded real
/// content, drew a nonzero pixel sum and survived a state round trip on the
/// named platform — the matrix levels BOOTS and RENDERS. **renders** adds that a
/// frame was recorded and differs from the same build fed another system's
/// file, or that the core refused it — the matrix level RENDERS.
///
/// So a row may say a platform boots when the cell is BOOTS or RENDERS, and may
/// say it renders only when the cell is RENDERS. Anything less is a claim the
/// matrix does not support, which is the failure this test exists to prevent.
void main() {
  const platforms = <String, String>{
    'macOS': 'macOS arm64',
    'iOS': 'iOS arm64',
    'Android': 'Android arm64',
    'Linux': 'Linux x64',
    'Windows': 'Windows x64',
  };

  /// Matrix level per core, keyed by the platform column heading.
  Map<String, Map<String, String>> readMatrix() {
    final lines = File('docs/MATRIX.md').readAsLinesSync();
    final headerAt = lines.indexWhere(
      (line) => line.startsWith('| Core |') && line.contains('Linux x64'),
    );
    expect(headerAt, isNonNegative, reason: 'the matrix has its core table');
    final headings = lines[headerAt]
        .split('|')
        .map((cell) => cell.trim())
        .toList()
        .sublist(1);
    // Drop the trailing Notes column.
    headings.removeLast();

    final levels = <String, Map<String, String>>{};
    for (final line in lines.skip(headerAt + 2)) {
      if (!line.startsWith('|')) break;
      final cells = line
          .split('|')
          .map((cell) => cell.trim())
          .toList()
          .sublist(1);
      if (cells.length < headings.length + 1) continue;
      final byPlatform = <String, String>{};
      for (var i = 1; i < headings.length; i++) {
        byPlatform[headings[i]] = cells[i];
      }
      levels[cells.first] = byPlatform;
    }
    return levels;
  }

  /// True when the cell records at least the named level. RENDERS implies
  /// BOOTS, so a BOOTS question is satisfied by either.
  bool atLeast(String? cell, String level) {
    if (cell == null) return false;
    final records = RegExp(
      r'\b(BUILT|PINNED|IDENTIFIES|BOOTS|RENDERS)\b',
    ).allMatches(cell).map((match) => match.group(1)!).toSet();
    if (level == 'BOOTS') return records.contains('BOOTS');
    if (level == 'RENDERS') return records.contains('RENDERS');
    return records.contains(level);
  }

  /// Core ids named anywhere in the matrix, to tell a core from a system.
  Set<String> matrixIds() => RegExp(r'^\| ([a-z0-9_]+) \|', multiLine: true)
      .allMatches(File('docs/MATRIX.md').readAsStringSync())
      .map((match) => match.group(1)!)
      .toSet();

  /// Lowercased manifest display name to core id.
  Map<String, String> nameToId() {
    final map = <String, String>{};
    for (final entity in Directory('cores').listSync()) {
      if (entity is! Directory) continue;
      final manifest = File('${entity.path}/manifest.json');
      if (!manifest.existsSync()) continue;
      final text = manifest.readAsStringSync();
      final id = RegExp(r'"id"\s*:\s*"([a-z0-9_]+)"').firstMatch(text);
      final name = RegExp(r'"name"\s*:\s*"([^"]+)"').firstMatch(text);
      if (id != null && name != null) {
        map[name.group(1)!.toLowerCase()] = id.group(1)!;
      }
    }
    return map;
  }

  /// Core ids a lineup row names, in order. A row may name several cores, e.g.
  /// "DualVU (Play!) · LRPS2 (PCSX2)".
  List<String> coresNamed(
    String cell,
    Set<String> ids,
    Map<String, String> byName,
  ) {
    final found = <String>{};
    for (final match in RegExp(r'[A-Za-z][A-Za-z0-9_]*').allMatches(cell)) {
      final token = match.group(0)!.toLowerCase();
      if (ids.contains(token)) {
        found.add(token);
      } else if (byName.containsKey(token)) {
        found.add(byName[token]!);
      }
    }
    return found.toList();
  }

  test('the lineup claims no more than the matrix records', () {
    final matrix = readMatrix();
    final ids = matrixIds();
    final byName = nameToId();
    expect(matrix, isNotEmpty, reason: 'matrix table parsed');
    expect(ids, isNotEmpty, reason: 'matrix rows found');
    expect(byName, isNotEmpty, reason: 'manifest names read');

    final readme = File('README.md').readAsLinesSync();
    final start = readme.indexWhere((line) => line.trim() == '## The lineup');
    expect(start, isNonNegative, reason: 'README has the lineup section');

    final offenders = <String>[];
    var claimsChecked = 0;
    for (final line in readme.skip(start + 1)) {
      if (line.trim().startsWith('## ')) break;
      if (!line.startsWith('| ') || line.startsWith('|---')) continue;
      final cells = line.split('|').map((cell) => cell.trim()).toList();
      if (cells.length < 4) continue;
      final named = coresNamed(cells[2], ids, byName);
      final status = cells[3];
      if (named.isEmpty) continue;

      // Which word did the row use, and for which platforms? A row can name a
      // platform in a clause that carries the word and in one that does not,
      // so the platform is resolved per clause.
      for (final clause in status.split(RegExp(r'[;.]'))) {
        final String? claim;
        if (clause.contains('renders')) {
          claim = 'RENDERS';
        } else if (clause.contains('boots')) {
          claim = 'BOOTS';
        } else {
          claim = null;
        }
        if (claim == null) continue;
        final claimed = platforms.entries
            .where((entry) => clause.contains(entry.key))
            .map((entry) => entry.value)
            .toList();
        if (claimed.isEmpty) continue;
        for (final core in named) {
          final row = matrix[core];
          expect(row, isNotNull, reason: '$core is in the matrix');
          for (final platform in claimed) {
            final cell = row![platform];
            claimsChecked++;
            if (!atLeast(cell, claim)) {
              offenders.add(
                '$core ($platform): the lineup says ${claim.toLowerCase()}, '
                'the matrix records ${cell?.replaceAll('|', '/') ?? 'no cell'}',
              );
            }
          }
        }
      }
    }

    expect(
      claimsChecked,
      greaterThan(0),
      reason:
          'at least one lineup clause claims a platform, or this test is '
          'vacuous',
    );
    expect(
      offenders,
      isEmpty,
      reason:
          'the lineup claims more than the matrix proves:\n  '
          '${offenders.join('\n  ')}',
    );
  });
}

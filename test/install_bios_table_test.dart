import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The BIOS table in `docs/INSTALL.md` tells people which files to place for a
/// core. The Systems screen and the player identify a core by its ezCORE
/// name/id, so a row that carries an upstream libretro id sends the reader
/// looking for a core the app never shows. The catalog is the source of truth:
/// every id the table names must exist there, and the display name in the same
/// cell must be the one the catalog gives that id.
void main() {
  Map<String, dynamic> readJson(String path) =>
      json.decode(File(path).readAsStringSync()) as Map<String, dynamic>;

  /// Core id to display name, straight from the shipped catalog.
  Map<String, String> catalogNames() => {
    for (final entry in readJson('cores/catalog.json').entries)
      entry.key: '${(entry.value as Map)['name'] ?? ''}',
  };

  /// Rows of the BIOS table, as [System, Core, Files, Required] cells.
  List<List<String>> biosRows() {
    final lines = File('docs/INSTALL.md').readAsLinesSync();
    final headerAt = lines.indexWhere(
      (line) => line.startsWith('| System |') && line.contains('| Core |'),
    );
    expect(headerAt, isNonNegative, reason: 'docs/INSTALL.md has the BIOS table');

    final rows = <List<String>>[];
    for (final line in lines.skip(headerAt + 2)) {
      if (!line.startsWith('|')) break;
      final cells = line
          .split('|')
          .map((cell) => cell.trim())
          .toList()
          .sublist(1);
      cells.removeLast();
      rows.add(cells);
    }
    return rows;
  }

  test('every core in the BIOS table is a shipped catalog core', () {
    final names = catalogNames();
    expect(names, isNotEmpty, reason: 'cores/catalog.json parsed');

    final rows = biosRows();
    expect(rows, isNotEmpty, reason: 'BIOS table rows parsed');

    final problems = <String>[];
    for (final cells in rows) {
      final system = cells.first;
      final coreCell = cells[1];
      final ids = RegExp(r'`([^`]+)`')
          .allMatches(coreCell)
          .map((match) => match.group(1)!)
          .toList();

      if (ids.length != 1) {
        problems.add('$system: expected one backticked core id, got $ids');
        continue;
      }
      final id = ids.single;
      final name = names[id];
      if (name == null) {
        problems.add('$system: "$id" is not in cores/catalog.json');
        continue;
      }
      if (!coreCell.replaceAll('`$id`', '').contains(name)) {
        problems.add('$system: "$id" is named "$name" in the catalog, '
            'but the row reads "$coreCell"');
      }
    }

    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}

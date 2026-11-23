// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _catalog() =>
    jsonDecode(File('cores/catalog.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('catalog ships no gated cores', () {
    final catalog = _catalog();
    final gated = catalog.entries
        .where((entry) => (entry.value as Map).containsKey('gated_reason'))
        .map((entry) => entry.key)
        .toList()
      ..sort();
    expect(gated, isEmpty,
        reason: 'cores that cannot ship must not remain in the catalog: $gated');
  });

  test('every catalog core has a manifest and every manifest is catalogued', () {
    final catalog = _catalog();
    final manifests = Directory('cores')
        .listSync()
        .whereType<Directory>()
        .where((dir) => File('${dir.path}/manifest.json').existsSync())
        .map((dir) => dir.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .toSet();
    expect(manifests, catalog.keys.toSet());
  });
}

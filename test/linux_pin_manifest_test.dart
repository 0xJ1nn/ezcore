// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pin policy over the shipped linux-x64 manifests (data, not code).
///
/// A pin is evidence of bytes that exist. Two failure modes are worth
/// catching mechanically: a pin refreshed from a local build that no release
/// contains, and a bundled core whose pin is so recently written that nobody
/// has checked it against a published package. The first is caught by
/// `cores/shipped-bundle-sha256.txt`, the second by requiring every bundled
/// core to be either in that file or in the explicit never-published list
/// below with a reason.
void main() {
  Map<String, dynamic> readJson(String path) =>
      json.decode(File(path).readAsStringSync()) as Map<String, dynamic>;

  List<Map<String, dynamic>> loadManifests() => Directory('cores')
      .listSync()
      .whereType<Directory>()
      .map((d) => File('${d.path}/manifest.json'))
      .where((f) => f.existsSync())
      .map((f) => readJson(f.path))
      .toList();

  /// Parses a checksum file, returning library name to digest.
  Map<String, String> readChecksums(String path) {
    final result = <String, String>{};
    for (final line in File(path).readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length == 2) result[parts[1]] = parts[0].toLowerCase();
    }
    return result;
  }

  /// Bundled on Linux but absent from every published bundle, with the reason.
  /// A core leaves this map when a release ships it; the entry exists so an
  /// unverified pin cannot hide behind "not published yet".
  const neverPublished = <String, String>{
    'lrps2':
        'added after the last release; its Linux library has never been built '
        'into a package, so the pin records a build no one has received',
  };

  test('downloadable linux-x64 cores pin the bytes the release serves', () {
    final release = readJson('cores/release.json');
    final offered =
        (release['assets'] as Map<String, dynamic>)['linux-x64']
            as Map<String, dynamic>;
    final published = readChecksums('cores/published-sha256.txt');
    final byId = {for (final m in loadManifests()) m['id'] as String: m};

    expect(offered, isNotEmpty, reason: 'the release map publishes something');
    for (final entry in offered.entries) {
      final manifest = byId[entry.key];
      expect(manifest, isNotNull, reason: '${entry.key} has no manifest');
      final pin =
          (manifest!['artifacts'] as Map<String, dynamic>)['linux-x64']
              as String?;
      final digest = published[entry.value as String];
      expect(
        digest,
        isNotNull,
        reason: '${entry.value} is not in the published checksum file',
      );
      expect(
        pin?.toLowerCase(),
        digest,
        reason: '${entry.key}: manifest pin must be the published asset bytes',
      );
    }
  });

  test(
    'every bundled linux-x64 pin names bytes a release actually contained',
    () {
      final shipped = readChecksums('cores/shipped-bundle-sha256.txt');
      expect(
        shipped,
        isNotEmpty,
        reason: 'the shipped bundle digest is recorded',
      );

      final bundled = loadManifests()
          .where(
            (m) =>
                (m['delivery'] as Map<String, dynamic>)['linux'] == 'bundled',
          )
          .toList();
      expect(bundled, isNotEmpty, reason: 'at least one core is bundled');

      var matched = 0;
      for (final m in bundled) {
        final id = m['id'] as String;
        final pin =
            (m['artifacts'] as Map<String, dynamic>?)?['linux-x64'] as String?;
        expect(
          pin,
          matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: '$id: linux-x64 pin must be 64 lowercase hex characters',
        );

        final digest = shipped['${id}_libretro.so'];
        if (digest == null) {
          expect(
            neverPublished.containsKey(id),
            isTrue,
            reason:
                '$id is bundled on Linux but no release bundle records its '
                'bytes, so its pin is unverified. Either the release now ships '
                'it — add it to cores/shipped-bundle-sha256.txt — or record why '
                'it has never been published in `neverPublished`.',
          );
          continue;
        }
        expect(
          pin,
          digest,
          reason:
              '$id: the pin must be the library byte a release shipped, not '
              'a local rebuild that no package contains',
        );
        matched++;
      }

      for (final id in neverPublished.keys) {
        expect(
          shipped.containsKey('${id}_libretro.so'),
          isFalse,
          reason:
              '$id is in `neverPublished` but a release bundle records it; '
              'remove the stale exception',
        );
      }
      expect(matched, greaterThan(0), reason: 'some bundled core is verified');
    },
  );
}

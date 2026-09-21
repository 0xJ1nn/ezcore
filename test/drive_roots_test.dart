import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/content_importer.dart';

/// Platform-aware scan roots must stay narrow: only well-known ROM-ish
/// locations, never the bare home directory, never system directories.
void main() {
  test('driveRoots returns only ROM-ish locations, never the bare home', () {
    final roots = ContentImporter.driveRoots();
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    const romish = ['roms', 'games', 'emulation'];
    for (final root in roots) {
      final lower = root.toLowerCase();
      expect(
        romish.any(lower.contains),
        isTrue,
        reason: 'driveRoots must only return ROM-ish dirs, got: $root',
      );
      if (home.isNotEmpty) {
        expect(root, isNot(home), reason: 'must not return the bare home dir');
      }
    }
  });

  test('driveRoots honors platform storage rules', () {
    final roots = ContentImporter.driveRoots();
    if (Platform.isIOS) {
      // Sandboxed: no general storage access.
      expect(roots, isEmpty);
    } else if (Platform.isAndroid) {
      expect(
        roots.every((r) => r.startsWith('/sdcard') ||
            r.startsWith('/storage/emulated/0')),
        isTrue,
        reason: 'Android roots must stay in shared external storage',
      );
    }
    // Desktop platforms (Linux/macOS/Windows) are covered by the
    // ROM-ish + not-bare-home assertions above on every host runner.
  });
}

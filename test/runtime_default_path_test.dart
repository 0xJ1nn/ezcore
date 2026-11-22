// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/runtime/ezcore_runtime.dart';
import 'test_paths.dart' as paths;

void main() {
  test('default runtime loader opens the built ezCore runtime', () {
    // Prefers the legacy default path (runtime/build/<lib>); falls back to
    // the per-platform build dir, then the host build dir the suite setup
    // provisions (scripts/build_runtime.sh output copied to build-host).
    // build-host is not one of the loader's legacy defaults, so locate it
    // here instead of changing the shared path policy other tests use.
    final ext = paths.hostLibExt;
    final defaultLib = File('runtime/build/libezcore_runtime.$ext');
    final built = paths.bridgeLib() ?? _existing([
      'runtime/build-host/libezcore_runtime.$ext',
    ]);
    final runtime = EzCoreRuntime.load(
      runtimePath: defaultLib.existsSync() ? null : built,
    );
    expect(runtime.abiVersion(), 1);
  });
}

/// First path that actually exists, or null when the runtime is not built.
String? _existing(Iterable<String> candidates) {
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

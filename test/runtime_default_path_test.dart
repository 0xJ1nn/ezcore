import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/runtime/ezcore_runtime.dart';
import 'test_paths.dart' as paths;

void main() {
  test('default runtime loader opens the built ezCore runtime', () {
    // Prefers the legacy default path (runtime/build/<lib>); falls back to
    // the per-platform build dir so Linux/Windows dev checkouts pass too.
    final defaultLib =
        File('runtime/build/libezcore_runtime.${paths.hostLibExt}');
    final runtime = EzCoreRuntime.load(
      runtimePath: defaultLib.existsSync() ? null : paths.bridgeLib()!,
    );
    expect(runtime.abiVersion(), 1);
  });
}

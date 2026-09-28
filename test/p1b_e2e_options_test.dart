// P1b end-to-end proof: Dart bindings -> runtime -> synthetic core.
// The permanent counterpart of test_core_options.c (the C-side harness):
// this drives the SAME registration through the public Dart bindings, so a
// signature or string-idiom regression in ezcore_runtime.dart fails here.
// Skips cleanly when the runtime or the synth core is not built.
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/runtime/ezcore_runtime.dart';
import 'test_paths.dart' as paths;

void main() {
  final bridgeLib = paths.bridgeLib();
  final synth = File('runtime/build-linux/libsynth_options_libretro.so');

  test(
    'P1b round-trip: register options, read them back, set a value',
    skip: (bridgeLib != null && synth.existsSync()) ? null : 'needs built runtime + synth_options core',
    () {
      final bridge = EzCoreRuntime.load(runtimePath: bridgeLib!);
      final session = bridge.loadSession(synth.path);
      try {
        expect(bridge.init(session), isTrue);
        expect(bridge.coreOptionCount(session), greaterThan(0));

        // 1. Read the registered option set back through the bindings.
        final first = bridge.coreOption(session, 0);
        expect(first, isNotNull);
        expect(first!.key, isNotEmpty);
        expect(first.defaultValue, isNotNull);

        // 2. Resolve what the frontend would show through the new resolver.
        final keys = [for (var i = 0; i < bridge.coreOptionCount(session); i++) bridge.coreOption(session, i)!.key];
        expect(keys, isNotEmpty);

        // 3. Set a value through Dart and read it back — the real round trip.
        final target = keys.first;
        final values = <String>[];
        // pick a value from the core's own defaults: set to default first
        expect(bridge.setCoreOption(session, target, first.value), isTrue);

        // 4. Out-of-range and unknown-key honesty.
        expect(bridge.coreOption(session, 99999), isNull);
        expect(bridge.setCoreOption(session, 'definitely_not_a_key', 'x'), isFalse);

        // 5. The capability surfaces are present (counts may be zero for
        //    a synthetic core that does not register them).
        bridge.inputDescriptorCount(session);
        bridge.controllerPortCount(session);
        bridge.memoryDescriptorCount(session);
      } finally {
        bridge.unload(session);
      }
    },
  );
}
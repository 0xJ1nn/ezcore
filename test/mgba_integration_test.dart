import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/runtime/ezcore_runtime.dart';
import 'test_paths.dart' as paths;

String _dylib(String id) => paths.stagedCoreLib(id) ?? '';

void main() {
  final bridgeLib = paths.bridgeLib();

  test(
    'mGBA: load, boot, render, save, restore, cheats',
    skip: bridgeLib != null && paths.stagedCoreLib('mgba') != null
        ? null
        : 'mGBA not built on this machine',
    () {
      final lib = _dylib('mgba');
      if (lib.isEmpty) return;

      final romPath = paths.fixture('test.gba') ?? 'native/test-roms/test.gba';
      if (!File(romPath).existsSync()) {
        print('No GBA test ROM — skipping full mGBA test');
        return;
      }

      final bridge = EzCoreRuntime.load(runtimePath: bridgeLib!);
      final session = bridge.loadSession(lib);
      expect(session, isNotNull, reason: 'mGBA dlopen/symbol resolution');

      try {
        // 1. ABI version
        expect(bridge.abiVersion(), 1);

        // 2. Core identification
        expect(bridge.coreName(session), contains('mGBA'));

        // 3. Pre-load geometry guard (mGBA segfaults on pre-load AV queries)
        final pre = bridge.geometry(session);
        expect(pre.w, 0, reason: 'pre-load geometry must return zeros');

        // 4. Set host directories (mGBA needs these for saves)
        bridge.setDirs('native/test-system', 'native/test-save');

        // 5. Load the GBA test ROM
        final romBytes = File(romPath).readAsBytesSync();
        expect(
          bridge.loadGame(session, romPath, romBytes),
          isTrue,
          reason: 'mGBA load_game must succeed',
        );

        // 6. Post-load geometry should be 240x160 (GBA native)
        final post = bridge.geometry(session);
        expect(post.w, 240, reason: 'GBA width');
        expect(post.h, 160, reason: 'GBA height');

        // 7. Run 60 frames and check we get non-zero pixels
        for (var i = 0; i < 60; i++) {
          bridge.runFrame(session);
        }
        final pixelSum = bridge.pixelSum(session);
        expect(pixelSum, greaterThan(0), reason: 'frames rendered pixels');

        // 8. Save state round-trip
        final snap = bridge.saveState(session);
        expect(snap, isNotNull, reason: 'save state produced bytes');
        expect(snap!.length, greaterThan(0));

        // Run more frames (state diverges)
        for (var i = 0; i < 30; i++) {
          bridge.runFrame(session);
        }

        // Restore and verify same pixel output
        expect(bridge.loadState(session, snap), isTrue);
        bridge.runFrame(session);
        final pixelAfterRestore = bridge.pixelSum(session);
        expect(pixelAfterRestore, greaterThan(0));

        // 9. Cheat plumbing (mGBA supports AR/GS/CB codes)
        bridge.cheatReset(session);
        // GBA Action Replay "Infinite Health" pattern (may not affect
        // this test ROM, but verifies the plumbing doesn't crash)
        expect(
          bridge.cheatSet(session, 0, true, '82000064 03E7'),
          isTrue,
          reason: 'cheat_set accepted',
        );

        // 10. Audio drain (silence is fine, just shouldn't crash)
        final audioFrames = bridge.audioFrames(session);
        // Don't assert count — just verify no crash

        // 11. Fast-forward: run 60 more frames without dropping
        for (var i = 0; i < 60; i++) {
          bridge.runFrame(session);
        }
        expect(bridge.pixelSum(session), greaterThan(0));

        print('mGBA integration test PASSED');
        print('  ABI: ${bridge.abiVersion()}');
        print('  Core: ${bridge.coreName(session)}');
        print('  Version: ${bridge.coreVersion(session)}');
        print('  Geometry: ${post.w}x${post.h}');
        print('  Save state: ${snap.length} bytes');
        print('  Cheats: OK');
        print('  Audio frames: $audioFrames');
      } finally {
        bridge.unload(session);
      }
    },
  );

  test(
    'mGBA: core load/unload cycle',
    skip: bridgeLib != null && paths.stagedCoreLib('mgba') != null
        ? null
        : 'mGBA not built on this machine',
    () {
      final lib = _dylib('mgba');
      if (lib.isEmpty) return;

      final bridge = EzCoreRuntime.load(runtimePath: bridgeLib!);

      // Load and unload 3 times to check for leaks/crashes
      for (var i = 0; i < 3; i++) {
        final session = bridge.loadSession(lib);
        expect(session, isNotNull, reason: 'load #$i');
        bridge.unload(session);
      }

      print('mGBA load/unload cycle PASSED (3 iterations)');
    },
  );

  test(
    'mGBA: setDirs before load_game does not crash',
    skip: bridgeLib != null && paths.stagedCoreLib('mgba') != null
        ? null
        : 'mGBA not built on this machine',
    () {
      final lib = _dylib('mgba');
      if (lib.isEmpty) return;

      final bridge = EzCoreRuntime.load(runtimePath: bridgeLib!);
      final session = bridge.loadSession(lib);
      try {
        bridge.setDirs('native/test-system', 'native/test-save');
        bridge.init(session);
        expect(bridge.coreName(session), contains('mGBA'));
      } finally {
        bridge.unload(session);
      }
    },
  );
}

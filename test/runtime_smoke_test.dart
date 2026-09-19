import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/runtime/ezcore_runtime.dart';
import 'test_paths.dart' as paths;

/// id -> expected core name substring. Grows as cores land in native/cores/.
const _cores = <String, String>{
  'pocketbit': 'SameBoy',
  'gambatte': 'Gambatte',
  'advancebit': 'mGBA',
  'superfx': 'Snes9x',
  'blastproc': 'Genesis Plus GX',
  'realmode': 'DOSBox-pure',
  'nesbyte': 'Mesen',
  'dualscreen': 'melonDS',
  'joystick': 'Stella',
  'cardcon': 'Beetle',
  'twinsh': 'Beetle',
  'rcp64': 'Mupen64Plus',
  'geometry1': 'SwanStation',
  'portcomp': 'PPSSPP',
  'dreamarc': 'Flycast',
  'powercube': 'dolphin-emu',
  'coinbox': 'FinalBurn Neo',
  'pointclick': 'ScummVM',
};

String _dylib(String id) => paths.stagedCoreLib(id) ?? '';

void main() {
  final bridgeLib = paths.bridgeLib();
  final blarggRom = paths.fixture('cpu_instrs.gb');

  test(
    'bridge ABI version is 1',
    skip: bridgeLib != null ? null : 'bridge not built',
    () {
      final bridge = EzCoreRuntime.load(runtimePath: bridgeLib!);
      expect(bridge.abiVersion(), 1);
    },
  );

  test(
    'every staged core loads, inits, and identifies',
    skip: bridgeLib != null ? null : 'bridge not built',
    () {
      final bridge = EzCoreRuntime.load(runtimePath: bridgeLib!);
      var exercised = 0;
      for (final entry in _cores.entries) {
        final lib = _dylib(entry.key);
        if (lib.isEmpty) continue; // not built yet on this machine
        exercised++;
        final Pointer<Void> session = bridge.loadSession(lib);
        try {
          expect(bridge.init(session), isTrue, reason: entry.key);
          expect(bridge.coreName(session), contains(entry.value),
              reason: entry.key);
          final pre = bridge.geometry(session);
          expect(pre.w, 0, reason: '${entry.key} pre-load guard');
        } finally {
          bridge.unload(session);
        }
      }
      expect(exercised, greaterThan(0), reason: 'no staged cores found');
    },
  );

  test(
    'sameboy boots blargg and renders pixels',
    skip: (bridgeLib != null && blarggRom != null) ? null : 'no rom',
    () {
      final lib = _dylib('pocketbit');
      if (lib.isEmpty) return;
      final bridge = EzCoreRuntime.load(runtimePath: bridgeLib!);
      final session = bridge.loadSession(lib);
      try {
        expect(bridge.init(session), isTrue);
        final rom = File(blarggRom!).readAsBytesSync();
        expect(bridge.loadGame(session, blarggRom, rom), isTrue);
        // Cheat + dir plumbing must not crash (SameBoy libretro build has
        // cheats compiled out, so this exercises the path, not the effect).
        bridge.setDirs('native/test-system', 'native/test-save');
        bridge.cheatReset(session);
        expect(bridge.cheatSet(session, 0, true, '0101ABCD'), isTrue);
        for (var i = 0; i < 30; i++) {
          bridge.runFrame(session);
        }
        expect(bridge.pixelSum(session), greaterThan(0));
        // Save-state round trip through the runtime (same bytes back in).
        final snap = bridge.saveState(session);
        expect(snap, isNotNull);
        for (var i = 0; i < 30; i++) {
          bridge.runFrame(session);
        }
        expect(bridge.loadState(session, snap!), isTrue);
      } finally {
        bridge.unload(session);
      }
    },
  );
}

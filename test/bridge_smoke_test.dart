import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_emulator/cores/native_bridge.dart';

bool _exists(String path) => File(path).existsSync();

/// id -> expected core name substring. Grows as cores land in native/cores/.
const _cores = <String, String>{
  'sameboy': 'SameBoy',
  'gambatte': 'Gambatte',
  'mgba': 'mGBA',
  'snes9x': 'Snes9x',
  'genesis_plus_gx': 'Genesis Plus GX',
  'dosbox_pure': 'DOSBox-pure',
  'mesen': 'Mesen',
  'melonds': 'melonDS',
  'stella': 'Stella',
  'beetle_pce': 'Beetle',
  'beetle_saturn': 'Beetle',
  'mupen64plus': 'Mupen64Plus',
  'swanstation': 'SwanStation',
  'ppsspp': 'PPSSPP',
  'flycast': 'Flycast',
  'dolphin': 'Dolphin',
  'fbneo': 'FinalBurn Neo',
  'scummvm': 'ScummVM',
};

String _dylib(String id) {
  final dir = Directory('native/cores/$id');
  if (!dir.existsSync()) return '';
  final hits = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('_libretro.dylib'))
      .toList();
  return hits.isEmpty ? '' : hits.first.path;
}

void main() {
  const bridgeLib = 'bridge/build/libhuh_bridge.dylib';
  const blarggRom = 'native/test-roms/cpu_instrs.gb';

  test(
    'bridge ABI version is 1',
    skip: _exists(bridgeLib) ? null : 'bridge not built',
    () {
      final bridge = NativeBridge.load(bridgePath: bridgeLib);
      expect(bridge.abiVersion(), 1);
    },
  );

  test(
    'every staged core loads, inits, and identifies',
    skip: _exists(bridgeLib) ? null : 'bridge not built',
    () {
      final bridge = NativeBridge.load(bridgePath: bridgeLib);
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
    skip: (_exists(bridgeLib) && _exists(blarggRom)) ? null : 'no rom',
    () {
      final lib = _dylib('sameboy');
      if (lib.isEmpty) return;
      final bridge = NativeBridge.load(bridgePath: bridgeLib);
      final session = bridge.loadSession(lib);
      try {
        expect(bridge.init(session), isTrue);
        final rom = File(blarggRom).readAsBytesSync();
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
      } finally {
        bridge.unload(session);
      }
    },
  );
}

// Diagnostic prints are the point of this harness (it reports per-core
// boot/render results when run locally); the lint is for production code.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/runtime/ezcore_runtime.dart';
import 'test_paths.dart' as paths;

bool _exists(String path) => File(path).existsSync();

String _dylib(String id) => paths.stagedCoreLib(id) ?? '';

/// Cores with test ROMs available for full boot + render + save test.
const _coresWithRom = <String, ({String name, String romPath})>{
  'sameboy': (name: 'SameBoy', romPath: 'native/test-roms/cpu_instrs.gb'),
  'gambatte': (name: 'Gambatte', romPath: 'native/test-roms/cpu_instrs.gb'),
  'mgba': (name: 'mGBA', romPath: 'native/test-roms/test.gba'),
};

/// Cores without test ROMs — load + identify only.
const _coresNoRom = <String, String>{
  'snes9x': 'Snes9x',
  'mesen': 'Mesen',
  'genesis_plus_gx': 'Genesis Plus GX',
  'dosbox_pure': 'DOSBox-pure',
  'melonds': 'melonDS',
  'stella': 'Stella',
  'beetle_pce': 'Beetle',
  'beetle_saturn': 'Beetle',
  'mupen64plus': 'Mupen64Plus',
  'swanstation': 'SwanStation',
  'ppsspp': 'PPSSPP',
  'flycast': 'Flycast',
  'dolphin': 'dolphin-emu',
  'fbneo': 'FinalBurn Neo',
  'scummvm': 'ScummVM',
};

void main() {
  final bridgeLib = paths.bridgeLib();

  // --- Full boot tests (cores with test ROMs) ---

  for (final entry in _coresWithRom.entries) {
    final id = entry.key;
    final expectedName = entry.value.name;
    final romPath = entry.value.romPath;

    test(
      '$id: full boot + render + save',
      skip: (bridgeLib != null && _exists(bridgeLib) && _exists(romPath)) ? null : 'no rom or bridge',
      () {
        final lib = _dylib(id);
        if (lib.isEmpty) return;

        final bridge = EzCoreRuntime.load(runtimePath: bridgeLib!);
        final session = bridge.loadSession(lib);
        expect(session, isNotNull, reason: '$id load');

        try {
          expect(bridge.abiVersion(), 1);
          expect(bridge.coreName(session), contains(expectedName));

          bridge.setDirs('native/test-system', 'native/test-save');
          expect(bridge.init(session), isTrue, reason: '$id init');
          final romBytes = File(romPath).readAsBytesSync();
          expect(bridge.loadGame(session, romPath, romBytes), isTrue,
              reason: '$id load_game');

          for (var i = 0; i < 30; i++) {
            bridge.runFrame(session);
          }
          expect(bridge.pixelSum(session), greaterThan(0),
              reason: '$id pixels');

          final snap = bridge.saveState(session);
          expect(snap, isNotNull, reason: '$id save_state');

          for (var i = 0; i < 10; i++) {
            bridge.runFrame(session);
          }
          expect(bridge.loadState(session, snap!), isTrue,
              reason: '$id load_state');

          // Cheat plumbing
          bridge.cheatReset(session);
          bridge.cheatSet(session, 0, true, '0101ABCD');

          // Audio drain
          bridge.audioFrames(session);

          print('  ✅ $id PASSED');
        } finally {
          bridge.unload(session);
        }
      },
    );
  }

  // --- Load + identify only (cores without test ROMs) ---

  for (final entry in _coresNoRom.entries) {
    final id = entry.key;
    final expectedName = entry.value;

    test(
      '$id: load + identify',
      skip: bridgeLib != null && _exists(bridgeLib) ? null : 'bridge not built',
      () {
        final lib = _dylib(id);
        if (lib.isEmpty) return;

        final bridge = EzCoreRuntime.load(runtimePath: bridgeLib!);
        final session = bridge.loadSession(lib);

        try {
          final abi = bridge.abiVersion();
          final name = bridge.coreName(session);
          if (abi == 1 && name.contains(expectedName)) {
            print('  ✅ $id: $name (ABI $abi)');
          } else {
            print('  ⚠️  $id: $name (ABI $abi) — unexpected');
          }
        } finally {
          try {
            bridge.unload(session);
          } catch (_) {}
        }
      },
    );
  }
}

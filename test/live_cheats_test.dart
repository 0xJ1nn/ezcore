import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/emu/emulation_worker.dart';
import 'package:ezcore/models/cheat.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/state/app_state.dart';
import 'test_paths.dart' as paths;

void main() {
  test('multi-line editor codes join with + for cheat_set', () {
    expect(joinCheatCode('ABCD-EFGH'), 'ABCD-EFGH');
    expect(joinCheatCode('  AAAA\nBBBB\n'), 'AAAA+BBBB');
    expect(joinCheatCode('\n  \n'), isEmpty);
    expect(joinCheatCode('A\n\nB\n C '), 'A+B+C');
  });

  test('worker applies cheats without breaking the session', () async {
    final worker = EmulationWorker();
    final dir = await Directory.systemTemp.createTemp('ezcore_worker_cheats');
    final bridge = paths.bridgeLib();
    final synth = paths.synthLib();
    if (bridge == null || synth == null) {
      markTestSkipped('runtime/synth core not built');
      return;
    }
    try {
      await worker.open(
        runtimeRef: {'kind': 'path', 'path': File(bridge).absolute.path},
        corePath: File(synth).absolute.path,
        contentPath: '/dev/null', systemDir: dir.path, saveDir: dir.path,
      );
      expect(await worker.applyCheats([]), isEmpty);
      final rejected = await worker.applyCheats([
        [0, true, joinCheatCode('AAAA\nBBBB')],
      ]);
      expect(rejected, isA<List<int>>());
      // Session still steps frames afterwards.
      expect(await worker.frame(), isNotNull);
    } finally {
      await worker.close();
      await dir.delete(recursive: true);
    }
  });

  test('state count updates the matching game entry', () async {
    final state = AppState.ephemeral();
    state.games = const [
      GameEntry(
        id: 'g1',
        title: 'Dump',
        system: 'gba',
        filePath: '/tmp/dump.gba',
        extension: 'gba',
      ),
    ];
    state.setStateCount('g1', 3);
    expect(state.games.single.stateCount, 3);
    state.setStateCount('missing', 9);
    expect(state.games.single.stateCount, 3);
    state.dispose();
  });
}

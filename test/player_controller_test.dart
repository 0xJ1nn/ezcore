import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/emu/player_controller.dart';
import 'package:ezcore/emu/pcm_output.dart';
import 'package:ezcore/state/app_state.dart';
import 'test_paths.dart' as paths;

class RecordingAudio implements PcmOutput {
  int bytes = 0;
  @override
  String get sinkName => 'test sink';
  @override
  Future<void> start(double rate) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> write(Uint8List pcm) async {
    bytes += pcm.length;
  }
}

void main() {
  test('player controller displays frames, pauses, saves and closes', () async {
    final state = AppState.ephemeral();
    final audio = RecordingAudio();
    final player = PlayerController(audio: audio);
    final dir = await Directory.systemTemp.createTemp('ezcore_player');
    final bridge = paths.bridgeLib();
    final synth = paths.synthLib();
    if (bridge == null || synth == null) {
      markTestSkipped('runtime/synth core not built');
      return;
    }
    try {
      await player.open(
        runtimeRef: {'kind': 'path', 'path': File(bridge).absolute.path},
        corePath: File(synth).absolute.path,
        contentPath: '/dev/null',
        systemDir: dir.path,
        saveDir: dir.path,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      for (var i = 0; i < 100 && player.frame == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(player.frame, isNotNull);
      expect(audio.bytes, greaterThan(0));
      await player.setPaused(true);
      final frame = player.frame;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(identical(frame, player.frame), isTrue);
      await player.save(state.saves, 'fixture', 'slot0');
      expect(await state.saves.download('fixture', 'slot0'), isNotEmpty);
      await player.restore(state.saves, 'fixture', 'slot0');
      await player.setPaused(false);
    } finally {
      await player.close();
      player.dispose();
      state.dispose();
      await dir.delete(recursive: true);
    }
  });
}

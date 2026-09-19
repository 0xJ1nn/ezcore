import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/emu/player_controller.dart';
import 'package:ezcore/emu/pcm_output.dart';
import 'test_paths.dart' as paths;

class SilentAudio implements PcmOutput {
  @override
  String get sinkName => 'test sink';
  @override
  Future<void> start(double rate) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> write(_) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('controller renders real mGBA frames into ui.Image', () async {
    final player = PlayerController(audio: SilentAudio());
    final dir = await Directory.systemTemp.createTemp('ezcore_controller_mgba');
    try {
      final bridge = paths.bridgeLib();
      final core = paths.stagedCoreLib('advancebit');
      final rom = paths.fixture('test.gba');
      if (bridge == null || core == null || rom == null) {
        markTestSkipped('mGBA artifact or fixture missing');
        return;
      }
      await player.open(
        runtimeRef: {'kind': 'path', 'path': File(bridge).absolute.path},
        corePath: File(core).absolute.path,
        contentPath: File(rom).absolute.path,
        systemDir: dir.path,
        saveDir: dir.path,
      );
      for (var i = 0; i < 100 && player.frame == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(player.frame, isNotNull);
      expect(player.frame!.width, 240);
      expect(player.frame!.height, 160);
      await player.close();
      player.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

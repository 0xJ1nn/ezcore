// The user-facing promise of P6 (ADR-015): with crash protection on, a core
// that crashes mid-game ends the game — the player reports it plainly and
// stops — while the app (here, this test runner) keeps running.
import 'dart:io';
import 'dart:typed_data';

import 'package:ezcore/emu/pcm_output.dart';
import 'package:ezcore/emu/player_controller.dart';
import 'package:ezcore/emu/process_session_backend.dart';
import 'package:ezcore/services/runtime_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_paths.dart' as paths;

class _SilentAudio implements PcmOutput {
  @override
  String get sinkName => 'silent';
  @override
  Future<void> start(double rate) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> write(Uint8List pcm) async {}
}

void main() {
  final bridge = paths.bridgeLib();
  final dir = paths.runtimeBuildDir();
  final crash = dir == null
      ? null
      : File('$dir/libcrash_libretro.${paths.hostLibExt}');
  final ref = {
    'kind': 'path',
    'path': bridge == null ? null : File(bridge).absolute.path,
  };
  final host = bridge == null ? null : resolveCoreHostPath(ref);
  final skip = (host != null && crash != null && crash.existsSync())
      ? null
      : 'needs built runtime, ezcore_core_host and crash core';

  test('the host is found beside the runtime library', skip: skip, () {
    expect(host, endsWith('ezcore_core_host'));
  });

  test('a core crash ends the game with a plain message; the app lives',
      skip: skip, () async {
    final player = PlayerController(audio: _SilentAudio());
    player.useBackend(
      ProcessSessionBackend(
        hostPath: host!,
        environment: const {'EZCORE_CRASH_AFTER': '5'},
      ),
    );
    final tmp = await Directory.systemTemp.createTemp('ezcore_crash');
    try {
      await player.open(
        runtimeRef: ref,
        corePath: crash!.absolute.path,
        contentPath: '/dev/null',
        systemDir: tmp.path,
        saveDir: tmp.path,
      );
      for (var i = 0; i < 200 && player.error == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(player.running, isFalse);
      expect(player.error, contains('The core crashed'));
      expect(player.error, contains('only this game session ended'));
    } finally {
      await player.close();
      player.dispose();
      await tmp.delete(recursive: true);
    }
  });
}

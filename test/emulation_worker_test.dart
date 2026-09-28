import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/emu/emulation_worker.dart';
import 'test_paths.dart' as paths;

void main() {
  test(
    'worker executes native frames, pauses, saves, reloads and closes',
    () async {
      final bridge = paths.bridgeLib();
      final synth = paths.synthLib();
      if (bridge == null || synth == null) {
        markTestSkipped('runtime/synth core not built');
        return;
      }
      final worker = EmulationWorker();
      final dir = await Directory.systemTemp.createTemp('ezcore_worker');
      try {
        final info = await worker.open(
          runtimeRef: {'kind': 'path', 'path': File(bridge).absolute.path},
          corePath: File(synth).absolute.path,
          contentPath: '/dev/null',
          systemDir: dir.path,
          saveDir: dir.path,
        );
        expect(info['name'], 'ezTest Synth');
        final frame = await worker.frame();
        expect(frame!['width'], 256);
        expect((frame['rgba'] as Uint8List).sublist(0, 4), [1, 0, 0, 255]);
        expect((frame['pcm'] as Uint8List).length, greaterThan(0));
        final save = await worker.save();
        await worker.pause(true);
        expect(await worker.frame(), isNull);
        expect(await worker.save(), save);
        await worker.pause(false);
        await worker.button(0, true);
        final next = await worker.frame();
        expect(
          ByteData.sublistView(
            next!['pcm'] as Uint8List,
          ).getInt16(0, Endian.little),
          0x1001,
        );
        await worker.restore(save);
        expect(await worker.save(), save);
      } finally {
        await worker.close();
        await dir.delete(recursive: true);
      }
      await expectLater(worker.frame(), throwsStateError);
    },
  );

  test('worker exposes the core option set and applies setOption', () async {
    final bridge = paths.bridgeLib();
    final synth = paths.synthOptionsLib();
    if (bridge == null || synth == null) {
      markTestSkipped('runtime/synth_options core not built');
      return;
    }
    final worker = EmulationWorker();
    final dir = await Directory.systemTemp.createTemp('ezcore_worker_options');
    try {
      await worker.open(
        runtimeRef: {'kind': 'path', 'path': File(bridge).absolute.path},
        corePath: File(synth).absolute.path,
        contentPath: '/dev/null',
        systemDir: dir.path,
        saveDir: dir.path,
      );
      final options = await worker.coreOptions();
      expect(
        options.map((o) => o['key']),
        containsAll(['test_region', 'test_frameskip']),
      );
      expect(
        options.firstWhere((o) => o['key'] == 'test_region')['default'],
        'auto',
      );
      // Set through the isolate, read back through it: the full protocol
      // round trip, not just a direct call.
      expect(await worker.setCoreOption('test_region', 'ntsc-u'), isTrue);
      final after = await worker.coreOptions();
      expect(
        after.firstWhere((o) => o['key'] == 'test_region')['value'],
        'ntsc-u',
      );
      // Unknown keys are user data: false, never a throw.
      expect(await worker.setCoreOption('not_a_key', 'x'), isFalse);
    } finally {
      await worker.close();
      await dir.delete(recursive: true);
    }
  });

  test(
    'worker boots existing mGBA test content and returns opaque video',
    () async {
      final worker = EmulationWorker();
      final dir = await Directory.systemTemp.createTemp('ezcore_worker_mgba');
      try {
        final bridge = paths.bridgeLib();
        final core = paths.stagedCoreLib('advancebit');
        final rom = paths.fixture('test.gba');
        if (bridge == null || core == null || rom == null) {
          markTestSkipped('mGBA artifact or fixture missing');
          return;
        }
        await worker.open(
          runtimeRef: {'kind': 'path', 'path': File(bridge).absolute.path},
          corePath: File(core).absolute.path,
          contentPath: File(rom).absolute.path,
          systemDir: dir.path,
          saveDir: dir.path,
        );
        final frame = await worker.frame();
        expect(frame!['width'], 240);
        expect(frame['height'], 160);
        expect((frame['rgba'] as Uint8List)[3], 255);
        final save = await worker.save();
        expect(save.length, greaterThan(0));
        await worker.frame();
        await worker.restore(save);
      } finally {
        await worker.close();
        await dir.delete(recursive: true);
      }
    },
  );
}

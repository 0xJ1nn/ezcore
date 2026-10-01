// P3: analog sticks, mouse, keyboard and pointer reach a core through both
// ways ezCORE runs one — the in-process service and the crash-protected
// helper process. The synth_input core echoes what it read into audio, one
// value per sample (see runtime/test/synth_core/synth_input_core.c).
import 'dart:io';
import 'dart:typed_data';

import 'package:ezcore/emu/emulation_service.dart';
import 'package:ezcore/emu/process_session_backend.dart';
import 'package:ezcore/runtime/ezcore_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_paths.dart' as paths;

const retrokA = 97;
const mouseLeft = 2;

List<int> samples(Uint8List pcm) {
  final d = ByteData.sublistView(pcm);
  return [for (var i = 0; i + 1 < pcm.length && i < 32; i += 2) d.getInt16(i, Endian.little)];
}

void main() {
  final dir = paths.runtimeBuildDir();
  String? art(String n) {
    if (dir == null) return null;
    final f = File('$dir/$n');
    return f.existsSync() ? f.absolute.path : null;
  }

  final bridge = paths.bridgeLib();
  final synth = art('libsynth_input_libretro.${paths.hostLibExt}');
  final host = art(Platform.isWindows ? 'ezcore_core_host.exe' : 'ezcore_core_host');
  final skip = bridge != null && synth != null ? null : 'needs runtime + synth_input core';

  test('in-process: every device reaches the core', skip: skip, () async {
    final s = EmulationService(runtime: EzCoreRuntime.load(runtimePath: bridge!));
    await s.start(corePath: synth!, romPath: '/dev/null', rom: Uint8List(0));
    try {
      s.setAnalog(0, 0, 0, 12000);
      s.mouseMove(5, -3);
      s.setMouseButton(mouseLeft, true);
      s.setKey(retrokA, true, character: 0x61);
      s.setPointer(-100, 200, true);
      s.runFrame();
      final out = BytesBuilder();
      s.drainAudio(s.audioPending, out);
      final v = samples(out.takeBytes());
      expect(v[0], 12000, reason: 'left stick x');
      expect([v[4], v[5]], [5, -3], reason: 'mouse delta');
      expect(v[6], 1, reason: 'mouse left');
      expect(v[7], 1, reason: 'key a polled');
      expect([v[11], v[12]], [1, retrokA], reason: 'keyboard callback');
      expect([v[8], v[9], v[10]], [-100, 200, 1], reason: 'pointer');
    } finally {
      s.close();
    }
  });

  test('crash-protected helper: every device reaches the core',
      skip: skip ?? (host == null ? 'needs ezcore_core_host' : null), () async {
    final b = ProcessSessionBackend(hostPath: host!);
    await b.open(
      runtimeRef: const {},
      corePath: synth!,
      contentPath: '/dev/null',
      systemDir: Directory.systemTemp.path,
      saveDir: Directory.systemTemp.path,
    );
    try {
      await b.analog(1, 1, 0, 500);
      await b.mouseMove(-7, 9);
      await b.key(retrokA, true);
      await b.pointer(32767, -32767, true);
      final v = samples((await b.frame())!['pcm'] as Uint8List);
      expect(v[2], 500, reason: 'right stick on port 1');
      expect([v[4], v[5]], [-7, 9]);
      expect(v[7], 1);
      expect([v[8], v[9], v[10]], [32767, -32767, 1]);
    } finally {
      await b.close();
    }
  });
}

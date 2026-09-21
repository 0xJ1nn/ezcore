import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/runtime/ezcore_runtime.dart';
import 'test_paths.dart' as paths;

void main() {
  test(
    'copied frame is RGBA with opaque alpha, not native XRGB bytes',
    skip: paths.synthLib() != null ? null : 'synth core not built',
    () {
    final rt = EzCoreRuntime.load(runtimePath: paths.bridgeLib()!);
    final s = rt.loadSession(paths.synthLib()!);
    try {
      expect(rt.init(s), isTrue);
      expect(rt.loadGame(s, '', Uint8List(0)), isTrue);
      rt.runFrame(s);
      expect(rt.frameBytes(s)!.sublist(0, 4), [1, 0, 0, 255]);
    } finally { rt.unload(s); }
    },
  );
}

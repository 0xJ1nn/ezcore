import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/emu/pcm_linux.dart';
import 'package:ezcore/emu/pcm_output.dart';
import 'package:ezcore/emu/pcm_windows.dart';

void main() {
  test('factory resolves a named sink for the host', () {
    final sink = createPlatformPcm();
    expect(sink, isA<PcmOutput>());
    expect(sink.sinkName, isNotEmpty);
  });

  test('desktop sinks carry their platform labels', () {
    expect(AlsaPcmOutput().sinkName, 'ALSA (Linux)');
    expect(WinmmPcmOutput().sinkName, 'waveOut (Windows)');
    expect(PlatformPcmOutput().sinkName, isNotEmpty);
  });

  test('desktop sinks reject bad rates before touching native libs',
      () async {
    await expectLater(
        AlsaPcmOutput().start(1.0), throwsA(isA<ArgumentError>()));
    await expectLater(
        WinmmPcmOutput().start(double.nan), throwsA(isA<ArgumentError>()));
    await expectLater(
        AlsaPcmOutput().write(Uint8List(0)), throwsStateError);
  });
}

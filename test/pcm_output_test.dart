import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/emu/pcm_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PCM output configures, queues stereo data and flushes on stop', () async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('ezcore/audio');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async { calls.add(call); return null; });
    final output = PlatformPcmOutput();
    await output.start(32768);
    await output.write(Uint8List(16));
    await output.stop();
    expect(calls.map((c) => c.method), ['start', 'write', 'stop']);
    expect((calls.first.arguments as Map)['sampleRate'], 32768);
    expect(calls[1].arguments, hasLength(16));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}

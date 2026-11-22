// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'package:ezcore/emu/pcm_output.dart';
import 'package:ezcore/services/haptics.dart';
import 'package:ezcore/services/ui_sounds.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _PhoneRecorder implements PhoneHaptics {
  final impacts = <PhoneImpact>[];

  @override
  Future<void> impact(PhoneImpact impact) async => impacts.add(impact);
}

class _FakeOutput implements PcmOutput {
  @override
  Future<void> start(double sampleRate) async {}

  @override
  Future<void> write(Uint8List stereoS16) async {}

  @override
  Future<void> stop() async {}

  @override
  String get sinkName => 'Fake';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(List<MethodCall>, _PhoneRecorder, Haptics)> setup() async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('ezcore/gamepad');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    final phone = _PhoneRecorder();
    final haptics = Haptics(channel: channel, phone: phone);
    return (calls, phone, haptics);
  }

  test('every cue has the measured rumble and phone impact', () {
    final move = uiHaptics[UiCue.move]!;
    expect(move.rumble!.weak, 0.12);
    expect(move.rumble!.durationMs, 14);
    expect(move.impact, PhoneImpact.light);

    final select = uiHaptics[UiCue.select]!;
    expect(select.rumble!.weak, 0.35);
    expect(select.rumble!.strong, 0.1);
    expect(select.rumble!.durationMs, 26);
    expect(select.impact, PhoneImpact.medium);

    expect(uiHaptics[UiCue.back]!.rumble!.weak, 0.25);
    expect(uiHaptics[UiCue.edge]!.rumble!.strong, 0.35);
    expect(uiHaptics[UiCue.edge]!.rumble!.durationMs, 40);
    expect(uiHaptics[UiCue.toggle]!.rumble!.weak, 0.3);

    final launch = uiHaptics[UiCue.launch]!;
    expect(launch.rumble!.strong, 0.8);
    expect(launch.rumble!.rampTo, 0.8);
    expect(launch.rumble!.durationMs, 260);
    expect(launch.impact, PhoneImpact.heavy);

    final save = uiHaptics[UiCue.save]!;
    expect(save.rumble!.weak, 0.4);
    expect(save.rumble!.strong, 0.5);
    expect(save.rumble!.durationMs, 70);

    expect(uiHaptics[UiCue.error]!.rumble!.strong, 0.9);
    expect(uiHaptics[UiCue.error]!.rumble!.durationMs, 140);
    expect(uiHaptics[UiCue.error]!.impact, PhoneImpact.heavy);

    expect(uiHaptics[UiCue.toast]!.rumble, isNull);
    expect(uiHaptics[UiCue.toast]!.impact, isNull);
  });

  test(
    'a cue rumbles the pad and taps the phone with its own strengths',
    () async {
      final (calls, phone, haptics) = await setup();
      expect(await haptics.play(UiCue.move), isTrue);
      expect(calls.single.method, 'rumble');
      expect(calls.single.arguments, {
        'weak': 0.12,
        'strong': 0.0,
        'durationMs': 14,
      });
      expect(phone.impacts, [PhoneImpact.light]);

      expect(await haptics.play(UiCue.toast), isFalse);
      expect(calls.length, 1);
      expect(phone.impacts.length, 1);
    },
  );

  test('the Haptics preference silences rumble and impact', () async {
    final (calls, phone, haptics) = await setup();
    haptics.sync({'haptics': false});
    expect(await haptics.play(UiCue.error), isFalse);
    expect(calls, isEmpty);
    expect(phone.impacts, isEmpty);
  });

  test('one cue event drives sound and haptics together', () async {
    final (calls, phone, haptics) = await setup();
    final sounds = UiSounds(output: _FakeOutput(), gameRunning: () => false);
    haptics.attachTo(sounds);

    expect(await sounds.play(UiCue.select), isTrue);
    // The stream listener is async; give the haptic future a frame.
    await Future<void>.delayed(Duration.zero);
    expect(calls.single.method, 'rumble');
    expect(phone.impacts, [PhoneImpact.medium]);

    // Muting the audio half still leaves haptics to their own preference.
    sounds.configure(muted: true);
    await sounds.play(UiCue.save);
    await Future<void>.delayed(Duration.zero);
    expect(phone.impacts, [PhoneImpact.medium, PhoneImpact.medium]);
    haptics.detach();
  });
}

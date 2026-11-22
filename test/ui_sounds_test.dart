// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:typed_data';

import 'package:ezcore/emu/pcm_output.dart';
import 'package:ezcore/services/ui_sounds.dart';
import 'package:ezcore/widgets/pad_navigator.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Recorder implements PcmOutput {
  final calls = <String>[];
  Uint8List? written;

  @override
  Future<void> start(double sampleRate) async {
    calls.add('start:${sampleRate.round()}');
  }

  @override
  Future<void> write(Uint8List stereoS16) async {
    calls.add('write');
    written = stereoS16;
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  String get sinkName => 'Test sink';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the cue table carries the measured frequencies and durations', () {
    final move = uiCueSpec(UiCue.move);
    expect(move.tones.single.frequency, 1760);
    expect(move.tones.single.duration, 0.035);
    expect(move.tones.single.gain, 0.05);
    expect(move.tones.single.waveform, UiWaveform.sine);

    final select = uiCueSpec(UiCue.select);
    expect(select.tones.map((t) => t.frequency), [880, 1320]);
    expect(select.tones.map((t) => t.duration), [0.07, 0.09]);
    expect(
      select.tones.every((t) => t.waveform == UiWaveform.triangle),
      isTrue,
    );

    final back = uiCueSpec(UiCue.back);
    expect(back.tones.map((t) => t.frequency), [990, 660]);

    final edge = uiCueSpec(UiCue.edge);
    expect(edge.tones.single.frequency, 240);
    expect(edge.tones.single.endFrequency, 180);
    expect(edge.tones.single.duration, 0.06);

    final toggle = uiCueSpec(UiCue.toggle);
    expect(toggle.tones.map((t) => t.frequency), [1000, 1400]);
    expect(toggle.tones.map((t) => t.delay), [0, 0.05]);

    final launch = uiCueSpec(UiCue.launch);
    expect(launch.noises.single.highpassHz, 800);
    expect(launch.noises.single.duration, 0.6);
    expect(launch.tones.map((t) => t.frequency), [440, 554, 659, 880]);
    expect(
      launch.tones.every((t) => t.endFrequency == t.frequency * 1.5),
      isTrue,
    );

    final save = uiCueSpec(UiCue.save);
    expect(save.noises.single.highpassHz, 3000);
    expect(save.noises.single.duration, 0.05);
    expect(save.tones.map((t) => t.frequency), [1568, 2093]);

    final error = uiCueSpec(UiCue.error);
    expect(error.tones.map((t) => t.frequency), [196, 185]);
    expect(error.tones.every((t) => t.waveform == UiWaveform.square), isTrue);

    expect(uiCueSpec(UiCue.toast).tones.single.frequency, 1046);
    expect(uiCueSpec(UiCue.toast).tones.single.duration, 0.12);
    expect(uiCueSpecs.length, UiCue.values.length);
  });

  test('switching off reverses the 1000/1400 pair', () {
    expect(uiToggleSpec(true).tones.map((t) => t.frequency), [1000, 1400]);
    expect(uiToggleSpec(false).tones.map((t) => t.frequency), [1400, 1000]);
  });

  test('synthesis is deterministic, non-silent and length-matched', () {
    final samples = UiSoundSynth.samples(UiCue.move);
    final again = UiSoundSynth.samples(UiCue.move);
    expect(samples.length, again.length);
    expect(
      samples.length,
      (uiCueSpec(UiCue.move).duration * UiSoundSynth.sampleRate).ceil() + 1,
    );
    expect(samples.any((s) => s.abs() > 0.01), isTrue);
    for (var i = 0; i < samples.length; i++) {
      expect(samples[i], again[i]);
    }
    expect(samples.every((s) => s >= -1 && s <= 1), isTrue);

    final pcm = UiSoundSynth.pcm(UiCue.move);
    expect(pcm.length, samples.length * 4);
    final data = ByteData.sublistView(pcm);
    final offset = (samples.length * 0.25).round() * 4;
    expect(
      data.getInt16(offset, Endian.little),
      data.getInt16(offset + 2, Endian.little),
    );
    expect(data.getInt16(offset, Endian.little).abs(), greaterThan(0));
  });

  test('a cue is synthesised, written to the PCM sink and published', () async {
    final sink = _Recorder();
    final sounds = UiSounds(output: sink, gameRunning: () => false);
    final received = <UiCue>[];
    sounds.events.listen((event) => received.add(event.cue));

    expect(await sounds.play(UiCue.select), isTrue);
    expect(sink.calls, ['start:44100', 'write', 'stop']);
    expect(received, [UiCue.select]);
    expect(sink.written, isNotNull);

    // A fresh play reaches the sink again; cues are not one-shot.
    expect(await sounds.play(UiCue.toast), isTrue);
    expect(sink.calls.where((c) => c == 'write').length, 2);
  });

  test('UI sounds, Mute and a running game each gate playback', () async {
    final sink = _Recorder();
    final sounds = UiSounds(output: sink, gameRunning: () => false);

    sounds.configure(enabled: false);
    expect(await sounds.play(UiCue.move), isFalse);
    expect(sink.calls, isEmpty);

    sounds.configure(enabled: true, muted: true);
    expect(await sounds.play(UiCue.move), isFalse);
    expect(sink.calls, isEmpty);

    sounds.configure(muted: false);
    expect(await sounds.play(UiCue.move, gameRunning: true), isFalse);
    expect(sink.calls, isEmpty);

    expect(await sounds.play(UiCue.move), isTrue);
    expect(sink.calls, isNotEmpty);
  });

  test(
    'the shared focus owner feeds move and edge cues to the bridge',
    () async {
      final sounds = UiSounds(output: _Recorder(), gameRunning: () => false);
      final cues = <UiCue>[];
      sounds.events.listen((event) => cues.add(event.cue));
      sounds.attachGlobalBridge();

      FocusOwner.shared.edge.value = const EdgeSignal(
        'test-row',
        TraversalDirection.right,
        987654,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cues, contains(UiCue.edge));

      sounds.detachGlobalBridge();
      FocusOwner.shared.edge.value = null;
    },
  );

  test('settings sync maps the persisted preferences to the gates', () {
    final sounds = UiSounds(gameRunning: () => false);
    sounds.sync({'uiSounds': false, 'muted': true});
    expect(sounds.enabled, isFalse);
    expect(sounds.muted, isTrue);
    sounds.sync({'uiSounds': true, 'muted': false});
    expect(sounds.enabled, isTrue);
    expect(sounds.muted, isFalse);
  });
}

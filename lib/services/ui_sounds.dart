import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../emu/pcm_output.dart';
import '../services/gamepad.dart' show GamepadService;
import '../widgets/pad_navigator.dart' show FocusOwner, padNavigationEnabled;

/// Every interface cue named in the sound table (handoff §6).
///
/// The enum lives with the synthesised cues so a caller cannot ask for a cue
/// that has no definition. Haptics reuse the same names, so one event drives
/// both halves of the feedback.
enum UiCue { move, select, back, edge, toggle, launch, save, error, toast }

/// Oscillator shapes used by the cue table.
enum UiWaveform { sine, triangle, square }

/// A single oscillator in a cue. All times are seconds.
@immutable
class UiTone {
  const UiTone(
    this.frequency, {
    this.endFrequency = 0,
    this.duration = 0.1,
    this.gain = 0.05,
    this.delay = 0,
    this.waveform = UiWaveform.sine,
  });

  final double frequency;
  final double endFrequency;
  final double duration;
  final double gain;
  final double delay;
  final UiWaveform waveform;

  UiTone withDelay(double seconds) => UiTone(
    frequency,
    endFrequency: endFrequency,
    duration: duration,
    gain: gain,
    delay: seconds,
    waveform: waveform,
  );
}

/// A burst of high-passed noise (the shutter click and the launch swell).
@immutable
class UiNoise {
  const UiNoise({
    required this.duration,
    required this.gain,
    required this.highpassHz,
    this.delay = 0,
  });

  final double duration;
  final double gain;
  final double highpassHz;
  final double delay;
}

/// The complete, declarative definition of one cue.
@immutable
class UiCueSpec {
  const UiCueSpec(this.name, {this.tones = const [], this.noises = const []});

  final String name;
  final List<UiTone> tones;
  final List<UiNoise> noises;

  /// Longest tail, measured from the start of the cue.
  double get duration {
    var end = 0.0;
    for (final t in tones) {
      end = math.max(end, t.delay + t.duration);
    }
    for (final n in noises) {
      end = math.max(end, n.delay + n.duration);
    }
    return end;
  }
}

/// The measured table. No cue loads or ships an audio file: every sample is
/// generated from these numbers at play time.
const _launchChord = [440.0, 554.0, 659.0, 880.0];

final uiCueSpecs = <UiCue, UiCueSpec>{
  UiCue.move: UiCueSpec(
    'move',
    tones: [UiTone(1760, duration: 0.035, gain: 0.05)],
  ),
  UiCue.select: UiCueSpec(
    'select',
    tones: [
      UiTone(880, duration: 0.07, gain: 0.07, waveform: UiWaveform.triangle),
      UiTone(
        1320,
        duration: 0.09,
        gain: 0.06,
        delay: 0.05,
        waveform: UiWaveform.triangle,
      ),
    ],
  ),
  UiCue.back: UiCueSpec(
    'back',
    tones: [
      UiTone(990, duration: 0.06, gain: 0.06, waveform: UiWaveform.triangle),
      UiTone(
        660,
        duration: 0.08,
        gain: 0.05,
        delay: 0.045,
        waveform: UiWaveform.triangle,
      ),
    ],
  ),
  UiCue.edge: UiCueSpec(
    'edge',
    tones: [UiTone(240, endFrequency: 180, duration: 0.06, gain: 0.08)],
  ),
  UiCue.toggle: UiCueSpec(
    'toggle',
    tones: [
      UiTone(1000, duration: 0.04, gain: 0.05),
      UiTone(1400, duration: 0.04, gain: 0.05, delay: 0.05),
    ],
  ),
  UiCue.launch: UiCueSpec(
    'launch',
    noises: [UiNoise(duration: 0.6, gain: 0.06, highpassHz: 800)],
    tones: [
      for (var i = 0; i < _launchChord.length; i++)
        UiTone(
          _launchChord[i],
          endFrequency: _launchChord[i] * 1.5,
          duration: 0.7,
          gain: 0.05,
          delay: 0.08 + i * 0.06,
        ),
    ],
  ),
  UiCue.save: UiCueSpec(
    'save',
    noises: [UiNoise(duration: 0.05, gain: 0.14, highpassHz: 3000)],
    tones: [
      UiTone(1568, duration: 0.35, gain: 0.06, delay: 0.06),
      UiTone(2093, duration: 0.4, gain: 0.035, delay: 0.12),
    ],
  ),
  UiCue.error: UiCueSpec(
    'error',
    tones: [
      UiTone(196, duration: 0.12, gain: 0.04, waveform: UiWaveform.square),
      UiTone(
        185,
        duration: 0.14,
        gain: 0.04,
        delay: 0.14,
        waveform: UiWaveform.square,
      ),
    ],
  ),
  UiCue.toast: UiCueSpec(
    'toast',
    tones: [UiTone(1046, duration: 0.12, gain: 0.045)],
  ),
};

/// The table definition for [cue].
UiCueSpec uiCueSpec(UiCue cue) => uiCueSpecs[cue]!;

/// The switch-off cue is the same 1000 → 1400 Hz pair played in reverse.
UiCueSpec uiToggleSpec(bool on) {
  final spec = uiCueSpec(UiCue.toggle);
  if (on) return spec;
  return UiCueSpec(
    spec.name,
    tones: [spec.tones[1].withDelay(0), spec.tones[0].withDelay(0.05)],
  );
}

/// Renders a cue to signed 16-bit little-endian stereo PCM.
///
/// Deterministic on purpose: the noise uses a fixed seed, so a test can compare
/// the rendered buffer with the same cue rendered again. Cues sit an octave
/// above game audio and are mixed in memory — nothing is read from disk.
class UiSoundSynth {
  UiSoundSynth._();

  static const int sampleRate = 44100;

  /// Mono samples in [-1, 1]. Exposed so tests can inspect the waveform.
  static Float64List samples(UiCue cue, {bool reverse = false}) {
    final spec = cue == UiCue.toggle ? uiToggleSpec(!reverse) : uiCueSpec(cue);
    final length = math.max(1, (spec.duration * sampleRate).ceil() + 1);
    final mix = Float64List(length);

    for (final tone in spec.tones) {
      final start = (tone.delay * sampleRate).round();
      var phase = 0.0;
      for (
        var i = 0;
        i < tone.duration * sampleRate && start + i < length;
        i++
      ) {
        final t = i / sampleRate;
        final progress = (t / tone.duration).clamp(0.0, 1.0);
        final frequency =
            (tone.endFrequency == 0
                    ? tone.frequency
                    : tone.frequency *
                          math.pow(
                            tone.endFrequency / tone.frequency,
                            progress,
                          ))
                .toDouble();
        phase += 2 * math.pi * frequency / sampleRate;
        final wave = switch (tone.waveform) {
          UiWaveform.sine => math.sin(phase),
          UiWaveform.triangle => (2 / math.pi) * math.asin(math.sin(phase)),
          UiWaveform.square => math.sin(phase) >= 0 ? 1.0 : -1.0,
        };
        mix[start + i] +=
            wave * tone.gain * _envelope(t, tone.duration, tone.gain);
      }
    }

    for (final noise in spec.noises) {
      final start = (noise.delay * sampleRate).round();
      final count = (noise.duration * sampleRate).round();
      var state = 0x2545f491;
      var previous = 0.0;
      var filtered = 0.0;
      final alpha = 1 / (1 + 2 * math.pi * noise.highpassHz / sampleRate);
      for (var i = 0; i < count && start + i < length; i++) {
        // xorshift32 keeps the swell reproducible without a Random object.
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        final sample =
            (((state & 0xffffffff) / 0xffffffff) * 2 - 1) * (1 - i / count);
        filtered = alpha * (filtered + sample - previous);
        previous = sample;
        mix[start + i] += filtered * noise.gain;
      }
    }

    for (var i = 0; i < length; i++) {
      mix[i] = mix[i].clamp(-1.0, 1.0);
    }
    return mix;
  }

  /// A 5 ms attack, then the exponential tail the Web Audio reference uses.
  static double _envelope(double t, double duration, double gain) {
    final attack = math.min(0.005, duration / 2);
    if (t < attack) return t / attack;
    final remaining = duration - attack;
    if (remaining <= 0) return 1;
    return math.pow(0.0001 / gain, (t - attack) / remaining).toDouble();
  }

  /// Signed-16 stereo frames for the platform PCM sink.
  static Uint8List pcm(UiCue cue, {bool reverse = false}) {
    final samples = UiSoundSynth.samples(cue, reverse: reverse);
    final bytes = Uint8List(samples.length * 4);
    final data = ByteData.view(bytes.buffer);
    for (var i = 0; i < samples.length; i++) {
      final value = (samples[i] * 32767).round().clamp(-32768, 32767);
      data.setInt16(i * 4, value, Endian.little);
      data.setInt16(i * 4 + 2, value, Endian.little);
    }
    return bytes;
  }
}

/// What a cue event carries to the haptics listener.
@immutable
class UiCueEvent {
  const UiCueEvent(this.cue, {this.reverse = false});

  final UiCue cue;
  final bool reverse;
}

/// Plays the synthesised cues and owns the three gates around them: the
/// "UI sounds" preference, Mute, and a running game (§6: cues never play over
/// a game). Failures are swallowed: an unavailable audio sink must never
/// break a tap.
class UiSounds {
  UiSounds({this.output, bool Function()? gameRunning})
    : _gameRunning = gameRunning ?? _defaultGameRunning;

  static final UiSounds shared = UiSounds();

  static bool _defaultGameRunning() => !padNavigationEnabled.value;

  /// Injectable sink; null uses the platform PCM output lazily.
  final PcmOutput? output;
  final bool Function() _gameRunning;
  PcmOutput? _createdOutput;
  Future<void> _tail = Future.value();

  bool _enabled = true;
  bool _muted = false;
  bool _bridgeAttached = false;
  FocusNode? _lastFocus;
  int _lastEdge = 0;
  void Function()? _cancelPad;

  final StreamController<UiCueEvent> _events =
      StreamController<UiCueEvent>.broadcast();

  /// One cue per accepted play, so haptics can follow the same names without
  /// a second set of call sites.
  Stream<UiCueEvent> get events => _events.stream;

  bool get enabled => _enabled;
  bool get muted => _muted;

  /// Reconciles with the Audio preferences.
  void sync(Map<String, dynamic> settings) {
    _enabled = settings['uiSounds'] != false;
    _muted = settings['muted'] == true;
  }

  /// Test hook and explicit override; [sync] is the normal path.
  void configure({bool? enabled, bool? muted}) {
    if (enabled != null) _enabled = enabled;
    if (muted != null) _muted = muted;
  }

  /// Plays [cue] when the gates allow it. Returns true when audio was sent.
  ///
  /// The `reverse` flag plays the toggle cue off instead of on. Pass
  /// [gameRunning] to override the default player-state probe in tests.
  Future<bool> play(
    UiCue cue, {
    bool reverse = false,
    bool? gameRunning,
  }) async {
    // A running game owns both the audio device and the controller: no cue
    // from the menus is allowed to break through. Haptics follow the same
    // event, so they are gated here too.
    if (gameRunning ?? _gameRunning()) return false;
    _events.add(UiCueEvent(cue, reverse: reverse));
    // UI sounds off or Mute silences only the audio half; the haptics
    // preference is independent and still gets its own event.
    if (!_enabled || _muted) return false;

    final sink = output ?? (_createdOutput ??= createPlatformPcm());
    final pcm = UiSoundSynth.pcm(cue, reverse: reverse);
    final next = _tail.then((_) async {
      await sink.start(UiSoundSynth.sampleRate.toDouble());
      await sink.write(pcm);
      await sink.stop();
    });
    // Serialise cues: two fast focus moves must not fight over one PCM sink.
    _tail = next.catchError((_) {});
    try {
      await next;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Wires the cues that come from the shared focus owner and pad. Idempotent,
  /// because the shell and Settings can both ask for it.
  void attachGlobalBridge() {
    if (_bridgeAttached) return;
    _bridgeAttached = true;
    FocusOwner.shared.addListener(_onFocusChanged);
    FocusOwner.shared.edge.addListener(_onEdge);
    _cancelPad = GamepadService.shared.onButton((event) {
      if (!event.pressed) return;
      if (event.code == 'a' || event.code == 'start') {
        unawaited(play(UiCue.select));
      } else if (event.code == 'b') {
        unawaited(play(UiCue.back));
      }
    });
  }

  void _onFocusChanged() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || identical(focus, _lastFocus)) return;
    _lastFocus = focus;
    unawaited(play(UiCue.move));
  }

  void _onEdge() {
    final sequence = FocusOwner.shared.edge.value?.sequence ?? 0;
    if (sequence == 0 || sequence == _lastEdge) return;
    _lastEdge = sequence;
    unawaited(play(UiCue.edge));
  }

  /// Test-only: detaches the global listeners so singleton state cannot leak.
  void detachGlobalBridge() {
    if (!_bridgeAttached) return;
    _bridgeAttached = false;
    FocusOwner.shared.removeListener(_onFocusChanged);
    FocusOwner.shared.edge.removeListener(_onEdge);
    _cancelPad?.call();
    _cancelPad = null;
    _lastFocus = null;
    _lastEdge = 0;
  }
}

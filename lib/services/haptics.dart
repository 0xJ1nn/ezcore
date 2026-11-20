import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ui_sounds.dart';

/// Phone impact strengths the platform exposes (§6).
enum PhoneImpact { light, medium, heavy }

/// A pad motor pattern. Both motors are 0..1; [rampTo] is the launch swell.
@immutable
class RumbleSpec {
  const RumbleSpec({
    this.weak = 0,
    this.strong = 0,
    required this.durationMs,
    this.rampTo,
  });

  final double weak;
  final double strong;
  final int durationMs;
  final double? rampTo;

  Map<String, Object> toChannel() => {
    'weak': weak,
    'strong': strong,
    'durationMs': durationMs,
    'rampTo': ?rampTo,
  };
}

/// Both halves of one cue's feedback. A missing motor or impact means the
/// platform has no equivalent; the other half still fires.
@immutable
class HapticSpec {
  const HapticSpec({this.rumble, this.impact});

  final RumbleSpec? rumble;
  final PhoneImpact? impact;
}

/// The pad-rumble and phone-impact table, keyed by the same names as sound.
const uiHaptics = <UiCue, HapticSpec>{
  UiCue.move: HapticSpec(
    rumble: RumbleSpec(weak: 0.12, durationMs: 14),
    impact: PhoneImpact.light,
  ),
  UiCue.select: HapticSpec(
    rumble: RumbleSpec(weak: 0.35, strong: 0.1, durationMs: 26),
    impact: PhoneImpact.medium,
  ),
  UiCue.back: HapticSpec(
    rumble: RumbleSpec(weak: 0.25, durationMs: 22),
    impact: PhoneImpact.light,
  ),
  UiCue.edge: HapticSpec(
    rumble: RumbleSpec(strong: 0.35, durationMs: 40),
    impact: PhoneImpact.medium,
  ),
  UiCue.toggle: HapticSpec(
    rumble: RumbleSpec(weak: 0.3, durationMs: 20),
    impact: PhoneImpact.light,
  ),
  UiCue.launch: HapticSpec(
    rumble: RumbleSpec(strong: 0.8, durationMs: 260, rampTo: 0.8),
    impact: PhoneImpact.heavy,
  ),
  UiCue.save: HapticSpec(
    rumble: RumbleSpec(weak: 0.4, strong: 0.5, durationMs: 70),
    impact: PhoneImpact.medium,
  ),
  UiCue.error: HapticSpec(
    rumble: RumbleSpec(strong: 0.9, durationMs: 140),
    impact: PhoneImpact.heavy,
  ),
  // The toast cue deliberately has no rumble or impact.
  UiCue.toast: HapticSpec(),
};

/// Indirection so tests can record impacts without a platform channel.
abstract interface class PhoneHaptics {
  const PhoneHaptics();

  Future<void> impact(PhoneImpact impact);
}

class SystemPhoneHaptics implements PhoneHaptics {
  const SystemPhoneHaptics();

  @override
  Future<void> impact(PhoneImpact impact) async {
    try {
      switch (impact) {
        case PhoneImpact.light:
          await HapticFeedback.lightImpact();
        case PhoneImpact.medium:
          await HapticFeedback.mediumImpact();
        case PhoneImpact.heavy:
          await HapticFeedback.heavyImpact();
      }
    } on MissingPluginException {
      // Desktop has no haptics; the visible cue is unaffected.
    }
  }
}

/// Rumbles the pad and taps the phone for a cue.
///
/// Rumble travels over the existing `ezcore/gamepad` channel as a `rumble`
/// call; no new plugin or dependency is needed. Haptics listen to the same
/// [UiCueEvent] stream the sound service emits, so each cue has one call site
/// and the "Haptics" preference is the single gate.
class Haptics {
  Haptics({MethodChannel? channel, PhoneHaptics? phone, this.sounds})
    : _channel = channel ?? const MethodChannel('ezcore/gamepad'),
      _phone = phone ?? const SystemPhoneHaptics();

  static final Haptics shared = Haptics();

  final MethodChannel _channel;
  final PhoneHaptics _phone;

  /// Optional fixed cue source; defaults to [UiSounds.shared].
  final UiSounds? sounds;
  bool _enabled = true;
  bool _attached = false;
  StreamSubscription<UiCueEvent>? _subscription;

  bool get enabled => _enabled;

  /// Reconciles with the Controls preference.
  void sync(Map<String, dynamic> settings) {
    _enabled = settings['haptics'] != false;
  }

  /// Test hook and explicit override; [sync] is the normal path.
  void configure({bool? enabled}) {
    if (enabled != null) _enabled = enabled;
  }

  /// Follows the sound service's cue stream. Idempotent.
  void attachTo([UiSounds? sounds]) {
    if (_attached) return;
    _attached = true;
    final source = sounds ?? this.sounds ?? UiSounds.shared;
    _subscription = source.events.listen(_onCue);
  }

  void _onCue(UiCueEvent event) => unawaited(play(event.cue));

  /// Plays the pad/phone half of [cue]. Returns true when anything fired.
  Future<bool> play(UiCue cue) async {
    if (!_enabled) return false;
    final spec = uiHaptics[cue];
    if (spec == null) return false;
    var fired = false;
    final rumble = spec.rumble;
    if (rumble != null) {
      try {
        await _channel.invokeMethod<void>('rumble', rumble.toChannel());
        fired = true;
      } on MissingPluginException {
        // Not every platform runner exposes a rumble method yet.
      }
    }
    final impact = spec.impact;
    if (impact != null) {
      await _phone.impact(impact);
      fired = true;
    }
    return fired;
  }

  /// Test-only: stops listening so the singleton cannot leak between tests.
  void detach() {
    _subscription?.cancel();
    _subscription = null;
    _attached = false;
  }
}

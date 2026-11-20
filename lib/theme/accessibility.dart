import 'package:flutter/widgets.dart';

/// The three reduce-motion states the design offers (§5).
///
/// Unknown and legacy values are normalised to [system]: a missing preference
/// is not a fourth state, it is "Follow system". `true`/`false` are the values
/// written by older builds, so they keep working as On/Off.
enum ReducedMotion {
  system('Follow system'),
  on('On'),
  off('Off');

  const ReducedMotion(this.label);

  final String label;

  /// Resolves this preference against the OS setting.
  bool resolve(bool systemReduced) => switch (this) {
    ReducedMotion.system => systemReduced,
    ReducedMotion.on => true,
    ReducedMotion.off => false,
  };

  /// The next state when the row's switch is pressed. The switch keeps its
  /// two-position image, but a third press returns to Follow system so every
  /// state named by §5 stays reachable.
  ReducedMotion get next => switch (this) {
    ReducedMotion.system => ReducedMotion.on,
    ReducedMotion.on => ReducedMotion.off,
    ReducedMotion.off => ReducedMotion.system,
  };
}

/// Reads a persisted reduce-motion value without ever inventing a new state.
ReducedMotion normalizeReducedMotion(Object? raw) => switch (raw) {
  true => ReducedMotion.on,
  false => ReducedMotion.off,
  'on' || 'On' => ReducedMotion.on,
  'off' || 'Off' => ReducedMotion.off,
  _ => ReducedMotion.system,
};

/// Canonical token for a preference write.
Object? reducedMotionToken(ReducedMotion value) => switch (value) {
  ReducedMotion.system => null,
  ReducedMotion.on => true,
  ReducedMotion.off => false,
};

/// App-wide motion preference.
///
/// Screens outside Settings read their durations from [Tokens] and their
/// "did the OS ask for less motion" flag from MediaQuery. Keeping one notifier
/// here lets a preference write in Settings reach both without a second
/// lifecycle: [Tokens] reads [MotionPreference.shared] for each duration and
/// [AccessibilityScope] writes the resolved value into MediaQuery.
class MotionPreference extends ChangeNotifier {
  MotionPreference._();

  static final MotionPreference shared = MotionPreference._();

  ReducedMotion _value = ReducedMotion.system;

  ReducedMotion get value => _value;

  bool get reduced => _value.resolve(systemReduced);

  /// The platform's own reduce-motion flag, when a binding exists.
  bool get systemReduced {
    try {
      return WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations;
    } catch (_) {
      return false; // Pure-Dart unit tests have no platform dispatcher.
    }
  }

  /// Reconciles with a settings map. Callers must not write [value] directly
  /// from a build method unless they tolerate a notification; [sync] is quiet
  /// when nothing changed.
  void sync(Map<String, dynamic> settings) =>
      set(normalizeReducedMotion(settings['reduceMotion']));

  void set(ReducedMotion next) {
    if (_value == next) return;
    _value = next;
    notifyListeners();
  }

  /// Test-only: the singleton outlives individual widget tests.
  void reset() => set(ReducedMotion.system);
}

/// Applies the accessibility preferences to everything below it.
///
/// MediaQuery is the channel Flutter widgets already use for both settings:
/// animated widgets read `disableAnimations`, and every `Text` reads the
/// `textScaler`. Wrapping once means a preference is not re-implemented in
/// each screen.
class AccessibilityScope extends StatelessWidget {
  const AccessibilityScope({
    super.key,
    required this.reducedMotion,
    required this.textScale,
    required this.child,
  });

  final ReducedMotion reducedMotion;
  final double textScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        disableAnimations: reducedMotion.resolve(media.disableAnimations),
        textScaler: TextScaler.linear(textScale),
      ),
      child: child,
    );
  }
}

/// The three text-size options in Settings → Appearance (Devices 4f).
const textScaleOptions = <int>[100, 115, 130];

/// Normalises a persisted text-scale preference to 100, 115 or 130.
int normalizeTextScale(Object? raw) {
  final n = switch (raw) {
    final num v => v.round(),
    final String v => int.tryParse(v.trim()) ?? 100,
    _ => 100,
  };
  return textScaleOptions.contains(n) ? n : 100;
}

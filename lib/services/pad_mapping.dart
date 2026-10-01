import '../controls/control_layout.dart' show retroPadInputs, retroPadId;
import '../state/app_state.dart';

/// Which controller button presses which RetroPad input, editable by the
/// user and saved in settings under [padMappingKey] as `{button: input}`.
///
/// Buttons are the names every platform backend reports (`a`, `lb`, `rt`,
/// `start`, `up`, …). The default maps each to its natural RetroPad input;
/// a saved mapping only stores what the user changed, so a reset is simply
/// deleting it.
const padMappingKey = 'padMapping';

/// Controller buttons, in the order the Controllers settings lists them.
const padButtons = [
  'a', 'b', 'x', 'y', 'lb', 'rb', 'lt', 'rt', 'l3', 'r3', //
  'select', 'start', 'up', 'down', 'left', 'right',
];

/// The natural RetroPad input for each controller button.
const defaultPadMapping = {
  'a': 'a', 'b': 'b', 'x': 'x', 'y': 'y',
  'lb': 'l', 'rb': 'r', 'lt': 'l2', 'rt': 'r2', 'l3': 'l3', 'r3': 'r3',
  'select': 'select', 'start': 'start',
  'up': 'up', 'down': 'down', 'left': 'left', 'right': 'right',
};

class PadMapping {
  PadMapping(this.state);
  final AppState state;

  /// The effective mapping: defaults overlaid with the user's changes. A
  /// saved entry naming an unknown button or input is ignored.
  Map<String, String> get current {
    final out = Map.of(defaultPadMapping);
    final saved = state.settings[padMappingKey];
    if (saved is Map) {
      for (final e in saved.entries) {
        final button = e.key, input = e.value;
        if (button is String &&
            input is String &&
            padButtons.contains(button) &&
            retroPadInputs.contains(input)) {
          out[button] = input;
        }
      }
    }
    return out;
  }

  /// The RetroPad id [button] presses, or null for an unknown button.
  int? retroIdFor(String button) {
    final input = current[button];
    return input == null ? null : retroPadId(input);
  }

  /// The controller button that presses [input], if any.
  String? buttonFor(String input) {
    for (final e in current.entries) {
      if (e.value == input) return e.key;
    }
    return null;
  }

  /// Makes [button] press [input]. Whatever button pressed [input] before
  /// takes [button]'s old input, so no input is ever left unreachable.
  Future<void> assign(String button, String input) async {
    if (!padButtons.contains(button) || !retroPadInputs.contains(input)) {
      throw ArgumentError('unknown button "$button" or input "$input"');
    }
    final next = current;
    final previous = next[button];
    final other = buttonFor(input);
    next[button] = input;
    if (other != null && other != button && previous != null) {
      next[other] = previous;
    }
    final changed = {
      for (final e in next.entries)
        if (defaultPadMapping[e.key] != e.value) e.key: e.value,
    };
    await state.setSetting(padMappingKey, changed);
  }

  bool get isDefault => current.entries
      .every((e) => defaultPadMapping[e.key] == e.value);

  Future<void> reset() => state.removeSetting(padMappingKey);
}

/// How a controller button is named to people.
String padButtonLabel(String? button) => switch (button) {
  null => 'not assigned',
  'lb' => 'LB / L1',
  'rb' => 'RB / R1',
  'lt' => 'LT / L2',
  'rt' => 'RT / R2',
  'l3' => 'Left stick press',
  'r3' => 'Right stick press',
  'select' => 'Select / Back',
  'start' => 'Start / Menu',
  'up' => 'D-pad up',
  'down' => 'D-pad down',
  'left' => 'D-pad left',
  'right' => 'D-pad right',
  final b => b.toUpperCase(),
};

enum ChordResult { pass, openMenu, swallow }

/// Detects Select + Start held together (the controller's way into the pause
/// menu, since no platform reports a Home button). The chord's own presses
/// and releases are withdrawn from the game: the caller releases Select and
/// Start in the core on [ChordResult.openMenu], and drops events marked
/// [ChordResult.swallow].
class PadChord {
  static const buttons = {'select', 'start'};
  final _held = <String>{};
  bool _fired = false;

  ChordResult feed(String button, bool pressed) {
    if (pressed) {
      _held.add(button);
    } else {
      _held.remove(button);
    }
    if (_held.containsAll(buttons)) {
      if (_fired) return ChordResult.swallow;
      _fired = true;
      return ChordResult.openMenu;
    }
    if (_fired && buttons.contains(button)) {
      if (_held.intersection(buttons).isEmpty) _fired = false;
      return ChordResult.swallow;
    }
    return ChordResult.pass;
  }
}

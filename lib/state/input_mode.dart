import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Orientation, Size;

import '../theme/tokens.dart';

/// The physical device that last moved the focus.
///
/// The hint row and button glyphs follow this, so a room where a pad is
/// picked up mid-session never shows two competing sets of hints.
enum OrbitInputSource { keyboard, pointer, pad }

/// Input-aware modifiers layered on top of [OrbitLayout] values.
///
/// These deliberately are *not* new layout families: a TV still uses the
/// desktop rail/flow/dock code, and a handheld still uses the landscape
/// chrome. A modifier only changes the measurements and the affordances.
enum LayoutModifier { none, tv, ultrawide, handheld }

/// One owner for "what input is being used", so a screen never has to guess
/// whether hover is live or which glyph set to draw.
class InputMode extends ChangeNotifier {
  InputMode._();

  /// The single app-wide instance. Screens listen to it through [Layout].
  static final InputMode shared = InputMode._();

  OrbitInputSource _lastSource = OrbitInputSource.keyboard;
  bool _pointerSeen = false;
  String? _padName;
  String? _forced;

  OrbitInputSource get lastSource => _lastSource;

  /// True once a real pointer (mouse or touch) has been observed. A TV that
  /// has only ever seen a pad keeps its no-hover, always-labelled chrome.
  bool get pointerSeen => _pointerSeen;

  bool get padConnected => _padName != null;

  String? get padName => _padName;

  /// An explicit override, e.g. the "TV mode" setting used by captures.
  String? get forced => _forced;

  void noteKeyboard() {
    if (_lastSource == OrbitInputSource.keyboard) return;
    _lastSource = OrbitInputSource.keyboard;
    notifyListeners();
  }

  void notePointer() {
    final first = !_pointerSeen;
    _pointerSeen = true;
    if (_lastSource == OrbitInputSource.pointer && !first) return;
    _lastSource = OrbitInputSource.pointer;
    notifyListeners();
  }

  void notePad(String? name) {
    final changed = name != _padName;
    _padName = name;
    if (name != null) _lastSource = OrbitInputSource.pad;
    if (changed || name != null) notifyListeners();
  }

  /// Mirrors the persisted setting into the live modifier. `null` / `auto`
  /// means "decide from the inputs and the window".
  void syncFromSettings(Map<String, dynamic> settings) {
    setForced(settings['ui.inputMode'] as String?);
  }

  void setForced(String? value) {
    final next = (value == null || value == 'auto') ? null : value;
    if (_forced == next) return;
    _forced = next;
    notifyListeners();
  }

  /// Resolves the modifier for a window. Kept independent of [BuildContext]
  /// so tests and the capture harness can pin it directly.
  LayoutModifier resolve(Size size, Orientation orientation) {
    switch (_forced) {
      case 'tv':
        return LayoutModifier.tv;
      case 'handheld':
        return LayoutModifier.handheld;
      case 'ultrawide':
        return LayoutModifier.ultrawide;
    }

    final landscape = orientation == Orientation.landscape;
    if (!landscape) return LayoutModifier.none;

    // A very wide window is a 10-foot screen even before a pad is seen:
    // the extra room exists for a sofa, not for a desk.
    if (size.width / size.height >= 2.1) return LayoutModifier.ultrawide;

    final desktop =
        size.width >= Tokens.bpDesktop && size.height >= Tokens.bpShortHeight;
    if (desktop &&
        !_pointerSeen &&
        (padConnected || (size.width >= 1800 && size.height >= 1000))) {
      return LayoutModifier.tv;
    }

    // A handheld is a desktop-class window in a 7"-class chassis: compact
    // rail, collapsed dock, built-in pad instead of touch controls.
    if (size.width >= Tokens.bpDesktop &&
        size.width <= 1400 &&
        size.height >= 760 &&
        size.height <= 840 &&
        !_pointerSeen) {
      return LayoutModifier.handheld;
    }
    return LayoutModifier.none;
  }

  /// Test-only reset: the singleton outlives individual widget tests.
  void reset() {
    _lastSource = OrbitInputSource.keyboard;
    _pointerSeen = false;
    _padName = null;
    _forced = null;
    notifyListeners();
  }
}

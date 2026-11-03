import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/gamepad.dart';
import '../theme/symbols.dart';

/// Which device moved or pressed last. The OS bar and the hint row follow it.
enum InputKind { keyboard, mouse, pad }

/// The physical pad family, which decides the glyph set.
enum PadFamily { xbox, playstation, nintendo }

/// Named actions whose chip changes with the input above (§4.3).
enum GlyphKey { confirm, back, options, details, start, lb, rb, view }

/// One complete glyph set for an input device.
class GlyphSet {
  const GlyphSet(this._glyphs);

  final Map<GlyphKey, String> _glyphs;

  String operator [](GlyphKey key) => _glyphs[key] ?? '';

  /// "LB RB" / "[ ]" / "L1 R1".
  String get tab => '${this[GlyphKey.lb]} ${this[GlyphKey.rb]}';
}

const _keyboard = GlyphSet({
  GlyphKey.confirm: 'Enter',
  GlyphKey.back: 'Esc',
  GlyphKey.options: 'Q',
  GlyphKey.details: 'E',
  GlyphKey.start: 'P',
  GlyphKey.lb: '[',
  GlyphKey.rb: ']',
  GlyphKey.view: 'V',
});

const _xbox = GlyphSet({
  GlyphKey.confirm: 'A',
  GlyphKey.back: 'B',
  GlyphKey.options: 'X',
  GlyphKey.details: 'Y',
  GlyphKey.start: '≡',
  GlyphKey.lb: 'LB',
  GlyphKey.rb: 'RB',
  GlyphKey.view: '⧉',
});

const _playstation = GlyphSet({
  GlyphKey.confirm: '✕',
  GlyphKey.back: '○',
  GlyphKey.options: '□',
  GlyphKey.details: '△',
  GlyphKey.start: 'OPT',
  GlyphKey.lb: 'L1',
  GlyphKey.rb: 'R1',
  GlyphKey.view: 'CREATE',
});

const _nintendo = GlyphSet({
  GlyphKey.confirm: 'A',
  GlyphKey.back: 'B',
  GlyphKey.options: 'Y',
  GlyphKey.details: 'X',
  GlyphKey.start: '+',
  GlyphKey.lb: 'L',
  GlyphKey.rb: 'R',
  GlyphKey.view: '−',
});

/// Last input used, its pad family, and the resulting glyphs.
///
/// One owner, written by pointer, keyboard and pad events; the OS bar and
/// the hint row read it so they can never disagree with each other.
class InputModeController extends ChangeNotifier {
  InputKind _kind = InputKind.keyboard;
  PadFamily _family = PadFamily.xbox;

  InputKind get kind => _kind;

  PadFamily get family => _family;

  GlyphSet get glyphs => switch (_kind) {
    InputKind.pad => switch (_family) {
      PadFamily.xbox => _xbox,
      PadFamily.playstation => _playstation,
      PadFamily.nintendo => _nintendo,
    },
    _ => _keyboard,
  };

  /// Human label for the OS bar: "Keyboard", "Mouse", "Xbox controller"…
  String get label => switch (_kind) {
    InputKind.keyboard => 'Keyboard',
    InputKind.mouse => 'Mouse',
    InputKind.pad => switch (_family) {
      PadFamily.xbox => 'Xbox controller',
      PadFamily.playstation => 'PlayStation controller',
      PadFamily.nintendo => 'Nintendo controller',
    },
  };

  IconData get icon => switch (_kind) {
    InputKind.keyboard => Symbols.keyboard,
    InputKind.mouse => Symbols.mouse,
    InputKind.pad => Symbols.sportsEsports,
  };

  void noteKeyboard() => _set(InputKind.keyboard);

  void noteMouse() => _set(InputKind.mouse);

  void notePad([String? name]) {
    final family = padFamilyForName(name);
    if (_kind == InputKind.pad && _family == family) return;
    _kind = InputKind.pad;
    _family = family;
    notifyListeners();
  }

  void _set(InputKind kind) {
    if (_kind == kind) return;
    _kind = kind;
    notifyListeners();
  }
}

/// Guess the pad family from the device name; Xbox when unknown.
PadFamily padFamilyForName(String? name) {
  final n = (name ?? '').toLowerCase();
  if (n.contains('playstation') ||
      n.contains('dualshock') ||
      n.contains('dualsense') ||
      n.contains('sony')) {
    return PadFamily.playstation;
  }
  if (n.contains('nintendo') ||
      n.contains('switch') ||
      n.contains('joy-con') ||
      n.contains('joycon')) {
    return PadFamily.nintendo;
  }
  return PadFamily.xbox;
}

/// Feeds real input events into an [InputModeController].
///
/// Wraps its child so pointer motion is seen anywhere in the app, listens to
/// the hardware keyboard, and turns any pad button press into the pad glyph
/// set. It never intercepts an event: handlers return false and the child
/// keeps every normal behaviour.
class InputModeDetector extends StatefulWidget {
  const InputModeDetector({super.key, required this.mode, required this.child});

  final InputModeController mode;
  final Widget child;

  @override
  State<InputModeDetector> createState() => _InputModeDetectorState();
}

class _InputModeDetectorState extends State<InputModeDetector> {
  late final bool Function(KeyEvent) _onKey;
  void Function()? _cancelPad;

  @override
  void initState() {
    super.initState();
    _onKey = (event) {
      if (event is KeyDownEvent) widget.mode.noteKeyboard();
      return false;
    };
    HardwareKeyboard.instance.addHandler(_onKey);
    _cancelPad = GamepadService.shared.onButton((event) {
      if (!event.pressed) return;
      widget.mode.notePad(GamepadService.shared.connectedPad);
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _cancelPad?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => widget.mode.noteMouse(),
      child: Listener(
        onPointerDown: (_) => widget.mode.noteMouse(),
        child: widget.child,
      ),
    );
  }
}

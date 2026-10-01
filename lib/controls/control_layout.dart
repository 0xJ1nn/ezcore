import 'dart:ui' show Rect;

/// On-screen controls as data (format `ezcore.controls/1`, ADR-020).
///
/// One shape serves the built-in layouts, a user's customised copy, and
/// layouts that core packages ship. A layout says where the game picture
/// goes, optionally how to split it (a DS's two screens), what shell to draw
/// behind everything, and which controls sit where. Every coordinate is a
/// fraction of the player area (0..1), so one layout fits any screen with
/// the same orientation. It is data only: nothing in it can run code, load a
/// file, or reach the network.

const controlsFormat = 'ezcore.controls/1';

/// RetroPad inputs a control can press, in RETRO_DEVICE_ID_JOYPAD_* order,
/// so an input's index is the id the core receives.
const retroPadInputs = [
  'b', 'y', 'select', 'start', 'up', 'down', 'left', 'right', //
  'a', 'x', 'l', 'r', 'l2', 'r2', 'l3', 'r3',
];

/// Inputs that act on ezCORE rather than on the game.
const hostInputs = ['menu', 'fast_forward'];

/// The RetroPad id for [input], or null for a host input.
int? retroPadId(String input) {
  final i = retroPadInputs.indexOf(input);
  return i < 0 ? null : i;
}

enum ControlType { dpad, button }

enum ControlShape { circle, pill, rounded }

enum LayoutOrientation { portrait, landscape, any }

/// A rectangle in player-area fractions.
class NormRect {
  const NormRect(this.x, this.y, this.w, this.h);
  final double x, y, w, h;

  Rect resolve(double width, double height) =>
      Rect.fromLTWH(x * width, y * height, w * width, h * height);

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  NormRect copyWith({double? x, double? y, double? w, double? h}) =>
      NormRect(x ?? this.x, y ?? this.y, w ?? this.w, h ?? this.h);
}

/// How the game picture is placed. [split] 2 cuts the core's frame into two
/// equal halves stacked top to bottom (a DS outputs its two screens that
/// way) and draws them with [gap] between them, stacked or side by side.
class ScreenSpec {
  const ScreenSpec({
    required this.rect,
    this.split = 1,
    this.arrange = 'stacked',
    this.gap = 0.0,
  });
  final NormRect rect;
  final int split;
  final String arrange; // 'stacked' | 'side'
  final double gap;

  Map<String, dynamic> toJson() => {
    ...rect.toJson(),
    if (split != 1) 'split': split,
    if (split != 1) 'arrange': arrange,
    if (gap != 0) 'gap': gap,
  };
}

/// What to draw behind the picture and controls. Purely declarative: a fill
/// colour, corner rounding and an optional clamshell hinge line.
class ShellSpec {
  const ShellSpec({this.color, this.radius = 0, this.hinge});
  final int? color; // 0xAARRGGBB
  final double radius; // fraction of the shorter side
  final double? hinge; // y fraction of a hinge band, for clamshell shells

  Map<String, dynamic> toJson() => {
    if (color != null) 'color': _hex(color!),
    if (radius != 0) 'radius': radius,
    if (hinge != null) 'hinge': hinge,
  };
}

class ControlSpec {
  const ControlSpec({
    required this.id,
    required this.type,
    required this.rect,
    this.input,
    this.label,
    this.shape = ControlShape.circle,
  });

  final String id;
  final ControlType type;
  final NormRect rect;

  /// For a button: a [retroPadInputs] or [hostInputs] name. A d-pad always
  /// drives up/down/left/right.
  final String? input;
  final String? label;
  final ControlShape shape;

  ControlSpec copyWith({NormRect? rect}) => ControlSpec(
    id: id,
    type: type,
    rect: rect ?? this.rect,
    input: input,
    label: label,
    shape: shape,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    ...rect.toJson(),
    if (input != null) 'input': input,
    if (label != null) 'label': label,
    if (type == ControlType.button) 'shape': shape.name,
  };
}

class ControlLayout {
  const ControlLayout({
    required this.id,
    required this.name,
    required this.systems,
    required this.orientation,
    required this.screen,
    required this.controls,
    this.shell = const ShellSpec(),
    this.opacity = 0.85,
  });

  final String id;
  final String name;
  final List<String> systems;
  final LayoutOrientation orientation;
  final ScreenSpec screen;
  final ShellSpec shell;
  final List<ControlSpec> controls;

  /// Overall control opacity, 0.1..1.
  final double opacity;

  ControlLayout copyWith({List<ControlSpec>? controls, double? opacity}) =>
      ControlLayout(
        id: id,
        name: name,
        systems: systems,
        orientation: orientation,
        screen: screen,
        shell: shell,
        controls: controls ?? this.controls,
        opacity: opacity ?? this.opacity,
      );

  Map<String, dynamic> toJson() => {
    'format': controlsFormat,
    'id': id,
    'name': name,
    'systems': systems,
    'orientation': orientation.name,
    'screen': screen.toJson(),
    if (shell.toJson().isNotEmpty) 'shell': shell.toJson(),
    'opacity': opacity,
    'controls': [for (final c in controls) c.toJson()],
  };

  /// Parses and validates [json]. Returns the layout, or every problem found
  /// — never a partially trusted layout.
  static ({ControlLayout? layout, List<String> errors}) parse(Object? json) {
    final e = <String>[];
    if (json is! Map) {
      return (layout: null, errors: ['layout must be a JSON object']);
    }
    const known = {
      'format',
      'id',
      'name',
      'systems',
      'orientation',
      'screen',
      'shell',
      'opacity',
      'controls',
    };
    for (final k in json.keys) {
      if (!known.contains(k)) e.add('unknown field "$k"');
    }
    if (json['format'] != controlsFormat) {
      e.add('format must be "$controlsFormat"');
    }
    final id = _str(json['id'], 'id', e, pattern: _idPattern);
    final name = _str(json['name'], 'name', e);
    final systems = <String>[];
    final rawSystems = json['systems'];
    if (rawSystems is! List || rawSystems.isEmpty || rawSystems.length > 32) {
      e.add('systems must be a list of 1..32 system ids');
    } else {
      for (final s in rawSystems) {
        if (s is String && _idPattern.hasMatch(s)) {
          systems.add(s);
        } else {
          e.add('bad system id "$s"');
        }
      }
    }
    final orientation = LayoutOrientation.values
        .where((o) => o.name == json['orientation'])
        .firstOrNull;
    if (orientation == null) {
      e.add('orientation must be portrait, landscape or any');
    }
    ScreenSpec? screen;
    final rawScreen = json['screen'];
    if (rawScreen is! Map) {
      e.add('screen must be an object');
    } else {
      final r = _rect(rawScreen, 'screen', e);
      final split = rawScreen['split'] ?? 1;
      final arrange = rawScreen['arrange'] ?? 'stacked';
      final gap = rawScreen['gap'] ?? 0;
      if (split != 1 && split != 2) e.add('screen.split must be 1 or 2');
      if (arrange != 'stacked' && arrange != 'side') {
        e.add('screen.arrange must be stacked or side');
      }
      if (gap is! num || gap < 0 || gap > 0.5) {
        e.add('screen.gap must be 0..0.5');
      }
      if (r != null && split is int && arrange is String && gap is num) {
        screen = ScreenSpec(
          rect: r,
          split: split,
          arrange: arrange,
          gap: gap.toDouble(),
        );
      }
    }
    var shell = const ShellSpec();
    final rawShell = json['shell'];
    if (rawShell != null) {
      if (rawShell is! Map) {
        e.add('shell must be an object');
      } else {
        for (final k in rawShell.keys) {
          if (!{'color', 'radius', 'hinge'}.contains(k)) {
            e.add('unknown shell field "$k"');
          }
        }
        int? color;
        if (rawShell['color'] != null) {
          color = _color(rawShell['color']);
          if (color == null) e.add('shell.color must be #RRGGBB or #AARRGGBB');
        }
        final radius = rawShell['radius'] ?? 0;
        final hinge = rawShell['hinge'];
        if (radius is! num || radius < 0 || radius > 0.5) {
          e.add('shell.radius must be 0..0.5');
        }
        if (hinge != null && (hinge is! num || hinge < 0 || hinge > 1)) {
          e.add('shell.hinge must be 0..1');
        }
        if (radius is num && (hinge == null || hinge is num)) {
          shell = ShellSpec(
            color: color,
            radius: radius.toDouble(),
            hinge: (hinge as num?)?.toDouble(),
          );
        }
      }
    }
    final opacity = json['opacity'] ?? 0.85;
    if (opacity is! num || opacity < 0.1 || opacity > 1) {
      e.add('opacity must be 0.1..1');
    }
    final controls = <ControlSpec>[];
    final rawControls = json['controls'];
    if (rawControls is! List || rawControls.length > 64) {
      e.add('controls must be a list of at most 64 controls');
    } else {
      final ids = <String>{};
      for (var i = 0; i < rawControls.length; i++) {
        final c = _control(rawControls[i], i, e);
        if (c == null) continue;
        if (!ids.add(c.id)) e.add('duplicate control id "${c.id}"');
        controls.add(c);
      }
    }
    if (e.isNotEmpty) return (layout: null, errors: e);
    return (
      layout: ControlLayout(
        id: id!,
        name: name!,
        systems: systems,
        orientation: orientation!,
        screen: screen!,
        shell: shell,
        controls: controls,
        opacity: (opacity as num).toDouble(),
      ),
      errors: const [],
    );
  }

  static ControlSpec? _control(Object? raw, int i, List<String> e) {
    final where = 'controls[$i]';
    if (raw is! Map) {
      e.add('$where must be an object');
      return null;
    }
    for (final k in raw.keys) {
      if (!{
        'id',
        'type',
        'x',
        'y',
        'w',
        'h',
        'input',
        'label',
        'shape',
      }.contains(k)) {
        e.add('$where: unknown field "$k"');
      }
    }
    final before = e.length;
    final id = _str(raw['id'], '$where.id', e, pattern: _idPattern);
    final type = ControlType.values
        .where((t) => t.name == raw['type'])
        .firstOrNull;
    if (type == null) e.add('$where.type must be dpad or button');
    final rect = _rect(raw, where, e);
    String? input;
    if (type == ControlType.button) {
      input = raw['input'] as String?;
      if (input == null ||
          (!retroPadInputs.contains(input) && !hostInputs.contains(input))) {
        e.add('$where.input "${raw['input']}" is not a known input');
      }
    } else if (raw['input'] != null) {
      e.add('$where: a dpad takes no input');
    }
    final label = raw['label'];
    if (label != null && (label is! String || label.length > 12)) {
      e.add('$where.label must be at most 12 characters');
    }
    final shape = ControlShape.values
        .where((s) => s.name == (raw['shape'] ?? 'circle'))
        .firstOrNull;
    if (shape == null) e.add('$where.shape must be circle, pill or rounded');
    if (e.length != before) return null;
    return ControlSpec(
      id: id!,
      type: type!,
      rect: rect!,
      input: input,
      label: label as String?,
      shape: shape!,
    );
  }
}

final _idPattern = RegExp(r'^[a-z0-9_]{1,64}$');

String? _str(Object? v, String what, List<String> e, {RegExp? pattern}) {
  if (v is! String || v.isEmpty || v.length > 64) {
    e.add('$what must be a string of 1..64 characters');
    return null;
  }
  if (pattern != null && !pattern.hasMatch(v)) {
    e.add('$what "$v" must match [a-z0-9_]');
    return null;
  }
  return v;
}

NormRect? _rect(Map raw, String where, List<String> e) {
  final vals = <double>[];
  for (final k in ['x', 'y', 'w', 'h']) {
    final v = raw[k];
    if (v is! num || v.isNaN || v < 0 || v > 1) {
      e.add('$where.$k must be a number 0..1');
      return null;
    }
    vals.add(v.toDouble());
  }
  if (vals[2] <= 0 || vals[3] <= 0) {
    e.add('$where must have a positive size');
    return null;
  }
  if (vals[0] + vals[2] > 1.0001 || vals[1] + vals[3] > 1.0001) {
    e.add('$where must lie inside the player area');
    return null;
  }
  return NormRect(vals[0], vals[1], vals[2], vals[3]);
}

int? _color(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').firstMatch(v);
  if (m == null) return null;
  final hex = m.group(1)!;
  return int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
}

String _hex(int argb) =>
    '#${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';

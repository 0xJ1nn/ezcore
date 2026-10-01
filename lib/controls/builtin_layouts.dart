import 'control_layout.dart';

/// The layouts ezCORE ships, one portrait and one landscape per family of
/// systems. They are ordinary [ControlLayout]s — the same format a core
/// package or a user's customised copy uses — built here from a short
/// description of each family so the geometry stays consistent.
///
/// Labels follow the system's own markings only where the RetroPad mapping
/// is well established (Nintendo letters, Sony symbols, Genesis A/B/C, PC
/// Engine I/II). Elsewhere a button shows its RetroPad name, rather than a
/// guess about how the core maps it.

enum _Face { one, two, pce, four, sony, genesis }

enum _Shoulders { none, lr, lr2, lrz }

class _Family {
  const _Family(
    this.id,
    this.name,
    this.systems,
    this.face,
    this.shoulders, {
    this.shell,
    this.dual = false,
  });
  final String id;
  final String name;
  final List<String> systems;
  final _Face face;
  final _Shoulders shoulders;
  final int? shell;
  final bool dual; // two screens stacked in one frame (Nintendo DS)
}

const _families = [
  _Family(
    'gameboy',
    'Game Boy',
    ['gb', 'gbc'],
    _Face.two,
    _Shoulders.none,
    shell: 0xFF1E2636,
  ),
  _Family(
    'gba',
    'Game Boy Advance',
    ['gba'],
    _Face.two,
    _Shoulders.lr,
    shell: 0xFF1B2440,
  ),
  _Family('nes', 'NES', ['nes', 'fds'], _Face.two, _Shoulders.none),
  _Family('snes', 'Super Nintendo', ['snes'], _Face.four, _Shoulders.lr),
  _Family(
    'genesis',
    'Sega 16-bit',
    ['genesis', 'md', 'scd', 'sms', 'gg', 'sg1000'],
    _Face.genesis,
    _Shoulders.none,
  ),
  _Family(
    'pce',
    'PC Engine',
    ['pce', 'tg16', 'pcecd'],
    _Face.pce,
    _Shoulders.none,
  ),
  _Family('n64', 'Nintendo 64', ['n64'], _Face.four, _Shoulders.lrz),
  _Family('psx', 'PlayStation', ['psx'], _Face.sony, _Shoulders.lr2),
  _Family(
    'psp',
    'PlayStation Portable',
    ['psp'],
    _Face.sony,
    _Shoulders.lr,
    shell: 0xFF161B26,
  ),
  _Family(
    'nds',
    'Nintendo DS',
    ['nds'],
    _Face.four,
    _Shoulders.lr,
    shell: 0xFF1C2333,
    dual: true,
  ),
  _Family('atari', 'Atari 2600', ['atari2600'], _Face.one, _Shoulders.none),
  _Family('arcade', 'Arcade', ['arcade', 'neogeo'], _Face.four, _Shoulders.lr),
  _Family('generic', 'Standard pad', ['generic'], _Face.four, _Shoulders.lr),
];

/// The built-in layout for [system] in the given orientation. Always the
/// same instance for the same answer: the player rebuilds every frame, and
/// a "new" layout each time would make the touch layer release every held
/// control.
ControlLayout builtinLayout(String system, {required bool portrait}) {
  final family = _families.firstWhere(
    (f) => f.systems.contains(system),
    orElse: () => _families.last,
  );
  return _cache.putIfAbsent(
    '${family.id}/$portrait',
    () => portrait ? _portrait(family) : _landscape(family),
  );
}

final _cache = <String, ControlLayout>{};

/// Every built-in layout (used by tests to prove they all validate).
List<ControlLayout> allBuiltinLayouts() => [
  for (final f in _families) ...[_portrait(f), _landscape(f)],
];

// ---- geometry ----
//
// Portrait: picture on top, controls below, like a handheld held upright.
// Landscape: picture centred at full height, controls in the side columns.

ControlLayout _portrait(_Family f) {
  final screen = f.dual
      ? const ScreenSpec(
          rect: NormRect(0.06, 0.06, 0.88, 0.58),
          split: 2,
          arrange: 'stacked',
          gap: 0.03,
        )
      : const ScreenSpec(rect: NormRect(0.03, 0.06, 0.94, 0.42));
  final top = f.dual ? 0.66 : 0.52;
  // The d-pad and face buttons fill the band between the shoulder rows and
  // the Start/Select row, so nothing overlaps whatever the family.
  final rows = switch (f.shoulders) {
    _Shoulders.none => 0,
    _Shoulders.lr => 1,
    _Shoulders.lr2 || _Shoulders.lrz => 2,
  };
  final bandTop = top + rows * 0.055 + 0.01;
  final band = 0.92 - bandTop;
  final controls = <ControlSpec>[
    const ControlSpec(
      id: 'menu',
      type: ControlType.button,
      input: 'menu',
      label: 'Menu',
      shape: ControlShape.pill,
      rect: NormRect(0.40, 0.005, 0.20, 0.045),
    ),
    ControlSpec(
      id: 'dpad',
      type: ControlType.dpad,
      rect: NormRect(0.04, bandTop, 0.42, band),
    ),
    ..._face(f.face, NormRect(0.54, bandTop, 0.42, band), aspect: 0.46),
    ..._shoulders(f.shoulders, top, portrait: true),
    ..._startSelect(f, NormRect(0.27, 0.93, 0.46, 0.05)),
  ];
  return ControlLayout(
    id: '${f.id}_portrait',
    name: '${f.name} (portrait)',
    systems: f.systems,
    orientation: LayoutOrientation.portrait,
    screen: screen,
    shell: ShellSpec(
      color: f.shell,
      radius: f.shell == null ? 0 : 0.04,
      hinge: f.dual ? 0.35 : null, // between the two screens
    ),
    controls: controls,
  );
}

ControlLayout _landscape(_Family f) {
  final screen = f.dual
      ? const ScreenSpec(
          rect: NormRect(0.18, 0.04, 0.64, 0.92),
          split: 2,
          arrange: 'side',
          gap: 0.02,
        )
      : const ScreenSpec(rect: NormRect(0.18, 0.02, 0.64, 0.96));
  final controls = <ControlSpec>[
    const ControlSpec(
      id: 'menu',
      type: ControlType.button,
      input: 'menu',
      label: 'Menu',
      shape: ControlShape.pill,
      rect: NormRect(0.02, 0.02, 0.12, 0.10),
    ),
    const ControlSpec(
      id: 'dpad',
      type: ControlType.dpad,
      rect: NormRect(0.01, 0.40, 0.17, 0.40),
    ),
    ..._face(f.face, const NormRect(0.82, 0.36, 0.18, 0.46), aspect: 2.16),
    ..._shoulders(f.shoulders, 0, portrait: false),
    ..._startSelect(f, const NormRect(0.83, 0.86, 0.16, 0.10), split: true),
  ];
  return ControlLayout(
    id: '${f.id}_landscape',
    name: '${f.name} (landscape)',
    systems: f.systems,
    orientation: LayoutOrientation.landscape,
    screen: screen,
    shell: ShellSpec(color: f.shell, radius: 0),
    controls: controls,
    opacity: 0.7,
  );
}

/// Face buttons inside [box]. They are laid out in a region that is square
/// on a typical screen of that orientation ([aspect] = width / height), so a
/// diamond stays a diamond, and spaced so no two hit areas touch.
List<ControlSpec> _face(_Face face, NormRect box, {required double aspect}) {
  var w0 = box.w, h0 = box.w * aspect;
  if (h0 > box.h) {
    h0 = box.h;
    w0 = box.h / aspect;
  }
  final r = NormRect(
    box.x + (box.w - w0) / 2,
    box.y + (box.h - h0) / 2,
    w0,
    h0,
  );
  ControlSpec b(
    String id,
    String input,
    String label,
    double cx,
    double cy, [
    double s = 0.32,
  ]) {
    final w = r.w * s, h = r.h * s;
    return ControlSpec(
      id: id,
      type: ControlType.button,
      input: input,
      label: label,
      rect: NormRect(r.x + r.w * cx - w / 2, r.y + r.h * cy - h / 2, w, h),
    );
  }

  switch (face) {
    case _Face.one:
      return [b('fire', 'b', 'Fire', 0.5, 0.5, 0.5)];
    case _Face.two:
      return [
        b('b', 'b', 'B', 0.28, 0.62, 0.42),
        b('a', 'a', 'A', 0.72, 0.38, 0.42),
      ];
    case _Face.pce:
      return [
        b('ii', 'b', 'II', 0.28, 0.62, 0.42),
        b('i', 'a', 'I', 0.72, 0.38, 0.42),
      ];
    case _Face.genesis:
      return [
        b('ga', 'y', 'A', 0.18, 0.62, 0.3),
        b('gb', 'b', 'B', 0.5, 0.5, 0.3),
        b('gc', 'a', 'C', 0.82, 0.38, 0.3),
      ];
    case _Face.four:
      return [
        b('x', 'x', 'X', 0.5, 0.17),
        b('y', 'y', 'Y', 0.17, 0.5),
        b('a', 'a', 'A', 0.83, 0.5),
        b('b', 'b', 'B', 0.5, 0.83),
      ];
    case _Face.sony:
      return [
        b('triangle', 'x', '△', 0.5, 0.17),
        b('square', 'y', '□', 0.17, 0.5),
        b('circle', 'a', '○', 0.83, 0.5),
        b('cross', 'b', '×', 0.5, 0.83),
      ];
  }
}

List<ControlSpec> _shoulders(
  _Shoulders s,
  double top, {
  required bool portrait,
}) {
  if (s == _Shoulders.none) return const [];
  ControlSpec p(String id, String input, String label, NormRect r) =>
      ControlSpec(
        id: id,
        type: ControlType.button,
        input: input,
        label: label,
        shape: ControlShape.pill,
        rect: r,
      );
  final y = portrait ? top : 0.14;
  final h = portrait ? 0.045 : 0.11;
  final w = portrait ? 0.22 : 0.14;
  final out = [
    p('l', 'l', s == _Shoulders.lr2 ? 'L1' : 'L', NormRect(0.03, y, w, h)),
    p(
      'r',
      'r',
      s == _Shoulders.lr2 ? 'R1' : 'R',
      NormRect(1 - 0.03 - w, y, w, h),
    ),
  ];
  final y2 = y + h + (portrait ? 0.01 : 0.02);
  if (s == _Shoulders.lr2) {
    out.addAll([
      p('l2', 'l2', 'L2', NormRect(0.03, y2, w, h)),
      p('r2', 'r2', 'R2', NormRect(1 - 0.03 - w, y2, w, h)),
    ]);
  } else if (s == _Shoulders.lrz) {
    out.add(p('z', 'l2', 'Z', NormRect(0.03, y2, w, h)));
  }
  return out;
}

List<ControlSpec> _startSelect(_Family f, NormRect r, {bool split = false}) {
  ControlSpec p(String id, String input, String label, NormRect rect) =>
      ControlSpec(
        id: id,
        type: ControlType.button,
        input: input,
        label: label,
        shape: ControlShape.pill,
        rect: rect,
      );
  final half = r.w * 0.46;
  if (split) {
    // Landscape: Start under the face buttons, Select under the d-pad.
    return [
      p('select', 'select', 'Select', NormRect(0.02, r.y, r.w, r.h)),
      p('start', 'start', 'Start', r),
    ];
  }
  return [
    p('select', 'select', 'Select', NormRect(r.x, r.y, half, r.h)),
    p('start', 'start', 'Start', NormRect(r.x + r.w - half, r.y, half, r.h)),
  ];
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/symbols.dart';
import '../theme/tokens.dart';
import 'control_layout.dart';
import 'control_overlay.dart';
import 'layout_store.dart';
import 'phone_controls.dart';
import 'stage_backdrop.dart';

/// Edit an on-screen layout in place, over the game itself: drag a control
/// (or the face buttons as one group) to move it, pinch to resize, use the
/// fade slider, or long-press to hide it. Done saves the layout for this
/// system and orientation; Reset returns to the built-in or the core's own.
///
/// What stays true while editing: controls remain inside the screen, keep a
/// minimum size, and Menu can never be hidden — it is the touch way out of
/// a game.
class LayoutEditorScreen extends StatefulWidget {
  const LayoutEditorScreen({
    super.key,
    required this.store,
    required this.system,
    required this.portrait,
    this.coreId,
    this.frame,
  });

  final LayoutStore store;
  final String system;
  final bool portrait;
  final String? coreId;
  final ui.Image? frame;

  @override
  State<LayoutEditorScreen> createState() => _LayoutEditorScreenState();
}

const _faceIds = {
  'x',
  'y',
  'a',
  'b',
  'triangle',
  'square',
  'circle',
  'cross',
  'ga',
  'gb',
  'gc',
  'i',
  'ii',
  'fire',
};

/// The landscape editing board starts from the printed layout's face-group
/// snapshot: A sits high on the right and B low on the left, inside a box that
/// is taller than the player's resting one. Resizing that snapshot is what
/// produces the board's 112% group, while the player keeps its own baseline.
/// Systems with more than two face buttons keep theirs — this only describes
/// the two-button board the design draws.
ControlLayout editBoardBaseline(ControlLayout layout, {required bool portrait}) {
  if (portrait) return layout;
  final faces = layout.controls.where((c) => _faceIds.contains(c.id)).toList();
  if (faces.length != 2) return layout;
  if (!faces.any((c) => c.id == 'a') || !faces.any((c) => c.id == 'b')) {
    return layout;
  }
  NormRect px(double x, double y, double s) =>
      NormRect(x / 844, y / 390, s / 844, s / 390);
  return layout.copyWith(
    controls: [
      for (final c in layout.controls)
        switch (c.id) {
          'a' => c.copyWith(rect: px(728.84, 153.61, 68)),
          'b' => c.copyWith(rect: px(662.16, 203.39, 68)),
          _ => c,
        },
    ],
  );
}

class _LayoutEditorScreenState extends State<LayoutEditorScreen> {
  late ControlLayout _layout;
  late ControlLayout _builtin;
  final List<ControlSpec> _hidden = [];

  /// A selection is 'face' (all face buttons move as one group) or one id.
  String? _selected;
  double _lastPinch = 1;

  static const _minSide = 0.06;
  static const scaleLabelKey = Key('edit-scale-label');

  @override
  void initState() {
    super.initState();
    _builtin = widget.store.defaultFor(
      widget.system,
      portrait: widget.portrait,
      coreId: widget.coreId,
    );
    _layout = widget.store.resolve(
      widget.system,
      portrait: widget.portrait,
      coreId: widget.coreId,
    );
    // The phone boards place controls at their own coordinates. On the
    // landscape board the face group starts from the printed edit snapshot —
    // a layout the player already saved is left alone.
    final saved = !identical(_layout, _builtin);
    _builtin = editBoardBaseline(
      phoneControls(_builtin, portrait: widget.portrait),
      portrait: widget.portrait,
    );
    _layout = saved
        ? phoneControls(_layout, portrait: widget.portrait)
        : _builtin;
    final present = {for (final c in _layout.controls) c.id};
    _hidden.addAll(_builtin.controls.where((c) => !present.contains(c.id)));
  }

  String _groupOf(ControlSpec c) => _faceIds.contains(c.id) ? 'face' : c.id;

  /// The bottom action pills are drawn by the player's action bar, not on
  /// the edit board; their hit areas stay editable via this screen.
  bool _actionPill(ControlSpec c) =>
      c.id == 'menu' || c.id == 'select' || c.id == 'start';

  List<ControlSpec> _members(String group) => group == 'face'
      ? _layout.controls.where((c) => _faceIds.contains(c.id)).toList()
      : _layout.controls.where((c) => c.id == group).toList();

  ControlLayout _with(List<ControlSpec> next) => _layout.copyWith(
    controls: [
      for (final c in _layout.controls)
        next.firstWhere((n) => n.id == c.id, orElse: () => c),
    ],
  );

  void _select(String group) => setState(() => _selected = group);

  void _move(String group, Offset delta, Size size) {
    final members = _members(group);
    if (members.isEmpty) return;
    var left = double.infinity,
        top = double.infinity,
        right = double.infinity,
        bottom = double.infinity;
    for (final c in members) {
      final r = c.rect;
      left = math.min(left, r.x);
      top = math.min(top, r.y);
      right = math.min(right, 1 - (r.x + r.w));
      bottom = math.min(bottom, 1 - (r.y + r.h));
    }
    final dx = (delta.dx / size.width).clamp(-left, right);
    final dy = (delta.dy / size.height).clamp(-top, bottom);
    _layout = _with([
      for (final c in members)
        c.copyWith(
          rect: c.rect.copyWith(x: c.rect.x + dx, y: c.rect.y + dy),
        ),
    ]);
    setState(() {});
  }

  /// Scales the selection about its centre, keeping every member on screen.
  void _scale(String group, double factor, Size size) {
    final members = _members(group);
    if (members.isEmpty) return;
    final centre = _groupRect(group, size).center;
    final minW = _minSide * size.shortestSide / size.width;
    final minH = _minSide * size.shortestSide / size.height;

    var f = factor;
    for (final c in members) {
      f = math.max(f, minW / c.rect.w);
      f = math.max(f, minH / c.rect.h);
    }
    List<ControlSpec> place(double scale) => [
      for (final c in members)
        c.copyWith(
          rect: (() {
            final r = c.rect.resolve(size.width, size.height);
            final w = r.width * scale, h = r.height * scale;
            final x = centre.dx + (r.center.dx - centre.dx) * scale - w / 2;
            final y = centre.dy + (r.center.dy - centre.dy) * scale - h / 2;
            return NormRect(
              x / size.width,
              y / size.height,
              w / size.width,
              h / size.height,
            );
          })(),
        ),
    ];
    bool inside(double scale) => place(scale).every((c) {
      final r = c.rect;
      return r.x >= -1e-6 &&
          r.y >= -1e-6 &&
          r.x + r.w <= 1 + 1e-6 &&
          r.y + r.h <= 1 + 1e-6;
    });
    for (var i = 0; i < 24 && !inside(f); i++) {
      f *= 0.92;
    }
    if (!inside(f)) return;
    _layout = _with(place(f));
    setState(() {});
  }

  void _hide(String group) {
    if (group == 'menu') return;
    final ids = _members(group).map((c) => c.id).toSet();
    _hidden.addAll(_layout.controls.where((c) => ids.contains(c.id)));
    _layout = _layout.copyWith(
      controls: [
        for (final c in _layout.controls)
          if (!ids.contains(c.id)) c,
      ],
    );
    _selected = null;
    setState(() {});
  }

  void _restoreHidden() => setState(() {
    _layout = _layout.copyWith(controls: [..._layout.controls, ..._hidden]);
    _hidden.clear();
  });

  Future<void> _save() async {
    await widget.store.save(_layout);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _reset() async {
    await widget.store.reset(_builtin.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  /// The game picture's box, placed exactly as the player places it, so the
  /// editor shows what playing will show.
  Rect _screenBox(Size size) {
    final frame = widget.frame;
    if (frame == null) {
      return _layout.screen.rect.resolve(size.width, size.height);
    }
    if (widget.portrait) {
      var scale = size.width / frame.width;
      final maxHeight = size.height * 0.70;
      if (frame.height * scale > maxHeight) scale = maxHeight / frame.height;
      return Rect.fromLTWH(
        0,
        size.height * 0.0664,
        frame.width * scale,
        frame.height * scale,
      );
    }
    final fit = math.min(size.width / frame.width, size.height / frame.height);
    final scale = fit >= 1 ? fit.floorToDouble() : fit;
    final h = frame.height * scale;
    return Rect.fromLTWH(
      (size.width - frame.width * scale) / 2,
      math.max(0.0, (size.height - h - 26) / 2),
      frame.width * scale,
      h,
    );
  }

  Rect _groupRect(String group, Size size) {
    final boxes = _members(
      group,
    ).map((c) => c.rect.resolve(size.width, size.height)).toList();
    return boxes.reduce(
      (a, b) => Rect.fromLTRB(
        math.min(a.left, b.left),
        math.min(a.top, b.top),
        math.max(a.right, b.right),
        math.max(a.bottom, b.bottom),
      ),
    );
  }

  /// The selection's scale against the default, shown above the handles.
  int get _scalePercent {
    final group = _selected;
    if (group == null) return 100;
    for (final c in _members(group)) {
      final original = _builtin.controls.where((x) => x.id == c.id).firstOrNull;
      if (original != null && original.rect.w > 0) {
        return (c.rect.w / original.rect.w * 100).round();
      }
    }
    return 100;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.playerInk,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop(false);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final size = c.biggest;
              final box = _screenBox(size);
              final frame = widget.frame;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: StageBackdrop(
                      phone: true,
                      landscape: !widget.portrait,
                      editing: true,
                    ),
                  ),
                  if (frame != null)
                    Positioned.fromRect(
                      rect: box,
                      child: CustomPaint(
                        painter: GamePicturePainter(
                          frame,
                          ScreenSpec(
                            rect: const NormRect(0, 0, 1, 1),
                            split: widget.portrait ? _layout.screen.split : 1,
                            arrange: 'stacked',
                            gap: _layout.screen.gap,
                          ),
                        ),
                      ),
                    ),
                  for (final ctl in _layout.controls)
                    Positioned.fromRect(
                      rect: ctl.rect.resolve(size.width, size.height),
                      child: GestureDetector(
                        key: ValueKey('edit-${ctl.id}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _select(_groupOf(ctl)),
                        onLongPress: () => _hide(_groupOf(ctl)),
                        onScaleStart: (d) {
                          _select(_groupOf(ctl));
                          _lastPinch = 1;
                        },
                        onScaleUpdate: (d) {
                          if (d.pointerCount >= 2) {
                            _scale(_groupOf(ctl), d.scale / _lastPinch, size);
                            _lastPinch = d.scale;
                          } else {
                            _move(_groupOf(ctl), d.focalPointDelta, size);
                          }
                        },
                        child: Stack(
                          clipBehavior: Clip.none,
                          fit: StackFit.expand,
                          children: [
                            if (!_actionPill(ctl) &&
                                ctl.id != 'l' &&
                                ctl.id != 'r')
                              ControlVisual(spec: ctl, editing: true),
                            if (_selected != _groupOf(ctl) && !_actionPill(ctl))
                              const CustomPaint(
                                painter: _DashedOutlinePainter(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (_selected != null)
                    _SelectionHandles(
                      rect: _groupRect(_selected!, size),
                      label: '$_scalePercent%',
                      labelKey: scaleLabelKey,
                      onBigger: () => _scale(_selected!, 1.04, size),
                      onSmaller: () => _scale(_selected!, 1 / 1.04, size),
                      onHide: () => _hide(_selected!),
                      canHide: _selected != 'menu',
                    ),
                  if (_hidden.isNotEmpty)
                    Positioned(
                      left: box.left + 8,
                      bottom: 8,
                      child: GestureDetector(
                        onTap: _restoreHidden,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Tokens.panel,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Tokens.lineStrong),
                          ),
                          child: Text(
                            'Show hidden (${_hidden.length})',
                            style: Tokens.body(size: 12, height: null),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fromRect(
                    rect: Rect.fromLTWH(
                      box.left + 3,
                      box.top - 2,
                      box.width - 6,
                      42,
                    ),
                    child: Semantics(
                      label:
                          'Drag, resize or fade any button. '
                          'Saved for $_systemName.',
                      child: _banner(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String get _systemName {
    final labels = {
      'gba': 'Game Boy Advance',
      'nds': 'Nintendo DS',
      'gb': 'Game Boy',
      'gbc': 'Game Boy Color',
      'snes': 'Super Nintendo',
      'nes': 'NES',
    };
    return labels[widget.system] ?? widget.system.toUpperCase();
  }

  Widget _banner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xF0101825),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: Tokens.lineStrong),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              'Drag to move · pinch to resize',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tokens.body(size: 13, color: Tokens.muted, height: null),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Symbols.opacity, size: 15, color: Tokens.text),
          const SizedBox(width: 6),
          SizedBox(
            width: 84,
            height: 20,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: Tokens.accent,
                inactiveTrackColor: Tokens.toggleOff,
                thumbColor: Tokens.text,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: _layout.opacity.clamp(0.2, 1.0),
                min: 0.2,
                max: 1,
                onChanged: (v) => setState(() {
                  _layout = _layout.copyWith(opacity: v);
                }),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _pill(label: 'Reset', onTap: _reset, filled: false),
          const SizedBox(width: 6),
          _pill(label: 'Done', onTap: _save, filled: true),
        ],
      ),
    );
  }

  Widget _pill({
    required String label,
    required VoidCallback onTap,
    required bool filled,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? Tokens.accent : const Color(0x14DDE6F4),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          label,
          style: Tokens.body(
            size: 13,
            weight: filled ? FontWeight.w700 : FontWeight.w600,
            color: filled ? Colors.white : Tokens.text,
            height: null,
          ),
        ),
      ),
    );
  }
}

/// The dashed edit affordance around a control that is not selected.
class _DashedOutlinePainter extends CustomPainter {
  const _DashedOutlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 3.5, gap = 3.5, inset = 1.0;
    final paint = Paint()
      ..color = Tokens.accent.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - 2 * inset,
      size.height - 2 * inset,
    );
    final r = math.min(rect.shortestSide / 2, 18);
    final points = <Offset>[];
    // Walk the stadium: top edge, right cap, bottom edge, left cap.
    for (var x = rect.left + r; x <= rect.right - r; x += 3) {
      points.add(Offset(x, rect.top));
    }
    for (var a = -math.pi / 2; a <= math.pi / 2; a += 0.12) {
      points.add(
        Offset(
          rect.right - r + r * math.cos(a),
          rect.center.dy + r * math.sin(a),
        ),
      );
    }
    for (var x = rect.right - r; x >= rect.left + r; x -= 3) {
      points.add(Offset(x, rect.bottom));
    }
    for (var a = math.pi / 2; a <= 3 * math.pi / 2; a += 0.12) {
      points.add(
        Offset(
          rect.left + r + r * math.cos(a),
          rect.center.dy + r * math.sin(a),
        ),
      );
    }
    points.add(points.first);
    var until = dash;
    var draw = true;
    for (var i = 1; i < points.length; i++) {
      var from = points[i - 1];
      final to = points[i];
      final length = (to - from).distance;
      var segment = length;
      while (segment > 0.01 && length > 0) {
        final step = math.min(segment, until);
        final end = from + (to - from) * (step / length);
        if (draw) canvas.drawLine(from, end, paint);
        from = end;
        segment -= step;
        until -= step;
        if (until <= 0.01) {
          draw = !draw;
          until = draw ? dash : gap;
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutlinePainter old) => false;
}

/// A crisp accent outline with a soft dark shadow below and to the left.
/// Nothing is painted inside the box: the buttons and their near-white
/// glyphs stay exactly as the player draws them.
class _SelectionOutlinePainter extends CustomPainter {
  const _SelectionOutlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final edge = RRect.fromRectAndRadius(rect, const Radius.circular(16));
    final shadow = RRect.fromRectAndRadius(
      rect.shift(const Offset(-3, 5)),
      const Radius.circular(16),
    );
    canvas.drawRRect(
      shadow,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = const Color(0x99162A44)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRRect(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Tokens.accent,
    );
  }

  @override
  bool shouldRepaint(_SelectionOutlinePainter old) => false;
}

/// The accent outline, scale label and resize handle of the selected group.
class _SelectionHandles extends StatefulWidget {
  const _SelectionHandles({
    required this.rect,
    required this.label,
    required this.labelKey,
    required this.onBigger,
    required this.onSmaller,
    required this.onHide,
    required this.canHide,
  });

  final Rect rect;
  final String label;
  final Key labelKey;
  final VoidCallback onBigger;
  final VoidCallback onSmaller;
  final VoidCallback onHide;
  final bool canHide;

  @override
  State<_SelectionHandles> createState() => _SelectionHandlesState();
}

class _SelectionHandlesState extends State<_SelectionHandles> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.rect;
    final box = Rect.fromLTWH(
      r.left - 14,
      r.top - 30,
      r.width + 28,
      r.height + 44,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: box,
          child: CustomPaint(painter: const _SelectionOutlinePainter()),
        ),
        Positioned(
          left: box.right - 5,
          top: box.bottom - 5,
          child: Container(
            width: 11,
            height: 11,
            decoration: const BoxDecoration(
              color: Tokens.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
        if (_open)
          Positioned(
            left: box.left + 2,
            top: box.top - 48,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Smaller',
                  onPressed: widget.onSmaller,
                  icon: const Icon(Icons.remove, size: 18),
                  color: Tokens.text,
                ),
                IconButton(
                  tooltip: 'Bigger',
                  onPressed: widget.onBigger,
                  icon: const Icon(Icons.add, size: 18),
                  color: Tokens.text,
                ),
                if (widget.canHide)
                  IconButton(
                    tooltip: 'Hide',
                    onPressed: widget.onHide,
                    icon: const Icon(Icons.visibility_off_outlined, size: 18),
                    color: Tokens.text,
                  ),
              ],
            ),
          ),
        Positioned(
          left: box.left,
          top: box.top - 48,
          width: box.width,
          child: Center(
            child: GestureDetector(
              key: widget.labelKey,
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _open = !_open),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  widget.label,
                  style: Tokens.display(
                    size: 13,
                    weight: FontWeight.w600,
                    ls: 0,
                    color: Tokens.systemLabelFg,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

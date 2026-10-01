import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/orbit_widgets.dart';
import 'control_layout.dart';
import 'control_overlay.dart';
import 'layout_store.dart';

/// Edit an on-screen layout in place: drag any control to move it, pick one
/// to resize or hide it, set overall opacity, then save — or reset to the
/// built-in default. What you see is exactly what you will play with.
///
/// Rules that keep a layout playable: controls stay inside the screen, keep
/// a minimum size, and Menu can never be hidden (it is the touch way out of
/// a game).
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

  /// The game's core, whose package may ship its own default layout.
  final String? coreId;

  /// The current game picture, shown behind the controls when available.
  final ui.Image? frame;

  @override
  State<LayoutEditorScreen> createState() => _LayoutEditorScreenState();
}

class _LayoutEditorScreenState extends State<LayoutEditorScreen> {
  late ControlLayout _layout;
  late final ControlLayout _builtin;
  final List<ControlSpec> _hidden = [];
  String? _selected;
  bool _dirty = false;

  /// Smallest a control may become, as a fraction of the shorter side.
  static const _minSide = 0.06;

  @override
  void initState() {
    super.initState();
    // "Default" is whatever Reset returns to: the core's own layout if its
    // package ships one, else the built-in.
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
    // Controls the user hid earlier are the built-in ones not in their copy.
    final present = {for (final c in _layout.controls) c.id};
    _hidden.addAll(_builtin.controls.where((c) => !present.contains(c.id)));
  }

  ControlSpec? get _sel =>
      _layout.controls.where((c) => c.id == _selected).firstOrNull;

  void _replace(ControlSpec next) => setState(() {
    _dirty = true;
    _layout = _layout.copyWith(
      controls: [for (final c in _layout.controls) c.id == next.id ? next : c],
    );
  });

  void _move(ControlSpec c, Offset delta, Size size) {
    final r = c.rect;
    final x = (r.x + delta.dx / size.width).clamp(0.0, 1 - r.w);
    final y = (r.y + delta.dy / size.height).clamp(0.0, 1 - r.h);
    _replace(
      c.copyWith(
        rect: r.copyWith(x: x, y: y),
      ),
    );
  }

  /// Scales the selected control about its centre, kept inside the screen.
  void _scale(ControlSpec c, double factor, Size size) {
    final r = c.rect;
    final minW = _minSide * size.shortestSide / size.width;
    final minH = _minSide * size.shortestSide / size.height;
    final w = (r.w * factor).clamp(minW, 1.0);
    final h = (r.h * factor).clamp(minH, 1.0);
    final cx = r.x + r.w / 2, cy = r.y + r.h / 2;
    final x = (cx - w / 2).clamp(0.0, 1 - w);
    final y = (cy - h / 2).clamp(0.0, 1 - h);
    _replace(c.copyWith(rect: NormRect(x, y, w, h)));
  }

  void _hide(ControlSpec c) => setState(() {
    _dirty = true;
    _hidden.add(c);
    _selected = null;
    _layout = _layout.copyWith(
      controls: [
        for (final x in _layout.controls)
          if (x.id != c.id) x,
      ],
    );
  });

  void _restoreHidden() => setState(() {
    _dirty = true;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final size = c.biggest;
            final frame = widget.frame;
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: ShellPainter(_layout.shell)),
                ),
                if (frame != null)
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.5,
                      child: CustomPaint(
                        painter: GamePicturePainter(frame, _layout.screen),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = null),
                  ),
                ),
                for (final ctl in _layout.controls)
                  Positioned.fromRect(
                    rect: ctl.rect.resolve(size.width, size.height),
                    child: GestureDetector(
                      key: ValueKey('edit-${ctl.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _selected = ctl.id),
                      onPanStart: (_) => setState(() => _selected = ctl.id),
                      onPanUpdate: (d) => _move(
                        _layout.controls.firstWhere((x) => x.id == ctl.id),
                        d.delta,
                        size,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _selected == ctl.id
                                ? Tokens.accent
                                : const Color(0x33DDE6F4),
                            width: _selected == ctl.id ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Opacity(
                          opacity: _layout.opacity,
                          child: ControlVisual(spec: ctl),
                        ),
                      ),
                    ),
                  ),
                // Over the picture area, which holds no controls, so the
                // toolbar never hides something the player wants to edit.
                Positioned.fromRect(
                  rect: _layout.screen.rect
                      .resolve(size.width, size.height)
                      .deflate(8),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: (size.width * _layout.screen.rect.w - 16).clamp(
                          280.0,
                          560.0,
                        ),
                        child: _toolbar(size),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _toolbar(Size size) {
    final sel = _sel;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: const Color(0xEE0F1825),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Tokens.lineStrong),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sel != null)
                Row(
                  children: [
                    Text(
                      _symbolNames[sel.label] ??
                          sel.label ??
                          (sel.type == ControlType.dpad ? 'D-pad' : sel.id),
                      style: Tokens.body(size: 13, weight: FontWeight.w600),
                    ),
                    const Spacer(),
                    _iconBtn(
                      Icons.remove,
                      'Smaller',
                      () => _scale(sel, 0.9, size),
                    ),
                    _iconBtn(Icons.add, 'Bigger', () => _scale(sel, 1.1, size)),
                    if (sel.input != 'menu')
                      _iconBtn(
                        Icons.visibility_off_outlined,
                        'Hide',
                        () => _hide(sel),
                      ),
                  ],
                )
              else
                Text(
                  'Drag a control to move it. Tap one to resize or hide it.',
                  textAlign: TextAlign.center,
                  style: Tokens.body(size: 12, color: Tokens.muted),
                ),
              Row(
                children: [
                  Text(
                    'Opacity',
                    style: Tokens.body(size: 12, color: Tokens.muted),
                  ),
                  Expanded(
                    child: Slider(
                      value: _layout.opacity,
                      min: 0.2,
                      max: 1,
                      onChanged: (v) => setState(() {
                        _dirty = true;
                        _layout = _layout.copyWith(opacity: v);
                      }),
                    ),
                  ),
                ],
              ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (_hidden.isNotEmpty)
                    TextButton(
                      onPressed: _restoreHidden,
                      child: Text('Show hidden (${_hidden.length})'),
                    ),
                  TextButton(
                    onPressed: _reset,
                    child: const Text('Reset to default'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  OrbitPrimary(
                    label: 'Save',
                    icon: Icons.check,
                    minHeight: 40,
                    onPressed: _dirty ? _save : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap) => IconButton(
    tooltip: tip,
    onPressed: onTap,
    icon: Icon(icon, size: 20, color: Tokens.text),
  );
}

/// Readable names for symbols the fonts cannot draw.
const _symbolNames = {
  '△': 'Triangle',
  '□': 'Square',
  '○': 'Circle',
  '×': 'Cross',
};

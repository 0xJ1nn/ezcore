import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'control_layout.dart';

/// Where the picture lands for [screen] inside an area of [size]: one rect,
/// or two for a split (DS) screen. Each part keeps the frame's aspect.
List<Rect> pictureRects(ScreenSpec screen, Size size, double frameAspect) {
  final box = screen.rect.resolve(size.width, size.height);
  Rect fit(Rect area, double aspect) {
    var w = area.width, h = w / aspect;
    if (h > area.height) {
      h = area.height;
      w = h * aspect;
    }
    return Rect.fromCenter(center: area.center, width: w, height: h);
  }

  if (screen.split == 1) return [fit(box, frameAspect)];
  // Each half of a stacked frame is twice as wide as tall, relatively.
  final partAspect = frameAspect * 2;
  if (screen.arrange == 'side') {
    final gap = box.width * screen.gap;
    final w = (box.width - gap) / 2;
    return [
      fit(Rect.fromLTWH(box.left, box.top, w, box.height), partAspect),
      fit(
        Rect.fromLTWH(box.left + w + gap, box.top, w, box.height),
        partAspect,
      ),
    ];
  }
  final gap = box.height * screen.gap;
  final h = (box.height - gap) / 2;
  return [
    fit(Rect.fromLTWH(box.left, box.top, box.width, h), partAspect),
    fit(Rect.fromLTWH(box.left, box.top + h + gap, box.width, h), partAspect),
  ];
}

/// Where [p] falls in the core's frame, as fractions 0..1 of its width and
/// height, or null when it is not on the picture. For a split (DS) screen a
/// point on the second panel maps into the frame's lower half, whichever
/// way the panels are arranged.
Offset? frameCoordinate(
  ScreenSpec screen,
  Size size,
  double frameAspect,
  Offset p,
) {
  final rects = pictureRects(screen, size, frameAspect);
  for (var k = 0; k < rects.length; k++) {
    final r = rects[k];
    if (!r.contains(p)) continue;
    final u = ((p.dx - r.left) / r.width).clamp(0.0, 1.0);
    final v = ((p.dy - r.top) / r.height).clamp(0.0, 1.0);
    return rects.length == 1 ? Offset(u, v) : Offset(u, (k + v) / 2);
  }
  return null;
}

/// A frame fraction (0..1) as libretro pointer coordinates (-32767..32767).
(int, int) toPointer(Offset frame) => (
  ((frame.dx * 2 - 1) * 32767).round(),
  ((frame.dy * 2 - 1) * 32767).round(),
);

/// Draws the core's frame into the layout's screen area, pixel-crisp.
class GamePicturePainter extends CustomPainter {
  GamePicturePainter(this.image, this.screen);
  final ui.Image image;
  final ScreenSpec screen;

  @override
  void paint(Canvas canvas, Size size) {
    final w = image.width.toDouble(), h = image.height.toDouble();
    final paint = Paint()..filterQuality = FilterQuality.none;
    final dest = pictureRects(screen, size, w / h);
    if (screen.split == 1) {
      canvas.drawImageRect(image, Rect.fromLTWH(0, 0, w, h), dest[0], paint);
      return;
    }
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, w, h / 2), dest[0], paint);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, h / 2, w, h / 2),
      dest[1],
      paint,
    );
  }

  @override
  bool shouldRepaint(GamePicturePainter old) =>
      old.image != image || old.screen != screen;
}

/// The device body behind everything: a fill, rounded corners, and for a
/// clamshell a darker hinge band. Declarative; nothing else is drawn.
class ShellPainter extends CustomPainter {
  ShellPainter(this.shell);
  final ShellSpec shell;

  @override
  void paint(Canvas canvas, Size size) {
    final color = shell.color;
    if (color == null) return;
    final r = shell.radius * size.shortestSide;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r)),
      Paint()..color = Color(color),
    );
    final hinge = shell.hinge;
    if (hinge != null) {
      final y = hinge * size.height;
      canvas.drawRect(
        Rect.fromLTWH(0, y - 5, size.width, 10),
        Paint()..color = const Color(0x33000000),
      );
    }
  }

  @override
  bool shouldRepaint(ShellPainter old) => old.shell != shell;
}

/// The touch layer. One [Listener] tracks every pointer and decides which
/// control it is on, so a thumb can slide from B to A or around the d-pad,
/// several fingers work at once, and lifting a finger always releases what
/// it held. [onInput] receives RetroPad names (`a`, `up`, …) as they go down
/// and up; host inputs (`menu`, `fast_forward`) arrive as presses only.
class ControlOverlay extends StatefulWidget {
  const ControlOverlay({
    super.key,
    required this.layout,
    required this.onInput,
    this.onHostInput,
    this.onTouch,
    this.toFrame,
    this.onPicture,
  });

  final ControlLayout layout;
  final void Function(String input, bool pressed) onInput;
  final void Function(String input)? onHostInput;

  /// Called on every new press, for haptics.
  final VoidCallback? onTouch;

  /// Maps a point to the core's frame (0..1), or null off the picture. With
  /// [onPicture], a finger that lands on the picture rather than a control
  /// becomes the core's pointer — the DS touchscreen, for example.
  final Offset? Function(Offset local, Size size)? toFrame;
  final void Function(Offset frame, bool pressed)? onPicture;

  @override
  State<ControlOverlay> createState() => ControlOverlayState();
}

class ControlOverlayState extends State<ControlOverlay> {
  /// What each pointer is currently holding.
  final Map<int, Set<String>> _byPointer = {};
  Size _size = Size.zero;

  Set<String> get held => {for (final s in _byPointer.values) ...s};

  /// Inputs a pointer at [p] presses.
  Set<String> inputsAt(Offset p) {
    for (final c in widget.layout.controls) {
      final r = c.rect.resolve(_size.width, _size.height);
      if (!r.contains(p)) continue;
      if (c.type == ControlType.button) return {c.input!};
      // D-pad: direction from the centre, with a dead zone and diagonals.
      final nx = (p.dx - r.center.dx) / (r.shortestSide / 2);
      final ny = (p.dy - r.center.dy) / (r.shortestSide / 2);
      return {
        if (ny < -0.3) 'up',
        if (ny > 0.3) 'down',
        if (nx < -0.3) 'left',
        if (nx > 0.3) 'right',
      };
    }
    return const {};
  }

  void _set(int pointer, Set<String> next) {
    final before = held;
    final prev = _byPointer[pointer] ?? const <String>{};
    if (next.isEmpty) {
      _byPointer.remove(pointer);
    } else {
      _byPointer[pointer] = next;
    }
    final after = held;
    // Releases first: sliding from B to A must never hold both at once.
    for (final i in before.difference(after)) {
      if (!hostInputs.contains(i)) widget.onInput(i, false);
    }
    var newPress = false;
    for (final i in after.difference(before)) {
      if (hostInputs.contains(i)) {
        if (!prev.contains(i)) widget.onHostInput?.call(i);
      } else {
        widget.onInput(i, true);
      }
      newPress = true;
    }
    if (newPress) widget.onTouch?.call();
    setState(() {});
  }

  /// The pointer currently touching the picture, and where it last was.
  int? _picture;
  Offset _lastFrame = Offset.zero;

  void _release(int pointer) {
    if (pointer == _picture) {
      _picture = null;
      widget.onPicture?.call(_lastFrame, false);
      return;
    }
    _set(pointer, const {});
  }

  /// Releases everything (the session paused, the layout changed).
  void releaseAll() {
    if (_picture != null) _release(_picture!);
    for (final p in _byPointer.keys.toList()) {
      _set(p, const {});
    }
  }

  @override
  void didUpdateWidget(ControlOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout) releaseAll();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _size = Size(c.maxWidth, c.maxHeight);
        final pressed = held;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) {
            final hits = inputsAt(e.localPosition);
            final frame = hits.isEmpty
                ? widget.toFrame?.call(e.localPosition, _size)
                : null;
            if (frame != null && widget.onPicture != null && _picture == null) {
              _picture = e.pointer;
              _lastFrame = frame;
              widget.onPicture!(frame, true);
              return;
            }
            _set(e.pointer, hits);
          },
          onPointerMove: (e) {
            if (e.pointer == _picture) {
              final frame = widget.toFrame?.call(e.localPosition, _size);
              if (frame != null) {
                _lastFrame = frame;
                widget.onPicture!(frame, true);
              }
              return;
            }
            _set(e.pointer, inputsAt(e.localPosition));
          },
          onPointerUp: (e) => _release(e.pointer),
          onPointerCancel: (e) => _release(e.pointer),
          child: Opacity(
            opacity: widget.layout.opacity,
            child: Stack(
              children: [
                for (final ctl in widget.layout.controls)
                  Positioned.fromRect(
                    rect: ctl.rect.resolve(_size.width, _size.height),
                    child: IgnorePointer(
                      child: ControlVisual(spec: ctl, pressed: pressed),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// How one control looks, pressed or not. Shared by the game overlay and
/// the layout editor so editing shows exactly what playing will.
class ControlVisual extends StatelessWidget {
  const ControlVisual({super.key, required this.spec, this.pressed = const {}});
  final ControlSpec spec;
  final Set<String> pressed;

  @override
  Widget build(BuildContext context) => spec.type == ControlType.dpad
      ? _DPad(pressed: pressed)
      : _Button(spec: spec, down: pressed.contains(spec.input));
}

class _Button extends StatelessWidget {
  const _Button({required this.spec, required this.down});
  final ControlSpec spec;
  final bool down;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final round = spec.shape == ControlShape.circle;
        final side = c.biggest.shortestSide;
        final box = round ? Size.square(side) : c.biggest;
        final radius = switch (spec.shape) {
          ControlShape.circle => side / 2,
          ControlShape.pill => box.height / 2,
          ControlShape.rounded => 10.0,
        };
        return Center(
          child: Semantics(
            button: true,
            label: spec.label ?? spec.input,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 60),
              width: box.width,
              height: box.height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: down ? const Color(0xCC007BFF) : const Color(0x5517263A),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: down
                      ? const Color(0xFF3B8BFF)
                      : const Color(0x66DDE6F4),
                  width: 1.5,
                ),
              ),
              child: _sonySymbols.contains(spec.label)
                  ? CustomPaint(
                      size: Size.square(side * 0.42),
                      painter: _SymbolPainter(spec.label!),
                    )
                  : FittedBox(
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          spec.label ?? spec.input ?? '',
                          style: Tokens.display(
                            size: round ? side * 0.36 : box.height * 0.42,
                            weight: FontWeight.w600,
                            ls: 0,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _DPad extends StatelessWidget {
  const _DPad({required this.pressed});
  final Set<String> pressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Semantics(
          label: 'Directional pad',
          child: CustomPaint(painter: _DPadPainter(pressed)),
        ),
      ),
    );
  }
}

class _DPadPainter extends CustomPainter {
  _DPadPainter(this.pressed);
  final Set<String> pressed;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final arm = s / 3;
    final idle = Paint()..color = const Color(0x5517263A);
    final down = Paint()..color = const Color(0xCC007BFF);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0x66DDE6F4);
    final arms = {
      'up': Rect.fromLTWH(arm, 0, arm, arm),
      'down': Rect.fromLTWH(arm, arm * 2, arm, arm),
      'left': Rect.fromLTWH(0, arm, arm, arm),
      'right': Rect.fromLTWH(arm * 2, arm, arm, arm),
    };
    final centre = Rect.fromLTWH(arm, arm, arm, arm);
    final cross = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(arm, 0, arm, s),
          const Radius.circular(8),
        ),
      )
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, arm, s, arm),
          const Radius.circular(8),
        ),
      );
    canvas.drawPath(cross, idle);
    for (final e in arms.entries) {
      if (pressed.contains(e.key)) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(e.value, const Radius.circular(8)),
          down,
        );
      }
    }
    canvas.drawRect(centre, idle);
    canvas.drawPath(cross, edge);
  }

  @override
  bool shouldRepaint(_DPadPainter old) =>
      old.pressed.length != pressed.length || !old.pressed.containsAll(pressed);
}

/// PlayStation face symbols, drawn rather than typeset: the app's fonts do
/// not carry these glyphs, and a missing glyph renders as a box.
const _sonySymbols = {'△', '□', '○', '×'};

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.symbol);
  final String symbol;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.12
      ..strokeCap = StrokeCap.round
      ..color = Tokens.text;
    final c = size.center(Offset.zero);
    switch (symbol) {
      case '△':
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - s * 0.42)
            ..lineTo(c.dx + s * 0.46, c.dy + s * 0.36)
            ..lineTo(c.dx - s * 0.46, c.dy + s * 0.36)
            ..close(),
          paint,
        );
      case '□':
        canvas.drawRect(
          Rect.fromCenter(center: c, width: s * 0.78, height: s * 0.78),
          paint,
        );
      case '○':
        canvas.drawCircle(c, s * 0.42, paint);
      case '×':
        final d = s * 0.38;
        canvas.drawLine(c.translate(-d, -d), c.translate(d, d), paint);
        canvas.drawLine(c.translate(d, -d), c.translate(-d, d), paint);
    }
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.symbol != symbol;
}

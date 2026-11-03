import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The Orbit space scene behind the whole app (§7.1).
///
/// Base: one elliptical radial gradient. Two tiled star layers, the first
/// drifting. A very large planet arc whose rim catches the light, and a
/// bottom vignette that keeps the chrome legible.
///
/// Two layers, on purpose:
///
/// * [SpaceScenePainter] paints the expensive geometry — the gradient, the
///   star tiles, the planet — and repaints only when its inputs change.
/// * [StarfieldPainter] repaints every animation frame with the drift, but
///   it only draws a handful of dots, so it stays cheap.
///
/// Motion is optional. When the `motion` setting is off, or the OS asks for
/// reduced motion, the controller never ticks: no frames are scheduled and
/// the scene holds still at `t = 0`.
class SpaceBackdrop extends StatefulWidget {
  const SpaceBackdrop({
    super.key,
    this.motion = true,
    this.planetTop = 730,
    this.tint,
    this.tintOpacity = 0.38,
  });

  /// Mirrors the user's "Ambient motion" preference.
  final bool motion;

  /// Logical y of the 3000 px planet's top edge. Per screen (§7.1).
  final double planetTop;

  /// The selected game's system tint, upper right; null leaves the sky.
  final Color? tint;
  final double tintOpacity;

  @override
  State<SpaceBackdrop> createState() => _SpaceBackdropState();
}

class _SpaceBackdropState extends State<SpaceBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _reduced = false;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      // The design's star drift is 120 s; a slow loop keeps the sky alive.
      duration: const Duration(seconds: 120),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    // Always reconcile, not only when the flag changes: the very first
    // call has to start the animation too.
    _sync();
  }

  @override
  void didUpdateWidget(SpaceBackdrop old) {
    super.didUpdateWidget(old);
    if (widget.motion != old.motion) _sync();
  }

  void _sync() {
    final shouldRun = widget.motion && !_reduced;
    if (shouldRun == _animating) return;
    _animating = shouldRun;
    if (shouldRun) {
      _ctrl.repeat();
    } else {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(painter: SkyPainter())),
          RepaintBoundary(
            child: AnimatedBuilder(
              // A stopped controller never notifies, so this layer costs
              // nothing while motion is off.
              animation: _ctrl,
              builder: (context, _) =>
                  CustomPaint(painter: StarfieldPainter(t: _ctrl.value)),
            ),
          ),
          RepaintBoundary(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: widget.planetTop),
              duration: Tokens.sceneDur,
              curve: Tokens.ease,
              builder: (context, planetTop, _) => CustomPaint(
                painter: SpaceScenePainter(
                  planetTop: planetTop,
                  tint: widget.tint,
                  tintOpacity: widget.tintOpacity,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A fixed star in a repeating tile.
class _Star {
  const _Star(this.x, this.y, this.r, this.color);
  final double x;
  final double y;
  final double r;
  final Color color;
}

/// Layer 1: 380×260 tile, drifting.
const _layer1 = <_Star>[
  _Star(20, 30, 1, Tokens.starHi),
  _Star(140, 90, 1, Tokens.starDim),
  _Star(260, 160, 1.5, Tokens.planetRimHi),
  _Star(330, 50, 1, Tokens.starDim),
  _Star(80, 220, 1, Tokens.starHi),
];
const _layer1Tile = Size(380, 260);

/// Layer 2: 610×420 tile, still.
const _layer2 = <_Star>[
  _Star(60, 120, 1, Tokens.planetRimHi),
  _Star(400, 40, 1, Tokens.starDim),
  _Star(520, 300, 2, Tokens.starHi),
];
const _layer2Tile = Size(610, 420);

/// The sky gradient, painted once beneath the drifting stars.
class SkyPainter extends CustomPainter {
  const SkyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;

    // radial-gradient(120% 80% at 70% -10%,
    //   #10243F 0%, #091324 40%, #05080F 75%).
    canvas.save();
    canvas.translate(w * 0.70, -h * 0.10);
    final rx = w * 1.20;
    final ry = h * 0.80;
    canvas.scale(1, ry / rx);
    final skyRect = Rect.fromCircle(center: Offset.zero, radius: rx);
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Tokens.spaceNebula, Tokens.spaceMid, Tokens.spaceDeep],
          stops: [0.0, 0.40, 0.75],
        ).createShader(skyRect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SkyPainter oldDelegate) => false;
}

/// Static half of the scene: room tint, planet, vignette.
class SpaceScenePainter extends CustomPainter {
  const SpaceScenePainter({
    this.planetTop = 730,
    this.tint,
    this.tintOpacity = 0.38,
  });

  final double planetTop;
  final Color? tint;
  final double tintOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;

    // --- Room tint: 1100×700 ellipse at the top right, blurred 110 px.
    final tintColor = tint;
    if (tintColor != null) {
      canvas.drawOval(
        Rect.fromLTWH(w - 840, -360, 1100, 700),
        Paint()
          ..color = tintColor.withValues(alpha: tintOpacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 55),
      );
    }

    // --- Planet: a 3000 px circle centred horizontally. Body #071120 to
    // 96%, #0B1B33 at 99.2%, #3B8BFF rim at 99.7%.
    _planet(canvas, size);

    // --- Bottom vignette keeps the interface legible over the scene.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0x8C04070D)],
          stops: [0.60, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  void _planet(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, planetTop + 1500);
    const radius = 1500.0;

    // Outer atmosphere: 0 0 120px 10px rgba(59,139,255,.28). Drawn before
    // the body so only the outside half of the glow survives.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 24
        ..color = const Color(0x473B8BFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
    );

    final disc = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Tokens.planetBody,
            Tokens.planetBody,
            Color(0xFF0B1B33),
            Tokens.planetRim,
            Color(0x003B8BFF),
          ],
          stops: [0.0, 0.96, 0.992, 0.997, 1.0],
        ).createShader(disc),
    );

    // Inset light from the top edge: inset 0 40px 80px rgba(59,139,255,.18).
    canvas.save();
    canvas.clipPath(Path()..addOval(disc));
    final inset = Rect.fromLTWH(
      size.width / 2 - radius,
      planetTop,
      radius * 2,
      200,
    );
    canvas.drawRect(
      inset,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x2E3B8BFF), Colors.transparent],
        ).createShader(inset),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SpaceScenePainter oldDelegate) =>
      oldDelegate.planetTop != planetTop ||
      oldDelegate.tint != tint ||
      oldDelegate.tintOpacity != tintOpacity;
}

/// Animated half of the scene: the drifting star layer.
class StarfieldPainter extends CustomPainter {
  const StarfieldPainter({required this.t});

  /// Animation position in `0..1`.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // translateX 0 → -200 px, alternate (a cosine triangle over the loop).
    final drift = -200 * (0.5 - 0.5 * math.cos(t * math.pi * 2));

    // The design's parallax container is inset −40 px on the top and left,
    // so the star tiles start 40 px above and left of the stage.
    const origin = -40.0;

    void layer(List<_Star> stars, Size tile, double offset, double opacity) {
      final startX = -tile.width + ((offset + origin) % tile.width);
      for (var x = startX; x < size.width + tile.width; x += tile.width) {
        for (
          var y = -tile.height + origin;
          y < size.height + tile.height;
          y += tile.height
        ) {
          for (final s in stars) {
            canvas.drawCircle(
              Offset(x + s.x, y + s.y),
              s.r,
              Paint()..color = s.color.withValues(alpha: opacity),
            );
          }
        }
      }
    }

    layer(_layer1, _layer1Tile, drift, 0.9);
    layer(_layer2, _layer2Tile, 0, 0.5);
  }

  @override
  bool shouldRepaint(StarfieldPainter oldDelegate) => oldDelegate.t != t;
}

// ---------------------------------------------------------------------------
// Room tint hues (§3.1): oklch(0.42 0.11 H) per system.
// ---------------------------------------------------------------------------

const _systemHues = <String, double>{
  'nes': 25,
  'snes': 300,
  'n64': 150,
  'gb': 115,
  'gbc': 345,
  'gba': 270,
  'nds': 215,
  'psx': 245,
  'dc': 55,
  'psp': 190,
};

/// The ambient room tint for [system], or null when the system is unknown.
Color? systemTint(String system) {
  final hue = _systemHues[system];
  if (hue == null) return null;
  return _oklchToColor(0.42, 0.11, hue);
}

Color _oklchToColor(double lightness, double chroma, double hueDegrees) {
  final h = hueDegrees * math.pi / 180;
  final a = chroma * math.cos(h);
  final b = chroma * math.sin(h);

  final l0 = lightness + 0.3963377774 * a + 0.2158037573 * b;
  final m0 = lightness - 0.1055613458 * a - 0.0638541728 * b;
  final s0 = lightness - 0.0894841775 * a - 1.2914855480 * b;

  final l = l0 * l0 * l0;
  final m = m0 * m0 * m0;
  final s = s0 * s0 * s0;

  final r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  final g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  final bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

  int channel(double linear) {
    final c = linear <= 0.0031308
        ? 12.92 * linear
        : 1.055 * math.pow(linear, 1 / 2.4) - 0.055;
    return (c.clamp(0.0, 1.0) * 255).round();
  }

  return Color.fromARGB(255, channel(r), channel(g), channel(bl));
}

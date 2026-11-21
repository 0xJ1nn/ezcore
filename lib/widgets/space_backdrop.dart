import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The studio-plate backdrop: a planet limb low on the right, a drifting
/// nebula wash and twinkling stars — exactly the reference plate's scene.
///
/// Two layers, on purpose:
///
/// * [SpaceScenePainter] paints the expensive geometry — gradients, the
///   planet, the ridges — exactly once.
/// * [StarfieldPainter] repaints on every animation frame, but it only
///   draws a small set of stars, edge-light pulses, orbital signals, and a
///   meteor, so it stays cheap.
///
/// Motion is optional. When the `motion` setting is off, or the OS asks
/// for reduced motion, the controller never ticks: no frames are
/// scheduled and the scene holds still at `t = 0`.
class SpaceBackdrop extends StatefulWidget {
  const SpaceBackdrop({super.key, this.motion = true});

  /// Mirrors the user's "Ambient motion" preference.
  final bool motion;

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
      // One full cycle of twinkle + a single meteor pass.
      duration: const Duration(seconds: 24),
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
          const RepaintBoundary(
            child: CustomPaint(painter: SpaceScenePainter()),
          ),
          RepaintBoundary(
            child: AnimatedBuilder(
              // A stopped controller never notifies, so this layer costs
              // nothing while motion is off.
              animation: _ctrl,
              builder: (context, _) =>
                  CustomPaint(painter: StarfieldPainter(t: _ctrl.value)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A star: normalised position, size, brightness tier and twinkle phase.
class _Star {
  const _Star(this.x, this.y, this.r, this.tier, this.phase);
  final double x;
  final double y;
  final double r;
  final int tier;
  final double phase;
}

/// Deterministic star field — generated once, identical on every launch
/// and on every device, so the sky never reshuffles itself on rebuild.
final List<_Star> _sky = _buildSky();

List<_Star> _buildSky() {
  // Fixed-seed LCG: a plain `Random()` would differ per run and make the
  // backdrop look different every launch.
  var seed = 0x1F2E3D4C;
  double next() {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    return seed / 0x7FFFFFFF;
  }

  final out = <_Star>[];
  for (var i = 0; i < 140; i++) {
    // Bias stars toward the top: the planet fills the lower band.
    final y = math.pow(next(), 1.5).toDouble();
    final tierRoll = next();
    final tier = tierRoll > 0.93 ? 2 : (tierRoll > 0.7 ? 1 : 0);
    final r = switch (tier) {
      2 => 1.5 + next() * 0.7,
      1 => 0.9 + next() * 0.5,
      _ => 0.5 + next() * 0.35,
    };
    out.add(_Star(next(), y, r, tier, next() * math.pi * 2));
  }
  return out;
}

/// Build a sampled circular arc instead of using a huge stroked circle.
/// Some Linux Impeller versions fill very large `drawCircle` strokes, which
/// turns a subtle atmosphere into a full-window wash. Paths stay predictable
/// across desktop renderers.
Path _orbitArc(
  Offset center,
  double radius,
  double start,
  double end, {
  int segments = 48,
}) {
  final path = Path();
  for (var i = 0; i <= segments; i++) {
    final angle = start + (end - start) * i / segments;
    final point = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  return path;
}

/// Static half of the scene: sky, nebula, planet limb, vignette.
class SpaceScenePainter extends CustomPainter {
  const SpaceScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;

    // --- Sky: deep zenith into a slightly warmer mid field.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Tokens.spaceDeep, Tokens.spaceMid, Tokens.spaceDeep],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );

    // --- Nebula wash: two soft clouds keep the upper field alive without
    // competing with the interface.
    _wash(
      canvas,
      size,
      center: Alignment(w * 0.78, h * 0.12),
      radius: math.max(w, h) * 0.72,
      color: Tokens.spaceNebula.withValues(alpha: 0.72),
    );
    _wash(
      canvas,
      size,
      center: Alignment(w * 0.12, h * 0.34),
      radius: math.max(w, h) * 0.55,
      color: const Color(0xFF0B1B33).withValues(alpha: 0.72),
    );

    // --- The one planet limb, low on the right, as the reference plate draws
    // it. No beams, companion body or ridges: they are not in the design.
    _planet(canvas, size);

    // --- Vignette keeps the UI legible over the scene.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: [Colors.transparent, Tokens.bg.withValues(alpha: 0.55)],
          stops: const [0.55, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  void _wash(
    Canvas canvas,
    Size size, {
    required Alignment center,
    required double radius,
    required Color color,
  }) {
    final paint = Paint()
      ..shader =
          RadialGradient(
            colors: [color, Colors.transparent],
            stops: const [0.0, 1.0],
          ).createShader(
            Rect.fromCircle(
              center: center.withinRect(Offset.zero & size),
              radius: radius,
            ),
          );
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _planet(Canvas canvas, Size size) {
    // Keep the horizon in the lower quarter so it frames the library instead
    // of running through covers, labels, and the selected-game panel.
    final c = Offset(size.width * 0.75, size.height * 2.0);
    final r = size.height * 1.10;
    final bodyTop = math.max(0.0, c.dy - r);
    final bodyRect = Rect.fromLTWH(
      0,
      bodyTop,
      size.width,
      size.height - bodyTop,
    );

    // Keep the shader in viewport coordinates. A shader based on the
    // off-screen disc rectangle is liable to be mis-clipped by Impeller.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF12233C), Tokens.planetBody],
          stops: const [0.0, 0.45],
        ).createShader(bodyRect),
    );

    // Draw only sampled orbital paths. Large `drawCircle` strokes are not
    // safe on every Linux renderer: some fill the whole circle and turn the
    // atmosphere into a pale full-width wash.
    const start = -2.35;
    const end = -0.79;
    final limb = _orbitArc(c, r, start, end);
    final outerTrack = _orbitArc(c, r * 1.035, start - 0.05, end + 0.05);
    final innerTrack = _orbitArc(c, r * 0.965, start + 0.06, end - 0.06);

    canvas.drawPath(
      outerTrack,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Tokens.planetRim.withValues(alpha: 0.22),
    );
    canvas.drawPath(
      innerTrack,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Tokens.planetRimHi.withValues(alpha: 0.16),
    );
    canvas.drawPath(
      limb,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = Tokens.planetRim.withValues(alpha: 0.08),
    );
    canvas.drawPath(
      limb,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Tokens.planetRimHi.withValues(alpha: 0.62),
    );

    // A few low-contrast latitude traces make the body read as a world,
    // not a flat blue fill.
    for (final scale in const [0.72, 0.84, 0.93]) {
      final trace = _orbitArc(c, r * scale, -2.18, -0.96, segments: 32);
      canvas.drawPath(
        trace,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = Tokens.planetRim.withValues(alpha: 0.10),
      );
    }
  }

  @override
  bool shouldRepaint(SpaceScenePainter oldDelegate) => false;
}

/// Animated half of the scene: star twinkle and parallax drift only. The
/// reference plate has no beams, orbital signals or meteors.
class StarfieldPainter extends CustomPainter {
  const StarfieldPainter({required this.t});

  /// Animation position in `0..1`.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Minimum scale factor: a 0-width window would otherwise draw stars
    // stacked on the same pixel.
    final unit = math.min(size.width, size.height) / 800;
    for (final s in _sky) {
      // Gentle twinkle plus a barely perceptible parallax drift.
      final tw = 0.55 + 0.45 * math.sin((t * math.pi * 2) + s.phase);
      final x = (s.x + t * (0.008 + s.tier * 0.003)) % 1.0;
      final y = (s.y + t * (0.002 + s.tier * 0.001)) % 1.0;
      final paint = Paint()
        ..color = (s.tier == 2 ? Tokens.starHi : Tokens.starDim).withValues(
          alpha: (s.tier == 2 ? 0.95 : 0.55) * tw,
        )
        ..maskFilter = s.tier == 2 && unit > 0.6
            ? const MaskFilter.blur(BlurStyle.normal, 1.4)
            : null;
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        s.r * math.max(unit, 0.45),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(StarfieldPainter oldDelegate) => oldDelegate.t != t;
}

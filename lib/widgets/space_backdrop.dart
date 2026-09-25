import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The studio-plate backdrop: a planet limb at the bottom edge, layered
/// mountain silhouettes, drifting nebula wash, twinkling stars and an
/// occasional meteor.
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

Offset _orbitPoint(
  Offset center,
  double radius,
  double progress,
  double start,
  double end,
) {
  final angle = start + (end - start) * progress;
  return Offset(
    center.dx + radius * math.cos(angle),
    center.dy + radius * math.sin(angle),
  );
}

/// Static half of the scene: sky, nebula, planet limb, ridges, vignette.
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

    // --- Two quiet diagonal light beams echo the ORBIT edge language.
    _diagonalBeam(canvas, size, x: 0.77, width: 0.16, alpha: 0.10);
    _diagonalBeam(canvas, size, x: 0.91, width: 0.07, alpha: 0.06);

    // --- Ringed companion planet, top right (the plate's second body).
    _companionPlanet(canvas, size);

    // --- Main planet limb and orbital tracks across the lower edge.
    _planet(canvas, size);

    // --- Two mountain silhouettes anchor the frame bottom.
    _ridge(canvas, size, far: true);
    _ridge(canvas, size, far: false);

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

  void _diagonalBeam(
    Canvas canvas,
    Size size, {
    required double x,
    required double width,
    required double alpha,
  }) {
    final top = Offset(size.width * x, -size.height * 0.12);
    final bottom = Offset(size.width * (x - 0.22), size.height * 1.08);
    final half = size.width * width * 0.5;
    final path = Path()
      ..moveTo(top.dx - half, top.dy)
      ..lineTo(top.dx + half, top.dy)
      ..lineTo(bottom.dx + half * 1.5, bottom.dy)
      ..lineTo(bottom.dx - half * 1.5, bottom.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Colors.transparent,
            Tokens.accent.withValues(alpha: alpha),
            Colors.transparent,
          ],
          stops: const [0.0, 0.52, 1.0],
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

  void _companionPlanet(Canvas canvas, Size size) {
    // Small and dim on purpose: it is a distant body, not a UI element.
    // Anything larger competes with the search field in the top corner.
    final unit = math.min(size.width, size.height);
    final c = Offset(size.width * 0.90, size.height * 0.07);
    final r = unit * 0.085;
    const fade = 0.55;

    // Body: dark disc with a lit upper-left edge.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.0)
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF17345C).withValues(alpha: fade),
            const Color(0xFF060A12).withValues(alpha: fade),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Atmosphere rim.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Tokens.planetRim.withValues(alpha: 0.30)
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Tokens.planetRimHi.withValues(alpha: 0.45),
            Tokens.planetRim.withValues(alpha: 0.25),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r * 1.2)),
    );
    // Rings: two thin ellipses give the distant body a clear orbital read.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.32);
    canvas.translate(-c.dx, -c.dy);
    for (final scale in const [2.9, 3.35]) {
      canvas.drawOval(
        Rect.fromCenter(center: c, width: r * scale, height: r * 0.72),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = scale > 3 ? 0.7 : 1.0
          ..color = Tokens.planetRim.withValues(alpha: scale > 3 ? 0.14 : 0.28),
      );
    }
    final moon = Offset(c.dx + r * 1.45, c.dy - r * 0.18);
    canvas.drawCircle(
      moon,
      2.2,
      Paint()..color = Tokens.planetRimHi.withValues(alpha: 0.72),
    );
    canvas.restore();
  }

  void _planet(Canvas canvas, Size size) {
    // Keep the horizon in the lower quarter so it frames the library instead
    // of running through covers, labels, and the selected-game panel.
    final c = Offset(size.width * 0.42, size.height * 1.85);
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

  void _ridge(Canvas canvas, Size size, {required bool far}) {
    final h = size.height;
    final baseY = far ? h * 0.94 : h * 1.02;
    final amp = far ? h * 0.10 : h * 0.14;
    // Fixed phases: far ridge peaks are higher and wider, near ridge jagged.
    final peaks = far
        ? const [0.0, 0.14, 0.23, 0.36, 0.5, 0.63, 0.78, 0.9, 1.0]
        : const [0.0, 0.08, 0.17, 0.28, 0.41, 0.52, 0.66, 0.8, 0.92, 1.0];
    final heights = far
        ? const [0.0, 0.55, 0.32, 0.78, 0.45, 0.68, 0.35, 0.6, 0.0]
        : const [0.0, 0.7, 0.42, 0.95, 0.5, 0.8, 0.38, 0.72, 0.55, 0.0];

    final path = Path()..moveTo(0, size.height);
    for (var i = 0; i < peaks.length; i++) {
      final x = peaks[i] * size.width;
      final y = baseY - heights[i] * amp;
      if (i == 0) {
        path.lineTo(x, y);
      } else {
        final prevX = peaks[i - 1] * size.width;
        final prevY = baseY - heights[i - 1] * amp;
        // Control point above the midpoint: soft mountain shoulders.
        final midX = (prevX + x) / 2;
        final midY = math.min(prevY, y) - amp * 0.12;
        path.quadraticBezierTo(midX, midY, x, y);
      }
    }
    path
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = far ? Tokens.ridgeFar : Tokens.ridgeNear
        ..style = PaintingStyle.fill,
    );

    // Moonlit edge along the crest of the near ridge.
    if (!far) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Tokens.planetRim.withValues(alpha: 0.22),
      );
    }
  }

  @override
  bool shouldRepaint(SpaceScenePainter oldDelegate) => false;
}

/// Animated half of the scene: edge-light breathing, orbital signals,
/// star twinkle, parallax drift, and a periodic meteor.
class StarfieldPainter extends CustomPainter {
  const StarfieldPainter({required this.t});

  /// Animation position in `0..1`.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _edgeLights(canvas, size);

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
    _orbitalSignals(canvas, size);
    _meteor(canvas, size);
  }

  void _edgeLights(Canvas canvas, Size size) {
    final phase = t * math.pi * 2;
    for (var i = 0; i < 2; i++) {
      final baseX = i == 0 ? 0.77 : 0.91;
      final drift = math.sin(phase + i * 1.7) * 0.012;
      final x = baseX + drift;
      final alpha =
          0.035 + 0.035 * (0.5 + 0.5 * math.sin(phase + i * math.pi * 0.8));
      final top = Offset(size.width * x, -size.height * 0.12);
      final bottom = Offset(size.width * (x - 0.22), size.height * 1.08);
      final half = size.width * (i == 0 ? 0.075 : 0.035);
      final path = Path()
        ..moveTo(top.dx - half, top.dy)
        ..lineTo(top.dx + half, top.dy)
        ..lineTo(bottom.dx + half * 1.5, bottom.dy)
        ..lineTo(bottom.dx - half * 1.5, bottom.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = Tokens.accent.withValues(alpha: alpha),
      );
      canvas.drawLine(
        top,
        bottom,
        Paint()
          ..strokeWidth = i == 0 ? 1.1 : 0.7
          ..color = Tokens.planetRimHi.withValues(alpha: alpha * 1.8),
      );
    }
  }

  void _orbitalSignals(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.42, size.height * 1.85);
    final radius = size.height * 1.10;
    const start = -2.35;
    const end = -0.79;

    // Three small signals travel around the visible limb at different phases.
    for (var i = 0; i < 3; i++) {
      final progress = (t * 0.72 + i / 3) % 1.0;
      final point = _orbitPoint(center, radius * 1.035, progress, start, end);
      final tail = _orbitPoint(
        center,
        radius * 1.035,
        (progress - 0.035) % 1.0,
        start,
        end,
      );
      canvas.drawLine(
        tail,
        point,
        Paint()
          ..strokeWidth = 1.2
          ..color = Tokens.planetRimHi.withValues(alpha: 0.30),
      );
      canvas.drawCircle(
        point,
        i == 0 ? 2.4 : 1.7,
        Paint()..color = Tokens.planetRimHi.withValues(alpha: 0.72),
      );
    }

    // A second, smaller signal loops around the companion body.
    final companion = Offset(size.width * 0.90, size.height * 0.07);
    final orbit = (t * 0.9 + 0.15) * math.pi * 2;
    final companionPoint = Offset(
      companion.dx + math.cos(orbit) * size.width * 0.018,
      companion.dy + math.sin(orbit) * size.height * 0.018,
    );
    canvas.drawCircle(
      companionPoint,
      1.8,
      Paint()..color = Tokens.starHi.withValues(alpha: 0.80),
    );
  }

  /// A single streak early in each 12s cycle, so the sky is never static
  /// but never busy.
  void _meteor(Canvas canvas, Size size) {
    const flight = 0.055; // fraction of each 12s cycle the streak is visible
    final phase = (t * 2) % 1.0;
    if (phase >= flight) return;
    final k = phase / flight;
    // Ease-out travel from the upper right toward the lower left.
    final start = Offset(size.width * 0.78, size.height * 0.04);
    final travel = Offset(-size.width * 0.34, size.height * 0.30);
    final pos = start + travel * (1 - math.pow(1 - k, 3).toDouble());
    final fade = (1 - k) * (k < 0.12 ? k / 0.12 : 1);

    canvas.drawLine(
      pos,
      pos + const Offset(54, 42),
      Paint()
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = Tokens.planetRimHi.withValues(alpha: 0.55 * fade),
    );
    canvas.drawLine(
      pos,
      pos + const Offset(18, 14),
      Paint()
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.75 * fade),
    );
  }

  @override
  bool shouldRepaint(StarfieldPainter oldDelegate) => oldDelegate.t != t;
}

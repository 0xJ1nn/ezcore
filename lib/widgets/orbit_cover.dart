import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/system_labels.dart';
import '../theme/system_hues.dart';
import '../theme/tokens.dart';

/// Generated cover art: the mark's diagonal cut in the game's system hue
/// (handoff §11, `design/Cover.dc.html`).
///
/// Pure — everything it paints comes from its inputs, so the library, the
/// detail page, search results and snapshots can all share one component
/// without any state access.
///
/// Every size is a share of the cover's own width (`cqw` = 1% of it), so the
/// same widget paints the 270 px shelf cover and the 38 px list thumb. Text
/// scales with it on purpose: the design component is specified in `cqw` and
/// the prototype renders it the same way at thumbnail sizes.
class OrbitCover extends StatelessWidget {
  const OrbitCover({
    super.key,
    required this.title,
    required this.systemId,
    required this.sysShort,
    this.sysName,
    this.year,
    this.favorite = false,
    this.isNew = false,
    this.badgeText,
    this.badgeColor,
    this.radius = Tokens.radiusCover,
  });

  /// The game's title, bottom left, Space Grotesk 700 13cqw.
  final String title;

  /// System id — picks the hue from [SystemHues] and the default name.
  final String systemId;

  /// Compact system code for the top row ('NDS', 'PS1', …).
  final String sysShort;

  /// Full system name for the bottom line; defaults to the design's cover
  /// name for [systemId].
  final String? sysName;

  /// Release year, top right. Nullable — nothing renders when absent.
  final int? year;

  /// A ♥ badge bottom-right.
  final bool favorite;

  /// A 'New' badge bottom-right.
  final bool isNew;

  /// A state-driven badge ('Needs core', 'Needs BIOS'). When set it replaces
  /// the favourite/New ones — the screen owns the decision, this widget only
  /// paints.
  final String? badgeText;
  final Color? badgeColor;

  final double radius;

  // ---- §11 palette (Cover.dc.html) ----
  static const _baseTop = Color(0xFF152235);
  static const _baseBottom = Color(0xFF0A111C);
  static const _ring = Color(0x24DDE6F4); // rgba(221,230,244,.14)
  static const _lightLineHi = Color(0xFF7DB9FF);
  static const _lightLineEdge = Color(0x33007BFF); // rgba(0,123,255,.2)
  static const _glowPeak = Color(0x73007BFF); // rgba(0,123,255,.45)
  static const _topRow = Color(0xEAFFFFFF); // rgba(255,255,255,.92)
  static const _topRowDim = Color(0xB3FFFFFF); // .7
  static const _badgeFavBg = Color(0xB3060B14); // rgba(6,11,20,.7)

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        if (w <= 0) return const SizedBox.shrink();
        final q = w / 100; // 1 cqw
        final badge = _badge(q);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              begin: Alignment(-0.342, -0.940),
              end: Alignment(0.342, 0.940),
              colors: [_baseTop, _baseBottom],
              stops: [0, 0.7],
            ),
            border: Border.all(color: _ring, width: 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The system hue, clipped to the mark's diagonal cut, with
                // hairline stripes over it.
                ClipPath(
                  clipper: const _PolygonClipper([
                    Offset(0, 0),
                    Offset(1, 0),
                    Offset(1, 0.34),
                    Offset(0, 0.60),
                  ]),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: SystemHues.blockFor(systemId),
                        ),
                      ),
                      CustomPaint(painter: _StripesPainter(period: 0.07 * w)),
                    ],
                  ),
                ),
                // The cut's glow band, blurred, under the light line.
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: ClipPath(
                      clipper: const _PolygonClipper([
                        Offset(0, 0.57),
                        Offset(1, 0.31),
                        Offset(1, 0.37),
                        Offset(0, 0.63),
                      ]),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              _glowPeak,
                              Colors.transparent,
                            ],
                            stops: const [0, 0.5, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // The blue light line along the cut.
                Positioned.fill(
                  child: ClipPath(
                    clipper: const _PolygonClipper([
                      Offset(0, 0.594),
                      Offset(1, 0.334),
                      Offset(1, 0.346),
                      Offset(0, 0.606),
                    ]),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _lightLineEdge,
                            _lightLineHi,
                            _lightLineEdge,
                          ],
                          stops: const [0, 0.5, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                // Top row: system short name and year.
                Positioned(
                  left: 7 * q,
                  top: 7 * q,
                  right: 7 * q,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(sysShort, style: _topRowStyle(q)),
                      if (year != null)
                        Text(
                          year.toString(),
                          style: _topRowStyle(q).copyWith(color: _topRowDim),
                        ),
                    ],
                  ),
                ),
                // Bottom: title, then the system name.
                Positioned(
                  left: 7 * q,
                  right: 7 * q,
                  bottom: 8 * q,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: Tokens.displayFamily,
                          fontSize: 13 * q,
                          height: 0.94,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.03 * 13 * q,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 3 * q),
                      Text(
                        (sysName ?? systemCoverName(systemId)).toUpperCase(),
                        style: TextStyle(
                          fontFamily: Tokens.bodyFamily,
                          fontSize: 5 * q,
                          height: 1,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.06 * 5 * q,
                          color: Tokens.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge != null)
                  Positioned(right: 3.7 * q, bottom: 3.7 * q, child: badge),
              ],
            ),
          ),
        );
      },
    );
  }

  TextStyle _topRowStyle(double q) => TextStyle(
    fontFamily: Tokens.displayFamily,
    fontSize: 5.6 * q,
    height: 1,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.12 * 5.6 * q,
    color: _topRow,
  );

  /// The bottom-right pill: 'New' in blue, a ♥ in dark glass, or the screen's
  /// own badge (e.g. 'Needs BIOS') in warn amber. Null when there is none.
  Widget? _badge(double q) {
    final String? text;
    final Color bg;
    final IconData? icon;
    if (badgeText != null) {
      text = badgeText;
      bg = badgeColor ?? Tokens.warn;
      icon = null;
    } else if (isNew) {
      text = 'New';
      bg = Tokens.accent;
      icon = null;
    } else if (favorite) {
      text = null;
      bg = _badgeFavBg;
      icon = Icons.favorite;
    } else {
      return null;
    }
    return Container(
      height: 8.9 * q,
      padding: EdgeInsets.symmetric(horizontal: 3.3 * q),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: icon != null
          ? Icon(icon, size: 5 * q, color: Colors.white)
          : Text(
              text!,
              style: TextStyle(
                fontFamily: Tokens.bodyFamily,
                fontSize: 4.1 * q,
                height: 1,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
    );
  }
}

/// Clips to a polygon given in fractions of the size.
class _PolygonClipper extends CustomClipper<Path> {
  const _PolygonClipper(this.fractions);

  final List<Offset> fractions;

  @override
  Path getClip(Size size) {
    final path = Path();
    for (final f in fractions) {
      path.lineTo(f.dx * size.width, f.dy * size.height);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_PolygonClipper oldClipper) => false;
}

/// Hairline white stripes at −58°, 1 px at 7% every 7cqw, over the hue block.
const _stripeColor = Color(0x12FFFFFF); // rgba(255,255,255,.07)

class _StripesPainter extends CustomPainter {
  _StripesPainter({required this.period});

  final double period;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _stripeColor
      ..strokeWidth = 1;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-58 * math.pi / 180);
    final extX = (size.width * 0.530 + size.height * 0.848) / 2 + period;
    final extY = (size.width * 0.848 + size.height * 0.530) / 2 + period;
    for (var y = -extY; y <= extY; y += period) {
      canvas.drawLine(Offset(-extX, y), Offset(extX, y), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripesPainter oldDelegate) =>
      oldDelegate.period != period;
}

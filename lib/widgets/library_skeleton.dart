import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The library while the collection is being read (handoff §8.1): five
/// shimmering cover placeholders, the reading note and a dock outline. The
/// shimmer is a moving gradient on plain containers — no shader art, no
/// network, no invented covers.
class LibrarySkeleton extends StatefulWidget {
  const LibrarySkeleton({super.key});

  @override
  State<LibrarySkeleton> createState() => _LibrarySkeletonState();
}

class _LibrarySkeletonState extends State<LibrarySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  static const _widths = <double>[132, 158, 182, 158, 132];
  static const _heights = <double>[176, 210, 242, 210, 176];

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final slide = reduce
        ? 0.5
        : CurvedAnimation(parent: _shimmer, curve: Curves.linear).value;
    return Column(
      key: const Key('library-skeleton'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < _widths.length; i++) ...[
                  if (i > 0) const SizedBox(width: 18),
                  _ShimmerBox(
                    width: _widths[i],
                    height: _heights[i],
                    slide: slide,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 34),
        const Text(
          'Reading your collection…',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: Tokens.bodyFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Tokens.muted,
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Container(
            height: 132,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            decoration: BoxDecoration(
              color: Tokens.panel.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(Tokens.radiusDock),
              border: Border.all(color: Tokens.lineStrong),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _bar(120, 14, 7),
                _bar(320, 26, 8),
                _bar(220, 12, 6),
              ],
            ),
          ),
        ),
        const SizedBox(height: 82),
      ],
    );
  }

  Widget _bar(double width, double height, double radius) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Tokens.text.withValues(alpha: height > 20 ? 0.1 : 0.07),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.slide,
  });

  final double width;
  final double height;
  final double slide;

  @override
  Widget build(BuildContext context) {
    // A wide gradient swept across the box: the design's ez-shimmer.
    final sweep = -1.0 + slide * 2;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Tokens.text.withValues(alpha: 0.08)),
        gradient: LinearGradient(
          begin: Alignment(sweep, -0.4),
          end: Alignment(sweep + 1.2, 0.4),
          colors: [
            Tokens.text.withValues(alpha: 0.035),
            Tokens.text.withValues(alpha: 0.11),
            Tokens.text.withValues(alpha: 0.035),
          ],
        ),
      ),
    );
  }
}

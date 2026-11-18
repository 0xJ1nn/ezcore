import 'package:flutter/material.dart';

/// The ezCORE mark: two halves of a gamepad and the blue light along the cut.
///
/// The artwork is the exported brand SVG, rendered into density-bucketed
/// images by scripts/render_icons.sh. The app only displays those files.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.height = 24,
    this.color = Colors.white,
    this.light = true,
  });

  final double height;

  /// Kept for source compatibility; the exported artwork fixes the colour.
  final Color color;

  /// Kept for source compatibility; the exported artwork includes the light.
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/inapp/mark.png',
      height: height,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'ezCORE',
    );
  }
}

/// "ez CORE" in the brand's lettering.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.height = 16, this.color = Colors.white});

  /// Height of the capitals.
  final double height;

  /// Kept for source compatibility; the exported artwork fixes the colour.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/inapp/wordmark.png',
      height: height,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'ezCORE',
    );
  }
}

/// Mark and wordmark side by side, in the brand sheet's proportions.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.height = 28, this.color = Colors.white});

  /// Height of the mark.
  final double height;

  /// Kept for source compatibility; the exported artwork fixes the colour.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/inapp/lockup.png',
      height: height,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'ezCORE',
    );
  }
}

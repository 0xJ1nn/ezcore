import 'package:flutter/material.dart';

import '../support/diamond_tokens.dart';

/// The Diamond badge from `design/diamond/badge.html`. The gem is the rendered
/// asset from `diamond-gem.svg`; nothing is drawn in code.
class DiamondBadge extends StatelessWidget {
  const DiamondBadge({
    super.key,
    this.label = 'Diamond',
    this.large = false,
    this.subtitle,
  });

  final String label;
  final bool large;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final h = large
        ? DiamondTokens.badgeHeightLarge
        : DiamondTokens.badgeHeight;
    final gap = large ? DiamondTokens.badgeGapLarge : DiamondTokens.badgeGap;
    final gem = large ? DiamondTokens.gem20 : DiamondTokens.gem16;
    final fontSize = large ? 13.0 : 11.0;
    return Container(
      height: h,
      padding: EdgeInsets.only(
        left: large ? 8 : 6,
        right: large ? 14 : 10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DiamondTokens.badgeHeight),
        gradient: DiamondTokens.background,
        border: Border.all(color: DiamondTokens.bd),
        boxShadow: DiamondTokens.glow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(gem, width: large ? 20 : 16, height: large ? 20 : 16),
          SizedBox(width: gap),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.12 * fontSize,
              color: DiamondTokens.fg,
              height: 1,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: DiamondTokens.badgeGap),
            Container(width: 3, height: 3, decoration: const BoxDecoration(color: DiamondTokens.muted, shape: BoxShape.circle)),
            const SizedBox(width: DiamondTokens.badgeGap),
            Text(
              subtitle!,
              style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: DiamondTokens.muted,
                height: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Icon-only 24 px circle for tight rows, from badge.html.
class DiamondChip extends StatelessWidget {
  const DiamondChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: DiamondTokens.background,
        border: Border.all(color: DiamondTokens.bd),
        boxShadow: DiamondTokens.glow,
      ),
      child: Image.asset(DiamondTokens.gem16, width: 14, height: 14),
    );
  }
}

import 'package:flutter/material.dart';

/// Diamond tokens, ported verbatim from `design/diamond` (support.html and
/// badge.html). Kept separate from the Orbit [Tokens] so the paid tier's
/// palette stays traceable to the design source.
abstract final class DiamondTokens {
  // Palette.
  static const fg = Color(0xFFCFE4FF); // --diamond-fg
  static const bd = Color(0x73A8CEFF); // --diamond-bd rgba(168,206,255,.45)
  static const blue2 = Color(0xFF4DA3FF); // --blue2
  static const dangerText = Color(0xFFFF8A80); // --danger
  static const ok = Color(0xFF7BE0A6); // --ok
  static const muted = Color(0xFF9AA8BC); // --muted
  static const faint = Color(0xFF687384); // --faint
  static const text = Color(0xFFDDE6F4); // --text

  /// --diamond-bg: 135deg rgba(77,163,255,.18) → rgba(0,101,237,.10)
  static const background = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x2E4DA3FF), Color(0x1A0065ED)],
  );

  /// --diamond-glow: 0 0 12px rgba(77,163,255,.35)
  static const glow = [
    BoxShadow(color: Color(0x594DA3FF), blurRadius: 12),
  ];

  /// The primary Diamond button: 135deg #3D8BFF → #0A5CE0.
  static const buttonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3D8BFF), Color(0xFF0A5CE0)],
  );

  /// Sheet surface #0D1522, card rgba(15,24,37,.72), hairline .09.
  static const sheet = Color(0xFF0D1522);
  static const card = Color(0xB80F1825);
  static const line = Color(0x17FFFFFF);

  /// Badge geometry (badge.html).
  static const double badgeHeight = 24;
  static const double badgeHeightLarge = 32;
  static const double badgeGap = 6;
  static const double badgeGapLarge = 8;
  static const double badgeGem = 16;
  static const double badgeGemLarge = 20;

  /// Gem sizes rendered from `diamond-gem.svg` into assets/diamond.
  static const String gem16 = 'assets/diamond/gem-16.png';
  static const String gem20 = 'assets/diamond/gem-20.png';
  static const String gem44 = 'assets/diamond/gem-44.png';
  static const String gem64 = 'assets/diamond/gem-64.png';

  static const String sponsorsUrl = 'https://github.com/sponsors/0xJ1nn';
  static const String termsUrl =
      'https://github.com/0xJ1nn/ezcore/blob/main/docs/TERMS.md';
  static const String privacyUrl =
      'https://github.com/0xJ1nn/ezcore/blob/main/docs/PRIVACY.md';
  static const String iosSubscriptionsUrl =
      'https://apps.apple.com/account/subscriptions';
  static const String androidSubscriptionsUrl =
      'https://play.google.com/store/account/subscriptions';
}

import 'package:flutter/material.dart';

import 'tokens.dart';

/// The four layout families the studio plate is drawn for.
///
/// Every screen asks for one of these instead of re-deriving
/// `portrait` / `wideRail` / `short` on its own. That duplication is how
/// screens drift apart — each one grows its own idea of "phone".
enum OrbitLayout {
  /// Wide desktop window: command rail + cover flow + full game dock.
  desktop,

  /// Tablet: command rail + hub rows ("Continue playing", "Recently added").
  tablet,

  /// Phone held sideways: compact command rail + short cover flow + dock.
  phoneLandscape,

  /// Phone held upright: top bar, featured game, bottom command bar.
  phonePortrait,
}

/// Responsive rules shared by the shell and every screen.
abstract final class Layout {
  /// The layout family for the current viewport.
  static OrbitLayout of(BuildContext context) {
    final m = MediaQuery.of(context);
    return ofSize(m.size, m.orientation);
  }

  /// Pure size/orientation form — the shape widget tests can call directly.
  ///
  /// Landscape splits three ways: a *short* window (a phone held sideways,
  /// or a small desktop window) gets the compressed rhythm regardless of
  /// how wide it is, because height is what runs out first.
  static OrbitLayout ofSize(Size size, Orientation orientation) {
    if (orientation == Orientation.portrait) return OrbitLayout.phonePortrait;
    if (size.height < Tokens.bpShortHeight || size.width < Tokens.bpCompact) {
      return OrbitLayout.phoneLandscape;
    }
    if (size.width >= Tokens.bpDesktop) return OrbitLayout.desktop;
    return OrbitLayout.tablet;
  }

  /// True when the command rail belongs on the left edge.
  static bool hasRail(OrbitLayout l) => l != OrbitLayout.phonePortrait;

  /// True for the two phone shapes.
  static bool isPhone(OrbitLayout l) =>
      l == OrbitLayout.phonePortrait || l == OrbitLayout.phoneLandscape;

  /// True when the phone-style bottom command bar replaces the top one.
  static bool hasBottomBar(OrbitLayout l) => l == OrbitLayout.phonePortrait;

  /// Short viewports (phone/tablet held sideways, small windows) need the
  /// compressed rhythm: tighter bars, smaller titles, no footer.
  static bool isShort(OrbitLayout l) =>
      l == OrbitLayout.phoneLandscape || l == OrbitLayout.tablet;

  /// Human label used in test names and debug overlays.
  static String label(OrbitLayout l) => switch (l) {
    OrbitLayout.desktop => 'desktop',
    OrbitLayout.tablet => 'tablet',
    OrbitLayout.phoneLandscape => 'phone landscape',
    OrbitLayout.phonePortrait => 'phone portrait',
  };
}

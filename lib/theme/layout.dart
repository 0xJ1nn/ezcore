// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'package:flutter/material.dart';

import '../state/input_mode.dart';
import 'tokens.dart';

/// The five layout families the studio plate is drawn for.
///
/// Every screen asks for one of these instead of re-deriving
/// `portrait` / `wideRail` / `short` on its own. That duplication is how
/// screens drift apart — each one grows its own idea of "phone".
enum OrbitLayout {
  /// Wide desktop window: command rail + cover flow + full game dock.
  desktop,

  /// Tablet: command rail + hub rows ("Continue playing", "Recently added").
  tablet,

  /// Tablet held upright: keep the rail and hub instead of using phone chrome.
  tabletPortrait,

  /// Phone held sideways: compact command rail + short cover flow + dock.
  phoneLandscape,

  /// Phone held upright: top bar, featured game, bottom command bar.
  phonePortrait,
}

/// Records the modifier resolved for the *outer* window. An input-aware
/// viewport scales its child for TV, which changes the MediaQuery size; a
/// screen below it must keep reading the modifier from here rather than
/// re-resolving it from the virtual size (which would look like a plain
/// desktop and undo every modifier).
class InputAwareViewportMarker extends InheritedWidget {
  const InputAwareViewportMarker({
    super.key,
    required this.modifier,
    required super.child,
  });

  final LayoutModifier modifier;

  @override
  bool updateShouldNotify(InputAwareViewportMarker old) =>
      old.modifier != modifier;
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
    if (orientation == Orientation.portrait) {
      return size.width >= Tokens.bpCompact
          ? OrbitLayout.tabletPortrait
          : OrbitLayout.phonePortrait;
    }
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

  /// True for layouts held upright, including tablets that keep a rail.
  static bool isPortrait(OrbitLayout l) =>
      l == OrbitLayout.phonePortrait || l == OrbitLayout.tabletPortrait;

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
    OrbitLayout.tabletPortrait => 'tablet portrait',
    OrbitLayout.phoneLandscape => 'phone landscape',
    OrbitLayout.phonePortrait => 'phone portrait',
  };

  // ---- Input-aware modifiers (§10) ----
  //
  // These add no enum values: the five families stay the contract every
  // screen already uses. A modifier is a measurement layered on that family.

  static LayoutModifier modifierOfSize(Size size, Orientation orientation) =>
      InputMode.shared.resolve(size, orientation);

  static LayoutModifier modifierOf(BuildContext context) {
    final marked = context
        .dependOnInheritedWidgetOfExactType<InputAwareViewportMarker>();
    if (marked != null) return marked.modifier;
    final m = MediaQuery.of(context);
    return modifierOfSize(m.size, m.orientation);
  }

  static bool isTv(LayoutModifier m) => m == LayoutModifier.tv;

  static bool isHandheld(LayoutModifier m) => m == LayoutModifier.handheld;

  static bool isUltrawide(LayoutModifier m) => m == LayoutModifier.ultrawide;

  /// Rail width in logical pixels. TV keeps the full rail but widens it for
  /// sofa-sized targets; handheld and sideways phones use the compact rail.
  static double railWidth(OrbitLayout l, LayoutModifier m) => switch (m) {
    LayoutModifier.tv => 136.0,
    LayoutModifier.handheld => Tokens.railShort,
    _ => l == OrbitLayout.phoneLandscape ? Tokens.railShort : Tokens.rail,
  };

  /// Uniform type multiplier. TV is the only family that grows type.
  static double typeScale(LayoutModifier m) =>
      m == LayoutModifier.tv ? 1.33 : 1.0;

  /// Title-safe inset. Only the 10-foot layout needs one.
  static double safeArea(LayoutModifier m) =>
      m == LayoutModifier.tv ? Tokens.s8 : 0.0;

  /// Content cap on a very wide window; the dock centres inside this.
  static double contentMaxWidth(LayoutModifier m) =>
      m == LayoutModifier.ultrawide ? 1600.0 : double.infinity;

  /// Focused cover width. TV and ultrawide share the sofa-sized cover;
  /// everywhere else the desktop shelf keeps its 270 px cover.
  static double coverExtent(LayoutModifier m, OrbitLayout l) => switch (m) {
    LayoutModifier.tv || LayoutModifier.ultrawide => 360.0,
    _ => l == OrbitLayout.desktop ? 270.0 : 0.0,
  };

  /// How many covers sit on each side of the focused one.
  static int coverNeighbours(LayoutModifier m) => switch (m) {
    LayoutModifier.ultrawide => 7,
    LayoutModifier.tv => 3,
    LayoutModifier.handheld => 3,
    LayoutModifier.none => 6,
  };

  /// No text renders below this size in the modified layout.
  static double textFloor(LayoutModifier m) => switch (m) {
    LayoutModifier.tv => 18.0,
    LayoutModifier.handheld => 16.0,
    _ => 12.0,
  };

  /// Hover is a mouse affordance. It is off on the two pad-first families.
  static bool showHover(LayoutModifier m) =>
      m != LayoutModifier.tv && m != LayoutModifier.handheld;

  /// Pad-first layouts keep the glyph hints on screen.
  static bool showHintRow(LayoutModifier m) =>
      m == LayoutModifier.tv || m == LayoutModifier.handheld;
}

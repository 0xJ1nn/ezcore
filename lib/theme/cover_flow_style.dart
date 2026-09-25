import 'package:flutter/material.dart';

/// User-selectable tuning for the library's cover carousel.
///
/// Keep the motion values together so the Library screen and future shelves
/// can share the same feel without copying animation constants into widgets.
enum CoverFlowStyle {
  /// Pronounced album-cover perspective with a relaxed snap.
  classic,

  /// A quieter tilt and shorter settle for people who prefer less motion.
  gentle,

  /// No 3D rotation; nearby covers stay almost the same size and brightness.
  flat;

  static CoverFlowStyle fromSetting(Object? value) => switch (value) {
    'gentle' => CoverFlowStyle.gentle,
    'flat' => CoverFlowStyle.flat,
    _ => CoverFlowStyle.classic,
  };

  String get label => switch (this) {
    CoverFlowStyle.classic => 'Classic',
    CoverFlowStyle.gentle => 'Gentle',
    CoverFlowStyle.flat => 'Flat',
  };

  double get rotationDegrees => switch (this) {
    CoverFlowStyle.classic => 19,
    CoverFlowStyle.gentle => 9,
    CoverFlowStyle.flat => 0,
  };

  double get neighborScale => switch (this) {
    CoverFlowStyle.classic => 0.84,
    CoverFlowStyle.gentle => 0.93,
    CoverFlowStyle.flat => 0.97,
  };

  double get neighborOpacity => switch (this) {
    CoverFlowStyle.classic => 0.82,
    CoverFlowStyle.gentle => 0.90,
    CoverFlowStyle.flat => 0.96,
  };

  double get minScale => switch (this) {
    CoverFlowStyle.classic => 0.60,
    CoverFlowStyle.gentle => 0.78,
    CoverFlowStyle.flat => 0.90,
  };

  double get minOpacity => switch (this) {
    CoverFlowStyle.classic => 0.28,
    CoverFlowStyle.gentle => 0.48,
    CoverFlowStyle.flat => 0.68,
  };

  double get perspective => switch (this) {
    CoverFlowStyle.classic => 0.0012,
    CoverFlowStyle.gentle => 0.0007,
    CoverFlowStyle.flat => 0,
  };

  Duration get settleDuration => switch (this) {
    CoverFlowStyle.classic => const Duration(milliseconds: 460),
    CoverFlowStyle.gentle => const Duration(milliseconds: 340),
    CoverFlowStyle.flat => const Duration(milliseconds: 240),
  };

  Curve get settleCurve => switch (this) {
    CoverFlowStyle.classic => Curves.easeOutCubic,
    CoverFlowStyle.gentle => Curves.easeOutCubic,
    CoverFlowStyle.flat => Curves.easeOut,
  };
}

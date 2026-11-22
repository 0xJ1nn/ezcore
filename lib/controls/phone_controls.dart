// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:math' as math;
import 'dart:ui';

import 'control_layout.dart';

/// The device boards in the design place controls at their own pixel
/// coordinates. A built-in layout is a fraction-based generic pad; on a
/// phone it is remapped onto those boards. A layout the player saved is used
/// exactly as saved — it has already been mapped once, here.
/// Touch controls move into the band below the full-bleed phone picture.
ControlLayout phoneControls(ControlLayout base, {required bool portrait}) {
  const faceIds = {
    'x',
    'y',
    'a',
    'b',
    'triangle',
    'square',
    'circle',
    'cross',
    'ga',
    'gb',
    'gc',
    'i',
    'ii',
    'fire',
  };
  final faces = base.controls.where((c) => faceIds.contains(c.id)).toList();
  var faceMinX = 0.0, faceMaxX = 1.0, faceMinY = 0.0, faceMaxY = 1.0;
  if (faces.isNotEmpty) {
    final centers = [
      for (final c in faces)
        Offset(c.rect.x + c.rect.w / 2, c.rect.y + c.rect.h / 2),
    ];
    faceMinX = centers.map((c) => c.dx).reduce(math.min);
    faceMaxX = centers.map((c) => c.dx).reduce(math.max);
    faceMinY = centers.map((c) => c.dy).reduce(math.min);
    faceMaxY = centers.map((c) => c.dy).reduce(math.max);
  }
  final target = portrait
      ? const Rect.fromLTRB(0.664, 0.8495, 0.882, 0.9491)
      : const Rect.fromLTRB(0.827, 0.431, 0.923, 0.554);
  double span(double lo, double hi, double at) =>
      hi == lo ? 0.5 : (at - lo) / (hi - lo);

  NormRect place(ControlSpec c) {
    final r = c.rect;
    final cx =
        target.left + span(faceMinX, faceMaxX, r.x + r.w / 2) * target.width;
    final cy =
        target.top + span(faceMinY, faceMaxY, r.y + r.h / 2) * target.height;
    final a = c.id == 'a' || c.id == 'circle';
    final size = portrait ? (a ? 0.1128 : 0.1077) : 0.0545;
    final h = portrait ? (a ? 0.0521 : 0.0498) : 0.1179;
    return NormRect(cx - size / 2, cy - h / 2, size, h);
  }

  // The landscape device board is drawn on an 844x390 surface; writing its
  // geometry in pixels keeps the review's measured numbers legible.
  NormRect px(double x, double y, double w, double h) =>
      NormRect(x / 844, y / 390, w / 844, h / 390);

  /// The bottom row's pills are drawn by [_LandscapeActionBar] so the Menu
  /// chip can carry a pause glyph; their data rectangles still own the hit
  /// areas and leave the label blank to avoid a second visual.
  ControlSpec quiet(ControlSpec c, NormRect rect) => ControlSpec(
    id: c.id,
    type: c.type,
    input: c.input,
    label: '',
    shape: c.shape,
    rect: rect,
  );

  final controls = <ControlSpec>[];
  for (final c in base.controls) {
    if (c.id == 'menu') {
      if (!portrait) {
        controls.add(quiet(c, px(384, 348, 78, 32)));
      }
      continue;
    }
    switch (c.id) {
      case 'l':
        controls.add(
          c.copyWith(
            rect: portrait
                ? const NormRect(0.0385, 0.7761, 0.241, 0.0450)
                : px(24, 24, 117, 36),
          ),
        );
      case 'r':
        controls.add(
          c.copyWith(
            rect: portrait
                ? const NormRect(0.7205, 0.7761, 0.241, 0.0450)
                : px(703, 24, 117, 36),
          ),
        );
      case 'l2':
        controls.add(
          c.copyWith(
            rect: portrait
                ? const NormRect(0.0385, 0.735, 0.241, 0.0403)
                : const NormRect(0.0237, 0.155, 0.1386, 0.0923),
          ),
        );
      case 'r2':
        controls.add(
          c.copyWith(
            rect: portrait
                ? const NormRect(0.7205, 0.735, 0.241, 0.0403)
                : const NormRect(0.8365, 0.155, 0.1386, 0.0923),
          ),
        );
      case 'z':
        controls.add(
          c.copyWith(
            rect: portrait
                ? const NormRect(0.0385, 0.735, 0.241, 0.0403)
                : const NormRect(0.0237, 0.155, 0.1386, 0.0923),
          ),
        );
      case 'dpad':
        controls.add(
          c.copyWith(
            rect: portrait
                ? const NormRect(0.073, 0.830, 0.303, 0.140)
                : px(25.5, 156.2, 140, 140),
          ),
        );
      case 'select':
        controls.add(
          portrait
              ? c.copyWith(rect: const NormRect(0.331, 0.942, 0.164, 0.0332))
              : quiet(c, px(318, 348, 58, 32)),
        );
      case 'start':
        controls.add(
          portrait
              ? c.copyWith(rect: const NormRect(0.526, 0.942, 0.144, 0.0332))
              : quiet(c, px(470, 348, 57, 32)),
        );
      case 'a':
        controls.add(
          portrait
              ? c.copyWith(rect: place(c))
              : c.copyWith(rect: px(748, 176, 64, 64)),
        );
      case 'b':
        controls.add(
          portrait
              ? c.copyWith(rect: place(c))
              : c.copyWith(rect: px(662, 214, 64, 64)),
        );
      default:
        if (faceIds.contains(c.id)) {
          controls.add(c.copyWith(rect: place(c)));
        } else {
          controls.add(c);
        }
    }
  }
  return ControlLayout(
    id: base.id,
    name: base.name,
    systems: base.systems,
    orientation: base.orientation,
    screen: base.screen,
    controls: controls,
    shell: base.shell,
    opacity: base.opacity,
  );
}

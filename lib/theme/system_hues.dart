import 'package:flutter/material.dart';

/// Per-system hues for generated cover art (handoff §3.1).
///
/// The design gives every system one hue, used by the cover's mark-cut
/// colour block — `oklch(0.47 0.095 H)` — and by the ambient room tint,
/// `oklch(0.42 0.11 H)`. Both are converted to sRGB constants here so the
/// app ships values, not a colour engine.
///
/// Design table (hue in degrees):
/// NES 25 · SNES 300 · N64 150 · GB 115 · GBC 345 · GBA 270 · NDS 215 ·
/// PS1 245 · DC 55 · PSP 190
///
/// Keys are the app's system ids (`psx` is PlayStation). Systems the design
/// table does not cover get the neutral slate fallback.
abstract final class SystemHues {
  SystemHues._();

  /// The cover's colour block, clipped to the mark's cut.
  static const Map<String, Color> block = {
    'nes': Color(0xFF88433F), // H 25
    'snes': Color(0xFF634D88), // H 300
    'n64': Color(0xFF2D693D), // H 150
    'gb': Color(0xFF596117), // H 115
    'gbc': Color(0xFF804367), // H 345
    'gba': Color(0xFF465790), // H 270
    'nds': Color(0xFF00677C), // H 215
    'psx': Color(0xFF245F8C), // H 245
    'dc': Color(0xFF834B20), // H 55
    'psp': Color(0xFF006B67), // H 190
  };

  /// The room tint behind the game (detail page, shelf ambient).
  static const Map<String, Color> roomTint = {
    'nes': Color(0xFF7E302D),
    'snes': Color(0xFF573C7F),
    'n64': Color(0xFF0B5D2A),
    'gb': Color(0xFF4C5300),
    'gbc': Color(0xFF75305B),
    'gba': Color(0xFF364789),
    'nds': Color(0xFF005A72),
    'psx': Color(0xFF005184),
    'dc': Color(0xFF793900),
    'psp': Color(0xFF005F5A),
  };

  /// Neutral slate for systems without a design hue — oklch(0.47 0.03 250).
  static const Color fallbackBlock = Color(0xFF4E5C6B);

  /// Neutral slate tint — oklch(0.42 0.035 250).
  static const Color fallbackTint = Color(0xFF3F4F60);

  /// The colour block for [systemId]'s covers.
  static Color blockFor(String systemId) => block[systemId] ?? fallbackBlock;

  /// The room tint for [systemId]'s detail page and ambient light.
  static Color roomTintFor(String systemId) =>
      roomTint[systemId] ?? fallbackTint;
}

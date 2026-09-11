import 'package:flutter/material.dart';

/// Cabinet-dark design tokens. Working theme — full identity pass later.
abstract final class Tokens {
  static const ink = Color(0xFF14120E);
  static const inkRaised = Color(0xFF1E1B15);
  static const inkLine = Color(0xFF2E2A21);
  static const paper = Color(0xFFF5F1E6);
  static const muted = Color(0xFFA8A094);
  static const coin = Color(0xFFE8B84B);
  static const pulse = Color(0xFFC9FF3D);
  static const danger = Color(0xFFFF6B5E);
  static const ok = Color(0xFF7DE89A);

  static const radiusSm = 8.0;
  static const radiusMd = 14.0;
  static const radiusLg = 22.0;
  static const pad = 16.0;

  static ThemeData theme() {
    final scheme = ColorScheme.dark(
      primary: coin,
      secondary: pulse,
      surface: ink,
      surfaceContainerHighest: inkRaised,
      outline: inkLine,
      onSurface: paper,
      onSurfaceVariant: muted,
      error: danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: ink,
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: ink,
        foregroundColor: paper,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: inkRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: inkLine),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: inkRaised,
        selectedColor: coin.withValues(alpha: 0.2),
        labelStyle: const TextStyle(color: paper, fontSize: 12),
        side: const BorderSide(color: inkLine),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(99),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inkRaised,
        hintStyle: const TextStyle(color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: inkLine),
        ),
      ),
    );
  }
}

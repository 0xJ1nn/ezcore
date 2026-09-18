import 'package:flutter/material.dart';

/// ezCORE final-01 (Orbit console) design tokens.
///
/// Source of truth: `ezcore-design/studio/orbit-console/orbit-app.source.html`
/// + `systems.css` — data-brand-build="ezcore-final-01".
/// Approved identity: black / electric blue / silver-white. Dark only.
///
/// Display: Space Grotesk · Body: Manrope (bundled in assets/fonts,
/// OFL-licensed — fully offline, no runtime font fetching).
abstract final class Tokens {
  // ---- Core (final) ----
  static const bg = Color(0xFF0A0A0A);
  static const text = Color(0xFFDDE6F4);
  static const muted = Color(0xFF9AA8BC);
  static const line = Color(0x16FFFFFF); // rgba(255,255,255,0.086)
  static const lineStrong = Color(0x2BDDE6F4); // #DDE6F42B dock hairline
  static const accent = Color(0xFF007BFF);
  static const accentHi = Color(0xFF0086FF);
  static const accentDeep = Color(0xFF0065ED);
  static const panel = Color(0xFF12151B);
  static const dockTop = Color(0xFF1B2029);
  static const dockBottom = Color(0xFF101216);
  static const systemLabelFg = Color(0xFFA8CEFF);
  static const systemLabelBg = Color(0x19007BFF); // #007BFF19
  static const systemLabelBd = Color(0x38007BFF); // #007BFF38
  static const separator = Color(0xFF687384);
  static const dockBody = Color(0xFF9AA8BC);
  static const scrim = Color(0xC902070D);
  static const searchIdle = Color(0x770A0A0A);
  static const chipActiveBg = Color(0x13DDE6F4); // #DDE6F413
  static const toggleOff = Color(0xFF38434C);
  static const toggleKnobOff = Color(0xFFBDC7CE);

  static const danger = Color(0xFFFF6B5E);
  static const ok = Color(0xFF7DE89A);

  // ---- Geometry ----
  static const radiusSm = 8.0;
  static const radiusMd = 14.0;
  static const radiusLg = 22.0;
  static const radiusCover = 5.0;
  static const radiusCase = 6.0;
  static const radiusDock = 18.0;
  static const radiusDialog = 10.0;
  static const radiusCoreCard = 20.0;
  static const radiusPrimary = 12.0;
  static const radiusRound = 12.0;
  static const radiusFlowBtn = 8.0;
  static const radiusBadge = 30.0;
  static const radiusToast = 30.0;
  static const pad = 16.0;

  static const ease = Cubic(0.22, 1, 0.36, 1);
  static const easeDur = Duration(milliseconds: 650);
  static const fastDur = Duration(milliseconds: 200);

  /// Single responsive side-margin: clamp(20, w*0.03, 52).
  /// Portrait phones use 24, short landscape 26 — handled by callers.
  static double osPad(double width, {bool portrait = false, bool short_ = false}) {
    if (portrait) return 24;
    if (short_) return 26;
    final v = width * 0.03;
    if (v < 20) return 20;
    if (v > 52) return 52;
    return v;
  }

  static const double rail = 84;
  static const double railShort = 72;

  // ---- Type (Space Grotesk display / Manrope body, bundled) ----
  static const displayFamily = 'SpaceGrotesk';
  static const bodyFamily = 'Manrope';

  static TextStyle display({
    double size = 30,
    FontWeight weight = FontWeight.w500,
    double ls = -1.0,
    Color color = text,
    double? height,
  }) =>
      TextStyle(
        fontFamily: displayFamily,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: ls,
        color: color,
        height: height,
      );

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    double ls = 0,
    Color color = text,
    double? height,
  }) =>
      TextStyle(
        fontFamily: bodyFamily,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: ls,
        color: color,
        height: height,
      );

  static TextStyle get eyebrow => const TextStyle(
        fontFamily: displayFamily,
        fontSize: 9,
        letterSpacing: 2.0,
        color: muted,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get h1 => display(size: 30, weight: FontWeight.w500, ls: -1.0);

  static TextStyle get dockTitle =>
      display(size: 24, weight: FontWeight.w500, ls: -0.7, height: 1.16);

  static TextStyle get dockBodyStyle =>
      body(size: 11, color: dockBody, height: 1.5);

  static TextStyle get gameMeta =>
      body(size: 10, ls: 0.25, color: text);

  static TextStyle get systemLabel => const TextStyle(
        fontFamily: displayFamily,
        fontSize: 9,
        letterSpacing: 1.0,
        color: systemLabelFg,
        fontWeight: FontWeight.w400,
      );

  static TextStyle get flowCount => const TextStyle(
        fontFamily: displayFamily,
        fontSize: 9,
        letterSpacing: 3.0,
        color: muted,
      );

  static TextStyle get chipLabel =>
      body(size: 11, weight: FontWeight.w600, color: muted);

  static TextStyle get footerStyle => body(size: 9, color: muted);

  // ---- Decorations ----
  static BoxDecoration get dockDecor => BoxDecoration(
        borderRadius: BorderRadius.circular(radiusDock),
        gradient: const LinearGradient(
          begin: Alignment(-1.0, -0.4),
          end: Alignment(1.0, 0.6),
          colors: [dockTop, dockBottom],
          stops: [0.0, 0.65],
        ),
        border: Border.all(color: lineStrong),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0CFFFFFF),
            offset: Offset(0, 1),
            blurRadius: 0,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Color(0x66000000),
            offset: Offset(0, 14),
            blurRadius: 34,
          ),
        ],
      );

  static BoxDecoration get dialogDecor => BoxDecoration(
        borderRadius: BorderRadius.circular(radiusDialog),
        gradient: const LinearGradient(
          begin: Alignment(-0.8, -0.8),
          end: Alignment(0.6, 0.8),
          colors: [dockTop, bg],
          stops: [0.0, 0.65],
        ),
        border: Border.all(color: Color(0x30DDE6F4)),
        boxShadow: const [
          BoxShadow(color: Color(0x88000000), offset: Offset(0, 35), blurRadius: 150),
          BoxShadow(color: Color(0x20DDE6F4), offset: Offset(0, 1), blurRadius: 0),
        ],
      );

  static BoxDecoration get coreCardDecor => BoxDecoration(
        borderRadius: BorderRadius.circular(radiusCoreCard),
        gradient: const LinearGradient(
          begin: Alignment(-0.7, -0.7),
          end: Alignment(0.7, 0.7),
          colors: [Color(0xFF242B35), Color(0xFF10141A)],
          stops: [0.0, 0.65],
        ),
        border: Border.all(color: Color(0x28DDE6F4)),
        boxShadow: const [
          BoxShadow(color: Color(0x12FFFFFF), offset: Offset(0, 1), blurRadius: 0),
          BoxShadow(color: Color(0x99000000), offset: Offset(0, 22), blurRadius: 44),
        ],
      );

  static BoxDecoration get coreCardSelectedDecor => BoxDecoration(
        borderRadius: BorderRadius.circular(radiusCoreCard),
        gradient: const LinearGradient(
          begin: Alignment(-0.7, -0.7),
          end: Alignment(0.7, 0.7),
          colors: [Color(0xFF242B35), Color(0xFF10141A)],
          stops: [0.0, 0.65],
        ),
        border: Border.all(color: Color(0xFF6EB4FF)),
        boxShadow: const [
          BoxShadow(color: Color(0x35FFFFFF), offset: Offset(0, 1), blurRadius: 0),
          BoxShadow(color: Color(0x35007BFF), offset: Offset(0, 0), blurRadius: 0, spreadRadius: 3),
          BoxShadow(color: Color(0x88000000), offset: Offset(0, 24), blurRadius: 50),
        ],
      );

  static ThemeData theme() {
    final scheme = const ColorScheme.dark(
      primary: accent,
      secondary: accent,
      surface: bg,
      surfaceContainerHighest: panel,
      outline: line,
      onSurface: text,
      onSurfaceVariant: muted,
      error: danger,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      splashFactory: NoSplash.splashFactory,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: text,
        displayColor: text,
        fontFamily: bodyFamily,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: line),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panel,
        selectedColor: chipActiveBg,
        labelStyle: body(size: 12),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(99),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: searchIdle,
        hintStyle: body(size: 13, color: muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dockTop,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusDialog),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: accent,
        contentTextStyle: body(size: 12, color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusToast),
          side: const BorderSide(color: Color(0x22FFFFFF)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      focusColor: accent.withValues(alpha: 0.12),
    );
  }
}

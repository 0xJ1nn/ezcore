import 'package:flutter/material.dart';

/// ezCORE (Orbit console) design tokens.
///
/// Approved identity, unchanged by the studio-plate redesign: black /
/// electric blue / silver-white, dark only. The brand plate pins the
/// palette as `#0A0A0A · #007BFF · #DDE6F4 · #FFFFFF`; everything under
/// "Space scene" re-mixes those same values for depth, it does not
/// introduce a new hue.
///
/// Every colour, radius and type style the UI uses is declared here, which
/// is what makes a future theme system a swap of this one file rather than
/// a rewrite of the screens.
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

  // ---- Space scene (studio plate background) ----
  // The approved identity stays black / electric blue / silver-white. The
  // scene only re-mixes those same values across depth instead of a new hue.
  static const spaceDeep = Color(0xFF05080F); // zenith
  static const spaceMid = Color(0xFF091324); // mid field
  static const spaceNebula = Color(0xFF10243F); // nebula wash
  static const planetBody = Color(0xFF071120); // planet surface
  static const planetRim = Color(0xFF3B8BFF); // atmosphere rim
  static const planetRimHi = Color(0xFFBFD8FF); // rim highlight
  static const starDim = Color(0xFF6E8CB5);
  static const starHi = Color(0xFFEAF2FF);
  static const ridgeFar = Color(0xFF0A1422); // far mountain silhouette
  static const ridgeNear = Color(0xFF04070D); // near mountain silhouette

  // ---- Brand taglines (brand plate) ----
  static const taglinePlay = 'PLAY  ·  PRESERVE  ·  ANYWHERE';
  static const taglineLeft = 'GAMES BRING US CLOSER.';
  static const taglineRight = 'BUILT FOR A MORE PLAYFUL TOMORROW.';

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
  static double osPad(
    double width, {
    bool portrait = false,
    bool short_ = false,
  }) {
    if (portrait) return 24;
    if (short_) return 26;
    final v = width * 0.03;
    if (v < 20) return 20;
    if (v > 52) return 52;
    return v;
  }

  static const double rail = 84;
  static const double railShort = 72;

  // ---- Responsive breakpoints (shared by every screen) ----
  // Four layout families mirror the studio plate:
  //   phone portrait  — bottom command bar, featured game, continue row
  //   phone landscape — compact command rail, short cover flow
  //   tablet          — command rail, hub rows
  //   desktop         — command rail, cover flow + game dock
  static const double bpCompact = 700; // below this: phone
  static const double bpDesktop = 1180; // at/above this: desktop
  static const double bpShortHeight = 650; // short landscape phones

  // ---- Geometry for the new chrome ----
  static const double bottomBarHeight = 64;
  static const double dockPanelRadius = 20;
  static const double statPanelRadius = 14;
  static const double pillRadius = 26;
  static const double tileRadius = 12;

  // ---- Type (Space Grotesk display / Manrope body, bundled) ----
  static const displayFamily = 'SpaceGrotesk';
  static const bodyFamily = 'Manrope';

  static TextStyle display({
    double size = 30,
    FontWeight weight = FontWeight.w500,
    double ls = -1.0,
    Color color = text,
    double? height,
  }) => TextStyle(
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
  }) => TextStyle(
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

  static TextStyle get h1 =>
      display(size: 30, weight: FontWeight.w500, ls: -1.0);

  static TextStyle get dockTitle =>
      display(size: 24, weight: FontWeight.w500, ls: -0.7, height: 1.16);

  static TextStyle get dockBodyStyle =>
      body(size: 11, color: dockBody, height: 1.5);

  static TextStyle get gameMeta => body(size: 10, ls: 0.25, color: text);

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

  // ---- Type: scene chrome (screen title, sections, stat panel) ----

  /// Big screen title: "The collection" + inline count.
  static const screenTitle = 30.0;

  /// Standfirst under a screen title: "Play. Preserve. Anywhere."
  static TextStyle get standfirst => body(size: 11, color: muted, height: 1.4);

  /// Section title inside a screen: "Continue playing".
  static TextStyle get sectionTitle =>
      display(size: 15, weight: FontWeight.w600, ls: -0.3);

  /// "See all" affordance on the right of a section title.
  static TextStyle get sectionLink =>
      body(size: 10, color: accent, weight: FontWeight.w600);

  /// Stat label: "Last played", "Save states".
  static TextStyle get statLabel => body(size: 9, color: muted, height: 1.2);

  /// Stat value: "2 days ago", "12 states".
  static TextStyle get statValue => body(size: 12, weight: FontWeight.w600);

  /// Small rounded tag on a game: "1.2 GB", "PSX".
  static TextStyle get tileTag =>
      body(size: 9, color: text, weight: FontWeight.w600, ls: 0.2);

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
      BoxShadow(
        color: Color(0x88000000),
        offset: Offset(0, 35),
        blurRadius: 150,
      ),
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
      BoxShadow(
        color: Color(0x99000000),
        offset: Offset(0, 22),
        blurRadius: 44,
      ),
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
      BoxShadow(
        color: Color(0x35007BFF),
        offset: Offset(0, 0),
        blurRadius: 0,
        spreadRadius: 3,
      ),
      BoxShadow(
        color: Color(0x88000000),
        offset: Offset(0, 24),
        blurRadius: 50,
      ),
    ],
  );

  /// Glass card: the selected-game dock, stat panel, and section tiles.
  static BoxDecoration get panelGlass => BoxDecoration(
    borderRadius: BorderRadius.circular(dockPanelRadius),
    gradient: const LinearGradient(
      begin: Alignment(-0.9, -0.9),
      end: Alignment(0.7, 0.9),
      colors: [Color(0xF21B2430), Color(0xF20B111B)],
      stops: [0.0, 0.7],
    ),
    border: Border.all(color: lineStrong),
    boxShadow: const [
      BoxShadow(color: Color(0x0AFFFFFF), offset: Offset(0, 1), blurRadius: 0),
      BoxShadow(
        color: Color(0x7A000000),
        offset: Offset(0, 18),
        blurRadius: 42,
      ),
    ],
  );

  /// Recessed panel that holds the game's real stats.
  static BoxDecoration get statPanelDecor => BoxDecoration(
    borderRadius: BorderRadius.circular(statPanelRadius),
    color: const Color(0x66060A11),
    border: Border.all(color: const Color(0x1FDDE6F4)),
  );

  /// Sheet surface (system picker, slot lists).
  static BoxDecoration get sheetDecor => BoxDecoration(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF182231), Color(0xFF0A0F18)],
    ),
    border: const Border(top: BorderSide(color: lineStrong)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x99000000),
        offset: Offset(0, -14),
        blurRadius: 46,
      ),
    ],
  );

  /// Bottom command bar (phone portrait).
  static BoxDecoration get bottomBarDecor => BoxDecoration(
    color: const Color(0xF2080D15),
    border: const Border(top: BorderSide(color: lineStrong)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x59000000),
        offset: Offset(0, -10),
        blurRadius: 26,
      ),
    ],
  );

  /// Pill chip in its resting state.
  static BoxDecoration chipPill({
    bool active = false,
    double radius = pillRadius,
  }) => BoxDecoration(
    color: active ? const Color(0x2E007BFF) : const Color(0x0FDDE6F4),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: active ? const Color(0x8C007BFF) : const Color(0x24DDE6F4),
    ),
    boxShadow: active
        ? const [
            BoxShadow(
              color: Color(0x4D007BFF),
              offset: Offset(0, 0),
              blurRadius: 16,
            ),
          ]
        : null,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
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

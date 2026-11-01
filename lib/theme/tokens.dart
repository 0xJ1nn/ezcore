import 'package:flutter/material.dart';

/// Visual states shared by the primary and secondary button tokens.
///
/// The screen layer only picks the state; the fill, shadow and transform
/// values live here so every button in the app stays in sync.
enum OrbitButtonState { rest, hover, pressed, disabled }

/// ezCORE (Orbit console) design tokens.
///
/// Orbit's approved identity: midnight navy, electric blue, silver-white,
/// dark only. The blue-black surfaces add depth around the existing brand
/// accent without changing the ezCORE marks or type.
///
/// Every colour, radius, type style, motion curve and elevation the UI uses
/// is declared here, which is what makes a future theme system a swap of
/// this one file rather than a rewrite of the screens.
///
/// Display: Space Grotesk · Body: Manrope (bundled in assets/fonts,
/// OFL-licensed — fully offline, no runtime font fetching).
/// Icons: Material Symbols Rounded (bundled variable subset, Apache-2.0).
/// See `lib/theme/symbols.dart` for the icon constants.
abstract final class Tokens {
  // ---- Core (final) ----
  static const bg = Color(0xFF060B14);
  static const text = Color(0xFFDDE6F4);
  static const muted = Color(0xFF9AA8BC);
  static const line = Color(0x16FFFFFF); // rgba(255,255,255,0.086)
  static const lineStrong = Color(0x2BDDE6F4); // #DDE6F42B raised hairline
  static const accent = Color(0xFF007BFF);
  static const accentHi = Color(0xFF0086FF);
  static const accentDeep = Color(0xFF0065ED);
  static const panel = Color(0xFF0F1825);
  static const dockTop = Color(0xFF17263A);
  static const dockBottom = Color(0xFF0B1421);
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

  /// Destructive *text* (never a fill).
  static const dangerText = Color(0xFFFF8A80);

  static const ok = Color(0xFF7DE89A);

  /// Needs a BIOS file or a core. **NEW** in Orbit.
  static const warn = Color(0xFFFFC46B);

  /// Eyebrows, icons, the favourite heart and links. Inline in the design.
  static const iconBlue = Color(0xFF4DA3FF);

  /// Toast pill background (inline in the design).
  static const toastBg = Color(0xFF14202F);

  /// 7 px outer focus glow. **NEW** in Orbit.
  static const focusHalo = Color(0x3D007BFF); // rgba(0,123,255,0.24)

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

  // ---- Brand taglines (the brand sheet) ----
  static const taglineMain = 'EMULATION SHOULDN’T BE HARD.';
  static const taglinePlay = 'PLAY  ·  PRESERVE  ·  ANYWHERE';
  static const taglineLeft = 'GAMES BRING US CLOSER.';
  static const taglineRight = 'ONE APP  ·  ALL GAMES  ·  YOUR WAY';
  static const taglinePillars = 'SIMPLE  |  POWERFUL  |  EVERYWHERE';

  // ---- Spacing (Orbit s1–s8) ----
  static const s1 = 4.0; // icon gaps
  static const s2 = 8.0; // chip gaps
  static const s3 = 12.0; // button gaps
  static const s4 = 16.0; // Tokens.pad
  static const s5 = 24.0; // card padding
  static const s6 = 32.0; // dock padding
  static const s7 = 44.0; // osPad on desktop
  static const s8 = 64.0; // TV safe area

  // ---- Geometry ----
  static const radiusSm = 8.0;
  static const radiusMd = 14.0;
  static const radiusLg = 22.0;
  static const radiusCover = 6.0; // CHANGED 5 → 6
  static const radiusCase = 6.0;
  static const radiusDock = 20.0; // CHANGED 18 → 20
  static const radiusDialog = 22.0; // CHANGED 10 → 22
  static const radiusCoreCard = 20.0;
  static const radiusPrimary = 12.0;
  static const radiusRound = 12.0;
  static const radiusFlowBtn = 8.0;
  static const radiusBadge = 999.0; // Pill
  static const radiusToast = 999.0; // Pill
  static const radiusPill = 999.0; // Chips, toasts, glyphs
  static const radiusSheet = 24.0; // Bottom sheets (top corners)
  static const radiusSearch = 23.0; // Library search field
  static const pad = s4;

  // ---- Motion ----
  /// Orbit out — everything that enters, focuses, turns or grows.
  static const ease = Cubic(0.22, 1, 0.36, 1);

  /// Orbit in-out — **NEW**. Only for things leaving the screen.
  static const easeInOut = Cubic(0.65, 0, 0.35, 1);

  /// Press feedback (90–130 ms).
  static const instantDur = Duration(milliseconds: 120);

  /// Focus / hover / toggle.
  static const fastDur = Duration(milliseconds: 200);

  /// Sheets, toasts, dialogs.
  static const baseDur = Duration(milliseconds: 320);

  /// Pause recede, launch grow (520–560 ms).
  static const moveDur = Duration(milliseconds: 540);

  /// Page enter, shelf camera (650 ms).
  static const ambientDur = Duration(milliseconds: 650);

  /// Room tint, parallax (900–1200 ms).
  static const sceneDur = Duration(milliseconds: 1100);

  /// Legacy name for [ambientDur].
  static const easeDur = ambientDur;

  /// Primary button focus lift.
  static const buttonHoverLift = -2.0;

  /// Primary button press scale.
  static const buttonPressScale = 0.95;

  /// Single responsive side-margin: clamp(20, w*0.03, 52).
  /// Portrait layouts use 24, short landscape callers use 26.
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

  static const double rail = 104; // CHANGED 112 → 104
  static const double railShort = 72;

  // ---- Responsive breakpoints (shared by every screen) ----
  // Five layout families mirror the studio plate:
  //   phone portrait  — bottom command bar, featured game, continue row
  //   phone landscape — compact command rail, short cover flow
  //   tablet          — command rail, hub rows
  //   tablet portrait — command rail, spacious hub rows
  //   desktop         — command rail, cover flow + game dock
  static const double bpCompact = 700; // below this: phone
  static const double bpDesktop = 1180; // at/above this: desktop
  static const double bpShortHeight = 650; // short landscape phones

  // ---- Geometry for the new chrome ----
  static const double bottomBarHeight = 64;
  static const double dockPanelRadius = radiusDock;
  static const double statPanelRadius = 14;
  static const double pillRadius = radiusPill;
  static const double tileRadius = 12;

  // ---- Type (Space Grotesk display / Manrope body, bundled) ----
  static const displayFamily = 'SpaceGrotesk';
  static const bodyFamily = 'Manrope';

  /// System monospace for paths, hashes and cheat codes.
  static const monoFamily = 'monospace';
  static const monoFallback = <String>['Menlo', 'Courier New', 'Courier'];

  static TextStyle display({
    double size = 30,
    FontWeight weight = FontWeight.w500,
    double ls = -1.0,
    Color color = text,
    double? height,
  }) => TextStyle(
    fontFamily: displayFamily,
    // Avoid the tiny 8–11 px labels that made the shell hard to scan.
    // Display titles keep their requested size; only micro-labels are lifted.
    fontSize: size < 12 ? 12 : size,
    fontWeight: weight,
    letterSpacing: ls,
    color: color,
    height: height,
  );

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    double ls = 0,
    Color color = text,
    double? height = 1.5,
  }) => TextStyle(
    fontFamily: bodyFamily,
    fontSize: size < 12 ? 12 : size,
    fontWeight: weight,
    letterSpacing: ls,
    color: color,
    height: height,
  );

  /// Monospace (paths, codes). Use `size: 17, height: 1.8` for cheat codes.
  static TextStyle mono({
    double size = 13,
    FontWeight weight = FontWeight.w500,
    Color color = text,
    double? height,
  }) => TextStyle(
    fontFamily: monoFamily,
    fontFamilyFallback: monoFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
  );

  // ---- Type roles (§3.2) ----
  // Named `displayHero` etc. so the design roles stay greppable.

  /// Detail title: 76 / 0.95, 700, −0.035em.
  static TextStyle get displayHero => display(
    size: 76,
    weight: FontWeight.w700,
    ls: -0.035 * 76,
    height: 0.95,
  );

  /// Screen title: 44 / 1, 600, −0.03em.
  static TextStyle get displayScreen => display(
    size: screenTitle,
    weight: FontWeight.w600,
    ls: -0.03 * screenTitle,
    height: 1,
  );

  /// Dock title: 32 / 1, 600, −0.02em.
  static TextStyle get displayDock => display(
    size: 32,
    weight: FontWeight.w600,
    ls: -0.02 * 32,
    height: 1,
  );

  /// Panel / dialog title: 26 / 1.1, 600, −0.02em (dialog uses 28).
  static TextStyle get displayPanel => display(
    size: 26,
    weight: FontWeight.w600,
    ls: -0.02 * 26,
    height: 1.1,
  );

  /// Dialog title at 28.
  static TextStyle get displayDialog => display(
    size: 28,
    weight: FontWeight.w600,
    ls: -0.02 * 28,
    height: 1.1,
  );

  /// Section title: 19 / 1, 600, −0.01em.
  static TextStyle get sectionTitle => display(
    size: 19,
    weight: FontWeight.w600,
    ls: -0.01 * 19,
    height: 1,
  );

  /// Eyebrow: 13, 500, +0.30em, uppercase (callers uppercase the copy).
  static TextStyle get eyebrow => const TextStyle(
    fontFamily: displayFamily,
    fontSize: 13,
    letterSpacing: 0.30 * 13,
    color: iconBlue,
    fontWeight: FontWeight.w500,
  );

  /// Buttons and menu items: 17, 700.
  static TextStyle get bodyAction => body(
    size: 17,
    weight: FontWeight.w700,
    height: null,
  );

  /// Buttons inside the dock / detail: 16, 700.
  static TextStyle get bodyActionDock => body(
    size: 16,
    weight: FontWeight.w700,
    height: null,
  );

  /// Dialog body / notes: 16 / 1.6, 500.
  static TextStyle get bodyLead => body(size: 16, height: 1.6);

  /// Body role: 14 / 1.5, 500 (already the [body] default).
  static TextStyle get bodyBase => body();

  /// Floor for any text: 12.5, 600.
  static TextStyle get labelMin =>
      body(size: 12.5, weight: FontWeight.w600, height: null);

  /// Stat label: 12, uppercase, 600, +0.08em.
  static TextStyle get statLabel => body(
    size: 12,
    weight: FontWeight.w600,
    ls: 0.08 * 12,
    color: muted,
    height: 1.2,
  );

  /// Stat value: Space Grotesk 19, 600.
  static TextStyle get statValue => display(
    size: 19,
    weight: FontWeight.w600,
    ls: 0,
    height: 1.1,
  );

  /// System badge: Space Grotesk 12, 600, +0.10em.
  static TextStyle get systemLabel => display(
    size: 12,
    weight: FontWeight.w600,
    ls: 0.10 * 12,
    color: systemLabelFg,
  );

  /// Glyph chip: Space Grotesk 11.5–12, 700. The 12 px floor wins.
  static TextStyle get glyphChip => display(
    size: 12,
    weight: FontWeight.w700,
    ls: 0,
  );

  /// Rail footer: Space Grotesk 11–12, 500, +0.24em.
  static TextStyle get railFooter => display(
    size: 12,
    weight: FontWeight.w500,
    ls: 0.24 * 12,
    color: separator,
  );

  /// Dock metadata line: 13, 500, muted.
  static TextStyle get dockMeta => body(
    size: 13,
    color: muted,
    height: null,
  );

  /// Big screen title size: "The collection" (44).
  static const screenTitle = 44.0;

  // ---- Legacy aliases ----
  // Screens still reference these names; they now resolve to the Orbit
  // roles above so a rename can land screen by screen.

  /// @Deprecated use [displayScreen].
  @Deprecated('Use Tokens.displayScreen')
  static TextStyle get h1 => displayScreen;

  /// @Deprecated use [displayDock].
  @Deprecated('Use Tokens.displayDock')
  static TextStyle get dockTitle => displayDock;

  /// @Deprecated use [body] / [bodyBase].
  @Deprecated('Use Tokens.body')
  static TextStyle get dockBodyStyle => body();

  /// @Deprecated use [body].
  @Deprecated('Use Tokens.body')
  static TextStyle get gameMeta => body(size: 14);

  /// @Deprecated use [body].
  @Deprecated('Use Tokens.body')
  static TextStyle get flowCount => body(size: 16, color: muted);

  /// Collection chip label: 14, 600, muted.
  static TextStyle get chipLabel =>
      body(size: 14, weight: FontWeight.w600, color: muted, height: null);

  /// @Deprecated use [railFooter].
  @Deprecated('Use Tokens.railFooter')
  static TextStyle get footerStyle => railFooter;

  /// @Deprecated use [body].
  @Deprecated('Use Tokens.body')
  static TextStyle get standfirst => body(color: muted);

  /// "See all" affordance on the right of a section title.
  static TextStyle get sectionLink =>
      body(size: 12.5, color: accent, weight: FontWeight.w600, height: null);

  /// Small rounded tag on a game: "1.2 GB", "PSX".
  static TextStyle get tileTag =>
      labelMin.copyWith(color: text, letterSpacing: 0.2);

  // ---- Elevation (§3.5) ----

  /// Level 1 — Recessed: stat panel.
  static BoxDecoration get statPanelDecor => BoxDecoration(
    borderRadius: BorderRadius.circular(statPanelRadius),
    color: const Color(0x80060A11), // rgba(6,10,17,.5)
    border: Border.all(color: const Color(0x1FDDE6F4)), // .12 ring
  );

  /// Level 2 — Card: core cards.
  static BoxDecoration get coreCardDecor => BoxDecoration(
    borderRadius: BorderRadius.circular(radiusCoreCard),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1B2A3D), Color(0xFF0C1522)],
      stops: [0.0, 0.65],
    ),
    border: Border.all(color: const Color(0x29DDE6F4)), // .16 ring
    boxShadow: const [
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
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF1B2A3D), Color(0xFF0C1522)],
      stops: [0.0, 0.65],
    ),
    border: Border.all(color: const Color(0xFF6EB4FF)),
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

  /// Level 3 — Glass: the selected-game dock, panels, section tiles.
  static BoxDecoration get dockDecor => BoxDecoration(
    borderRadius: BorderRadius.circular(radiusDock),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xF21B2430), Color(0xF20B111B)],
      stops: [0.0, 0.7],
    ),
    border: const Border(
      top: BorderSide(color: Color(0x0FFFFFFF)), // inset top hairline
      left: BorderSide(color: lineStrong),
      right: BorderSide(color: lineStrong),
      bottom: BorderSide(color: lineStrong),
    ),
    boxShadow: const [
      BoxShadow(
        color: Color(0x7A000000), // rgba(0,0,0,.48)
        offset: Offset(0, 18),
        blurRadius: 42,
      ),
    ],
  );

  /// Glass card: the selected-game dock, stat panel, and section tiles.
  static BoxDecoration get panelGlass => dockDecor;

  /// Level 4 — Modal dialog.
  static BoxDecoration get dialogDecor => BoxDecoration(
    borderRadius: BorderRadius.circular(radiusDialog),
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [dockTop, bg],
      stops: [0.0, 0.65],
    ),
    border: Border.all(color: const Color(0x30DDE6F4)), // .19 ring
    boxShadow: const [
      BoxShadow(
        color: Color(0x99000000),
        offset: Offset(0, 35),
        blurRadius: 150,
      ),
    ],
  );

  /// Level 4 — Modal bottom sheet.
  static BoxDecoration get sheetDecor => BoxDecoration(
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(radiusSheet),
    ),
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF182231), Color(0xFF0A0F18)],
    ),
    border: const Border(top: BorderSide(color: lineStrong)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x99000000),
        offset: Offset(0, 35),
        blurRadius: 150,
      ),
    ],
  );

  // ---- Focus halo (§3.6) ----

  /// HALO: 2 px accent ring, 7 px halo, blue drop.
  static const halo = <BoxShadow>[
    BoxShadow(color: accent, blurRadius: 0, spreadRadius: 2),
    BoxShadow(color: focusHalo, blurRadius: 0, spreadRadius: 7),
    BoxShadow(
      color: Color(0x99007BFF), // rgba(0,123,255,.6)
      offset: Offset(0, 16),
      blurRadius: 40,
      spreadRadius: -12,
    ),
  ];

  /// HALO3: TV focus halo (3 px + 11 px).
  static const halo3 = <BoxShadow>[
    BoxShadow(color: accent, blurRadius: 0, spreadRadius: 3),
    BoxShadow(color: focusHalo, blurRadius: 0, spreadRadius: 11),
  ];

  /// RING: resting 1 px outline, as an inset border.
  static const ringBorder = Border.fromBorderSide(
    BorderSide(color: Color(0x24DDE6F4)), // rgba(221,230,244,.14)
  );

  /// RING as an outer shadow (for surfaces that cannot take a border).
  static const ring = <BoxShadow>[
    BoxShadow(color: Color(0x24DDE6F4), blurRadius: 0, spreadRadius: 1),
  ];

  // ---- Button states (§3.7) ----

  /// Primary button: accent fill, blue drop, inset top highlight.
  static BoxDecoration primaryButton({
    OrbitButtonState state = OrbitButtonState.rest,
    double radius = radiusPrimary,
  }) {
    final fill = switch (state) {
      OrbitButtonState.rest => accent,
      OrbitButtonState.hover => accentHi,
      OrbitButtonState.pressed => accentDeep,
      OrbitButtonState.disabled => accent.withValues(alpha: 0.4),
    };
    final shadows = switch (state) {
      OrbitButtonState.rest => const [
        BoxShadow(
          color: Color(0xB3007BFF), // rgba(0,123,255,.7)
          offset: Offset(0, 10),
          blurRadius: 24,
          spreadRadius: -10,
        ),
      ],
      OrbitButtonState.hover || OrbitButtonState.pressed => halo,
      OrbitButtonState.disabled => const <BoxShadow>[],
    };
    return BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(radius),
      border: state == OrbitButtonState.disabled
          ? null
          : const Border(top: BorderSide(color: Color(0x38FFFFFF))),
      boxShadow: shadows,
    );
  }

  /// Secondary button: quiet fill plus RING; HALO on focus/hover.
  static BoxDecoration secondaryButton({
    OrbitButtonState state = OrbitButtonState.rest,
    double radius = radiusPrimary,
  }) {
    final focused =
        state == OrbitButtonState.hover || state == OrbitButtonState.pressed;
    final fill = focused
        ? const Color(0x1ADDE6F4) // .10
        : const Color(0x0DDDE6F4); // .05
    return BoxDecoration(
      color: state == OrbitButtonState.disabled
          ? fill.withValues(alpha: 0.4)
          : fill,
      borderRadius: BorderRadius.circular(radius),
      border: ringBorder,
      boxShadow: focused ? halo : null,
    );
  }

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
        labelStyle: body(size: 14, weight: FontWeight.w600),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: searchIdle,
        hintStyle: body(size: 14, color: muted),
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
        backgroundColor: toastBg,
        contentTextStyle: body(
          size: 15,
          weight: FontWeight.w600,
          color: Colors.white,
          height: null,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusToast),
          side: const BorderSide(color: Color(0x24DDE6F4)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      focusColor: accent.withValues(alpha: 0.12),
    );
  }
}

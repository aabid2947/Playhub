import 'package:flutter/material.dart';

/// Spacing scale — use these instead of magic numbers in padding/margin.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Hero / large section gaps (page headers, splash, empty states).
  static const double xxxl = 48;
}

/// Border-radius scale.
class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;

  /// Large surfaces — bottom sheets, hero cards.
  static const double xxl = 28;
  static const double pill = 999;
}

/// Standard animation durations.
class AppDuration {
  const AppDuration._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
}

/// Material elevation tokens.
class AppElevation {
  const AppElevation._();

  static const double none = 0;
  static const double low = 1;
  static const double med = 3;
  static const double high = 8;
}

/// Typography tokens — the font family, weights, and letter-spacing (tracking)
/// the type scale uses. The actual [TextTheme] is assembled in `core/theme.dart`
/// from Google Inter; these tokens keep the theme and any bespoke text styles
/// in sync. Prefer `Theme.of(context).textTheme.*` over building styles by hand
/// — reach for these only when a one-off needs a specific weight or tracking.
class AppType {
  const AppType._();

  static const String fontFamily = 'Inter';

  // Weights (matches typography.ts fontWeight).
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight heavy = FontWeight.w800;

  // Letter-spacing (tracking) — matches typography.ts letterSpacing. Large
  // display type tightens for a crafted feel; small labels open up.
  static const double trackingTight = -0.5; // tighter (display)
  static const double trackingSnug = -0.3; // tight (headlines / titles)
  static const double trackingNormal = 0; // body
  static const double trackingWide = 0.3; // labels, buttons
  static const double trackingWider = 0.5; // section headers
  static const double trackingWidest = 1; // all-caps meta labels
}

/// Font-size scale (logical px) mirroring typography.ts `fontSize`. Flutter
/// applies device text-scaling automatically via `MediaQuery.textScaler`, so
/// these are the base design sizes. The global [TextTheme] in `core/theme.dart`
/// is the primary surface for text; reach for these only for a bespoke style.
class AppFontSize {
  const AppFontSize._();

  static const double xs = 11; // timestamps, meta labels
  static const double sm = 12; // captions, secondary text
  static const double md = 13; // comments, sub-body
  static const double base = 14; // default body
  static const double lg = 15; // primary text
  static const double xl = 17; // section headers
  static const double xxl = 20; // screen titles
  static const double h2 = 24; // large headings
  static const double h1 = 30; // hero headings
  static const double display = 36; // splash / marketing
}

/// Brand + semantic palette ("Sports-Light" v1). Solid anchor colors, usable
/// inline anywhere in a widget tree. For backgrounds/foregrounds that must
/// adapt to light/dark, use the theme-aware [AppSemanticColors] instead.
///
/// v1 identity (locked, mirrored in colors.ts `lightColors`): an energetic
/// **orange** (`#FF6A2C`) leads every call-to-action; a deep **navy** ink
/// (`#0F2540`) carries headings/high-contrast text; a broadcast **blue**
/// (`#1763E0`) accents sparingly. The app ships **light only** — the dark
/// neutrals below are retained but dormant.
class AppPalette {
  const AppPalette._();

  // Brand — energetic orange leads every call-to-action.
  static const Color brandPrimary = Color(0xFFFF6A2C); // vivid orange
  static const Color brandPrimaryDark = Color(0xFFF4511E); // pressed / grad end
  static const Color brandPrimarySoft = Color(0xFFFFF1EA); // tint bg / nav pill
  static const Color brandPrimaryMuted = Color(0xFFFFD9C7); // borders on tint

  // Accent — broadcast blue, links / secondary highlights (colors.ts secondary).
  static const Color brandSecondary = Color(0xFF1763E0);
  static const Color accent = Color(0xFF1763E0);
  static const Color accentSoft = Color(0xFFE9F1FE);

  // Ink — deep navy for headings + high-contrast text on light surfaces.
  static const Color ink = Color(0xFF0F2540); // deep navy (titles)
  static const Color inkSoft = Color(0xFF1B3A5C); // navy gradient end
  static const Color textPrimary = Color(0xFF12283F);
  static const Color textSecondary = Color(0xFF5B6B7F);
  static const Color textMuted = Color(0xFF8A99AC);

  // Semantic — standard status colors, independent of the brand (colors.ts).
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF1763E0); // accent / info blue

  // Semantic — lifted for legibility on dark surfaces (dormant: light-only app).
  static const Color successDark = Color(0xFF4ADE80);
  static const Color warningDark = Color(0xFFFBBF24);
  static const Color dangerDark = Color(0xFFF87171);
  static const Color infoDark = Color(0xFF4DB3F5);

  // Light surfaces (colors.ts lightColors): near-white page, white cards, a
  // hairline border, and an inset alt for segment tracks / tinted icon boxes.
  static const Color pageBackground = Color(0xFFF4F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFEFF4FA);
  static const Color borderLight = Color(0xFFE6EDF5);
  static const Color dividerLight = Color(0xFFEDF1F7);

  // Neutral grays (slate-tinted) — kept for incidental use.
  static const Color gray50 = Color(0xFFF8FAFC);
  static const Color gray100 = Color(0xFFF1F5F9);
  static const Color gray200 = Color(0xFFE2E8F0);
  static const Color gray300 = Color(0xFFCBD5E1);
  static const Color gray400 = Color(0xFF94A3B8);
  static const Color gray500 = Color(0xFF64748B);
  static const Color gray600 = Color(0xFF475569);
  static const Color gray700 = Color(0xFF334155);
  static const Color gray800 = Color(0xFF1E293B);
  static const Color gray900 = Color(0xFF0F172A);

  // Dark-theme neutrals — retained but DORMANT (the app pins light mode).
  static const Color ink950 = Color(0xFF141318); // page background
  static const Color ink900 = Color(0xFF1C1D22); // surface
  static const Color ink800 = Color(0xFF212129); // cards / inputs / elevated
  static const Color ink700 = Color(0xFF2A2D34); // borders
  static const Color ink600 = Color(0xFF3A3D45);
  static const Color ink400 = Color(0xFF9CA3AF); // secondary text
  static const Color ink100 = Color(0xFFFAFAFA); // primary text on dark

  // Surface tints.
  static const Color surfaceTintLight = Color(0xFFF5F5F5);
  static const Color surfaceTintDark = Color(0xFF1C1D22);

  // Brand gradient — an orange sweep for hero bands, brand marks, peak chart bars.
  static const List<Color> brandGradient = [
    Color(0xFFFF8A4C),
    Color(0xFFFF6A2C),
    Color(0xFFF4511E),
  ];

  // Navy gradient — finance / profile / "more" hero bands.
  static const List<Color> navyGradient = [
    Color(0xFF173B62),
    Color(0xFF0F2540),
  ];

  // Rotating palette for sport / category accents (deterministic via name).
  static const List<Color> categorySwatch = [
    Color(0xFFFF6A2C), // orange
    Color(0xFF1763E0), // blue
    Color(0xFF16A34A), // green
    Color(0xFF9333EA), // purple
    Color(0xFFEA580C), // amber-orange
    Color(0xFF0EA5E9), // sky
  ];
}

/// Soft, layered shadows for the v1 light theme. Subtle by design — cards lift
/// gently off the near-white page rather than relying only on a hairline border.
class AppShadows {
  const AppShadows._();

  /// Default card lift.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F0F2540), blurRadius: 18, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x080F2540), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// Brand-tinted lift for emphasized/elevated surfaces.
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x1AFF6A2C), blurRadius: 20, offset: Offset(0, 10)),
  ];

  /// Stronger lift for pinned bottom bars / sheets / overlapping hero cards.
  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x1F0F2540), blurRadius: 28, offset: Offset(0, 14)),
  ];
}

/// Theme-aware semantic colors (success / warning / danger / info).
///
/// Registered on [ThemeData.extensions] in `core/theme.dart`, so the correct
/// light/dark variant resolves automatically. Read via
/// `AppSemanticColors.of(context)`.
///
/// Each tone exposes three colors:
/// * [success] / [warning] / [danger] / [info] — the saturated color for
///   icons, text, and borders.
/// * `*Container` — a soft translucent tint for backgrounds (badges, chips,
///   banners).
/// * `on*` — the foreground for text/icons placed on a **filled solid** swatch
///   (e.g. a toned snackbar).
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.successContainer,
    required this.onSuccess,
    required this.warning,
    required this.warningContainer,
    required this.onWarning,
    required this.danger,
    required this.dangerContainer,
    required this.onDanger,
    required this.info,
    required this.infoContainer,
    required this.onInfo,
  });

  final Color success;
  final Color successContainer;
  final Color onSuccess;
  final Color warning;
  final Color warningContainer;
  final Color onWarning;
  final Color danger;
  final Color dangerContainer;
  final Color onDanger;
  final Color info;
  final Color infoContainer;
  final Color onInfo;

  /// Light-theme tones. Containers are the base color at ~13% alpha.
  static const AppSemanticColors light = AppSemanticColors(
    success: AppPalette.success,
    successContainer: Color(0x2116A34A),
    onSuccess: Colors.white,
    warning: AppPalette.warning,
    warningContainer: Color(0x21F59E0B),
    onWarning: Color(0xFF422006),
    danger: AppPalette.danger,
    dangerContainer: Color(0x21EF4444),
    onDanger: Colors.white,
    info: AppPalette.info,
    infoContainer: Color(0x211763E0),
    onInfo: Colors.white,
  );

  /// Dark-theme tones. Bases are lifted; containers sit at ~22% alpha.
  static const AppSemanticColors dark = AppSemanticColors(
    success: AppPalette.successDark,
    successContainer: Color(0x384ADE80),
    onSuccess: Color(0xFF052E16),
    warning: AppPalette.warningDark,
    warningContainer: Color(0x38FBBF24),
    onWarning: Color(0xFF422006),
    danger: AppPalette.dangerDark,
    dangerContainer: Color(0x38F87171),
    onDanger: Color(0xFF450A0A),
    info: AppPalette.infoDark,
    infoContainer: Color(0x384DB3F5),
    onInfo: Color(0xFF082F49),
  );

  /// Resolve the active tones for [context]; falls back to [light] if the
  /// extension is somehow absent.
  static AppSemanticColors of(BuildContext context) =>
      Theme.of(context).extension<AppSemanticColors>() ?? light;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccess,
    Color? warning,
    Color? warningContainer,
    Color? onWarning,
    Color? danger,
    Color? dangerContainer,
    Color? onDanger,
    Color? info,
    Color? infoContainer,
    Color? onInfo,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarning: onWarning ?? this.onWarning,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDanger: onDanger ?? this.onDanger,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfo: onInfo ?? this.onInfo,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
    );
  }
}

/// Responsive breakpoints (logical pixels).
class AppBreakpoints {
  const AppBreakpoints._();

  static const double phone = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
}

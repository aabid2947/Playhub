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

  // Weights.
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  // Letter-spacing (tracking). Large display type tightens for a crafted feel;
  // small labels open up for legibility.
  static const double trackingTight = -0.5; // display
  static const double trackingSnug = -0.2; // headlines / titles
  static const double trackingNormal = 0; // body
  static const double trackingWide = 0.4; // labels, buttons
  static const double trackingWider = 0.8; // overlines / section headers
}

/// Brand + semantic palette. These are the solid anchor colors, usable inline
/// anywhere in a widget tree. For backgrounds/foregrounds that must adapt to
/// light vs dark, use the theme-aware [AppSemanticColors] instead.
class AppPalette {
  const AppPalette._();

  // Brand — Instagram-style. Magenta leads, purple accents, with the iconic
  // blue → purple → magenta → pink → gold gradient for brand moments. Hexes
  // are from Instagram's brand palette (sources cited in core/theme.dart).
  static const Color brandPrimary = Color(0xFFC13584); // Instagram magenta
  static const Color brandSecondary = Color(0xFF833AB4); // Instagram purple

  // Semantic — standard status colors, independent of the brand.
  static const Color success = Color(0xFF14A800);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF0EA5E9);

  // Semantic — lifted for legibility on dark surfaces.
  static const Color successDark = Color(0xFF4ADE80);
  static const Color warningDark = Color(0xFFFBBF24);
  static const Color dangerDark = Color(0xFFF87171);
  static const Color infoDark = Color(0xFF38BDF8);

  // Neutral grays (slate-tinted) — light-theme surfaces + text.
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

  // Dark-theme neutrals — a premium near-black ramp (Tailwind "zinc"). Pairs
  // with the green accents for the Upwork-style "green + black" dark theme.
  static const Color ink950 = Color(0xFF09090B); // page background
  static const Color ink900 = Color(0xFF18181B); // cards
  static const Color ink800 = Color(0xFF27272A); // inputs / elevated
  static const Color ink700 = Color(0xFF3F3F46); // borders
  static const Color ink600 = Color(0xFF52525B);
  static const Color ink400 = Color(0xFFA1A1AA); // secondary text
  static const Color ink100 = Color(0xFFF4F4F5); // primary text on dark

  // Surface tints.
  static const Color surfaceTintLight = Color(0xFFF1F5F9);
  static const Color surfaceTintDark = Color(0xFF18181B);

  // Brand gradient — the iconic Instagram sweep (blue → purple → magenta →
  // pink → gold), for brand marks, hero headers, and splash.
  static const List<Color> brandGradient = [
    Color(0xFF405DE6), // blue
    Color(0xFF833AB4), // purple
    Color(0xFFC13584), // magenta
    Color(0xFFE1306C), // pink
    Color(0xFFFCAF45), // gold
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
    successContainer: Color(0x2114A800),
    onSuccess: Colors.white,
    warning: AppPalette.warning,
    warningContainer: Color(0x21F59E0B),
    onWarning: Color(0xFF422006),
    danger: AppPalette.danger,
    dangerContainer: Color(0x21DC2626),
    onDanger: Colors.white,
    info: AppPalette.info,
    infoContainer: Color(0x210EA5E9),
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
    infoContainer: Color(0x3838BDF8),
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

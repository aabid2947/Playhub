import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:playhub/core/design_tokens.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = _scheme(brightness);
    final semantics =
        isLight ? AppSemanticColors.light : AppSemanticColors.dark;
    final textTheme = _textTheme(brightness);

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );
    const buttonMinimumSize = Size(0, 48);
    final buttonTextStyle = textTheme.labelLarge;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor:
          isLight ? Colors.white : AppPalette.ink950,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      extensions: <ThemeExtension<dynamic>>[semantics],

      // Cards: outlined, no shadow, lg radius. Card surface stays a step
      // brighter than the scaffold so it reads as a distinct plane.
      cardTheme: CardThemeData(
        elevation: AppElevation.none,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // Inputs: filled, md radius, no default outline; 1.5px primary on focus.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      // Filled buttons.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonMinimumSize,
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),

      // Elevated buttons (mirror filled).
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonMinimumSize,
          shape: buttonShape,
          textStyle: buttonTextStyle,
          elevation: AppElevation.none,
        ),
      ),

      // Outlined buttons.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonMinimumSize,
          shape: buttonShape,
          textStyle: buttonTextStyle,
          side: BorderSide(color: scheme.outline),
        ),
      ),

      // Text buttons.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),

      // Chips: stadium border with outlineVariant.
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant, width: 1),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        labelStyle: textTheme.labelMedium,
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        secondarySelectedColor: scheme.primaryContainer,
      ),

      // AppBar: minimal, flush with the page.
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: AppElevation.none,
        scrolledUnderElevation: AppElevation.low,
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: AppType.semibold,
          fontSize: 17,
        ),
      ),

      // Bottom navigation (legacy — most shells use NavigationBar below).
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        selectedLabelStyle: textTheme.labelSmall?.copyWith(
          fontWeight: AppType.medium,
        ),
        unselectedLabelStyle: textTheme.labelSmall?.copyWith(
          fontWeight: AppType.medium,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: AppElevation.low,
      ),

      // M3 NavigationBar: violet (primary) selection pill — the brand accent.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.low,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            // Slightly smaller than the M3 default (24) so long labels like
            // "Announcements" don't overflow narrow destinations.
            size: 22,
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            // Compact label: smaller size + tighter tracking so long tab
            // labels fit on one line without overflowing.
            fontSize: 10,
            height: 1.1,
            letterSpacing: 0,
            fontWeight: selected ? AppType.semibold : AppType.medium,
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          );
        }),
      ),

      // Dividers.
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),

      // SnackBar.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        elevation: 2,
      ),

      // ListTile.
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        iconColor: scheme.onSurfaceVariant,
      ),

      // Bottom sheets — large radius, flush surface.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xxl),
          ),
        ),
      ),

      // Dialogs.
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),

      // Progress indicators.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
      ),
    );
  }

  /// Violet brand scheme (colors.ts): an exact violet primary (#9933FF) on
  /// hand-tuned neutral surfaces — white/greys in light, a near-black ramp in
  /// dark — so the brand reads cleanly in both modes. The primary is pinned
  /// explicitly rather than taken from the seed's tonal palette.
  static ColorScheme _scheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: AppPalette.brandPrimary,
      brightness: brightness,
    );

    if (brightness == Brightness.light) {
      return base.copyWith(
        // Brand — exact violet, not a tonal approximation.
        primary: AppPalette.brandPrimary,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFEDE0FF),
        onPrimaryContainer: const Color(0xFF3A1A66),
        secondary: const Color(0xFF00BFFF), // colors.ts light secondary
        error: AppPalette.danger,
        onError: Colors.white,
        // Surfaces — colors.ts light: white bg, #F5F5F5 cards, #E5E5E5 raised,
        // #D1D5DB borders, #111418 text, #4A5568 secondary text.
        surface: const Color(0xFFF5F5F5),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: const Color(0xFFF5F5F5),
        surfaceContainerHigh: const Color(0xFFEDEDED),
        surfaceContainerHighest: const Color(0xFFE5E5E5),
        outlineVariant: const Color(0xFFD1D5DB),
        outline: const Color(0xFFD1D5DB),
        onSurface: const Color(0xFF111418),
        onSurfaceVariant: const Color(0xFF4A5568),
      );
    }

    return base.copyWith(
      // Brand — exact violet, not a tonal approximation.
      primary: AppPalette.brandPrimary,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF2E1A4D), // deep violet pill
      onPrimaryContainer: const Color(0xFFE9D5FF),
      secondary: const Color(0xFF373A43), // colors.ts dark secondary
      error: AppPalette.dangerDark,
      onError: const Color(0xFF450A0A),
      // Surfaces — colors.ts dark.
      surface: AppPalette.ink900,
      surfaceContainerLowest: AppPalette.ink950,
      surfaceContainerLow: AppPalette.ink950,
      surfaceContainer: AppPalette.ink900,
      surfaceContainerHigh: AppPalette.ink800,
      surfaceContainerHighest: AppPalette.ink800,
      outlineVariant: AppPalette.ink700,
      outline: AppPalette.ink700,
      onSurface: AppPalette.ink100,
      onSurfaceVariant: AppPalette.ink400,
    );
  }

  /// Inter type scale with intentional tracking: display/headlines tighten,
  /// labels open up. Body line-height is relaxed to 1.5 for readability.
  static TextTheme _textTheme(Brightness brightness) {
    final base = brightness == Brightness.light
        ? GoogleFonts.interTextTheme()
        : GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    // Explicit sizes (logical px) tuned a step down from the Material 3 defaults
    // — the defaults (titleLarge 22, headline 24-32, body 16) read oversized on a
    // dense, all-day mobile ops tool. This is the single source of truth for the
    // type scale: every screen consumes these roles via `textTheme.*`, so changing
    // a size here cascades app-wide. (Device text-scaling still applies on top.)
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontSize: 36,
        fontWeight: AppType.bold,
        letterSpacing: AppType.trackingTight,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontSize: 30,
        fontWeight: AppType.bold,
        letterSpacing: AppType.trackingTight,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 26,
        fontWeight: AppType.bold,
        letterSpacing: AppType.trackingTight,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: 24,
        fontWeight: AppType.bold,
        letterSpacing: AppType.trackingSnug,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 22,
        fontWeight: AppType.bold,
        letterSpacing: AppType.trackingSnug,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 20,
        fontWeight: AppType.bold,
        letterSpacing: AppType.trackingSnug,
      ),
      // App-bar titles, card/sheet headers, primary list text.
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: AppType.semibold,
        letterSpacing: AppType.trackingSnug,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: AppType.semibold,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 13,
        fontWeight: AppType.semibold,
      ),
      // Body — list-tile primary text (bodyLarge) and default paragraph.
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 15, height: 1.5),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 13, height: 1.5),
      bodySmall: base.bodySmall?.copyWith(fontSize: 12, height: 1.4),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: AppType.semibold,
        letterSpacing: AppType.trackingWide,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: AppType.medium,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: AppType.medium,
        letterSpacing: AppType.trackingWide,
      ),
    );
  }
}

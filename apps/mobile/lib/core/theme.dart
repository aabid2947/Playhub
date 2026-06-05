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
          isLight ? AppPalette.gray50 : AppPalette.ink950,
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
          fontSize: 18,
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

      // M3 NavigationBar: magenta (primary) selection pill — the brand accent.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevation.low,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
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

  /// Instagram-style scheme: a single magenta seed (#C13584), on hand-tuned
  /// neutral surfaces — slate in light, a premium near-black "zinc" ramp in
  /// dark so the magenta + gradient accents pop.
  ///
  /// Brand hexes are from Instagram's palette; the dark neutral ramp is
  /// Tailwind "zinc".
  static ColorScheme _scheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: AppPalette.brandPrimary,
      brightness: brightness,
    );

    if (brightness == Brightness.light) {
      return base.copyWith(
        surface: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: AppPalette.gray50,
        surfaceContainer: AppPalette.gray100,
        surfaceContainerHigh: AppPalette.gray100,
        surfaceContainerHighest: AppPalette.gray200,
        outlineVariant: AppPalette.gray200,
        outline: AppPalette.gray300,
        onSurface: AppPalette.gray900,
        onSurfaceVariant: AppPalette.gray500,
      );
    }

    return base.copyWith(
      surface: AppPalette.ink900,
      surfaceContainerLowest: AppPalette.ink950,
      surfaceContainerLow: AppPalette.ink950,
      surfaceContainer: AppPalette.ink900,
      surfaceContainerHigh: AppPalette.ink800,
      surfaceContainerHighest: AppPalette.ink800,
      outlineVariant: AppPalette.ink800,
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

    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontWeight: AppType.bold,
        letterSpacing: AppType.trackingTight,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontWeight: AppType.bold,
        letterSpacing: AppType.trackingTight,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontWeight: AppType.bold,
        letterSpacing: AppType.trackingTight,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontWeight: AppType.bold,
        letterSpacing: AppType.trackingSnug,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: AppType.bold,
        letterSpacing: AppType.trackingSnug,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: AppType.bold,
        letterSpacing: AppType.trackingSnug,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: AppType.semibold,
        letterSpacing: AppType.trackingSnug,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: AppType.semibold,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: AppType.semibold,
      ),
      bodyLarge: base.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.5),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: AppType.semibold,
        letterSpacing: AppType.trackingWide,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: AppType.medium,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontWeight: AppType.medium,
        letterSpacing: AppType.trackingWide,
      ),
    );
  }
}

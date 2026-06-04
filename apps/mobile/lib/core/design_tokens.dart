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
}

/// Border-radius scale.
class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
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

/// Brand + semantic palette. All values are static const Colors so they can
/// be used inline anywhere in widget trees.
class AppPalette {
  const AppPalette._();

  // Brand
  static const Color brandPrimary = Color(0xFF16A34A); // modern sports green
  static const Color brandSecondary = Color(0xFF0EA5E9); // sky/sport blue

  // Semantic
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF0EA5E9);

  // Neutral grays (slate-tinted)
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

  // Surface tints
  static const Color surfaceTintLight = Color(0xFFF1F5F9);
  static const Color surfaceTintDark = Color(0xFF1E293B);
}

/// Responsive breakpoints (logical pixels).
class AppBreakpoints {
  const AppBreakpoints._();

  static const double phone = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
}

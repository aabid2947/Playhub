import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// Small presentation helpers shared by the v1 widgets (avatars, sport chips,
/// tinted tiles). Pure functions — deterministic so the same name always maps
/// to the same accent color.

/// A deterministic accent color from a name, drawn from [AppPalette.categorySwatch]
/// (used for gradient avatars, sport chips, category dots).
Color colorFromName(String name) {
  if (name.isEmpty) return AppPalette.brandPrimary;
  final code = name.codeUnits.fold<int>(0, (a, b) => a + b);
  return AppPalette.categorySwatch[code % AppPalette.categorySwatch.length];
}

/// Up-to-two-letter initials for [name] ("Meera Kapoor" → "MK").
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

/// Maps a sport name to a representative Material icon. Falls back to a generic
/// sports glyph for anything unrecognised.
IconData sportIcon(String sport) {
  switch (sport.toLowerCase()) {
    case 'cricket':
      return Icons.sports_cricket;
    case 'football':
    case 'soccer':
      return Icons.sports_soccer;
    case 'basketball':
      return Icons.sports_basketball;
    case 'tennis':
      return Icons.sports_tennis;
    case 'badminton':
    case 'table tennis':
      return Icons.sports_tennis;
    case 'swimming':
      return Icons.pool;
    case 'athletics':
    case 'running':
      return Icons.directions_run;
    case 'volleyball':
      return Icons.sports_volleyball;
    case 'gym':
    case 'fitness':
      return Icons.fitness_center;
    default:
      return Icons.sports;
  }
}

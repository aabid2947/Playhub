import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// Static helpers for showing toned SnackBars consistently. Tones resolve
/// through [AppSemanticColors] so they adapt to light/dark.
class AppSnackbar {
  const AppSnackbar._();

  static void success(BuildContext context, String message) {
    final semantics = AppSemanticColors.of(context);
    _show(
      context,
      message,
      icon: Icons.check_circle_outline,
      color: semantics.success,
      onColor: semantics.onSuccess,
    );
  }

  static void error(BuildContext context, String message) {
    final semantics = AppSemanticColors.of(context);
    _show(
      context,
      message,
      icon: Icons.error_outline,
      color: semantics.danger,
      onColor: semantics.onDanger,
    );
  }

  static void info(BuildContext context, String message) {
    final semantics = AppSemanticColors.of(context);
    _show(
      context,
      message,
      icon: Icons.info_outline,
      color: semantics.info,
      onColor: semantics.onInfo,
    );
  }

  static void _show(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color color,
    required Color onColor,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          content: Row(
            children: [
              Icon(icon, color: onColor, size: 20),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: onColor),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

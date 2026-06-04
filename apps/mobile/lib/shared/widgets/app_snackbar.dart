import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// Static helpers for showing toned SnackBars consistently.
class AppSnackbar {
  const AppSnackbar._();

  static void success(BuildContext context, String message) {
    _show(
      context,
      message,
      icon: Icons.check_circle_outline,
      color: AppPalette.success,
    );
  }

  static void error(BuildContext context, String message) {
    _show(
      context,
      message,
      icon: Icons.error_outline,
      color: AppPalette.danger,
    );
  }

  static void info(BuildContext context, String message) {
    _show(
      context,
      message,
      icon: Icons.info_outline,
      color: AppPalette.info,
    );
  }

  static void _show(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color color,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          // ignore: deprecated_member_use
          backgroundColor: color.withOpacity(0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          content: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

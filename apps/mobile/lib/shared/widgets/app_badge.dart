import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

enum AppBadgeTone { neutral, success, warning, danger, info, brand }

/// Tinted pill label.
class AppBadge extends StatelessWidget {
  const AppBadge({
    required this.text,
    this.tone = AppBadgeTone.neutral,
    super.key,
  });

  final String text;
  final AppBadgeTone tone;

  Color _baseColor(BuildContext context) {
    switch (tone) {
      case AppBadgeTone.success:
        return AppPalette.success;
      case AppBadgeTone.warning:
        return AppPalette.warning;
      case AppBadgeTone.danger:
        return AppPalette.danger;
      case AppBadgeTone.info:
        return AppPalette.info;
      case AppBadgeTone.brand:
        return AppPalette.brandPrimary;
      case AppBadgeTone.neutral:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = _baseColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: base.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: base,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

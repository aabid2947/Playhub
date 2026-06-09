import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// v1 section heading: a navy mixed-case title with an optional leading brand
/// icon and a trailing action ("All ›"). Group dashboard/detail/settings
/// sections with this so the page never reads as one flat list.
///
/// Provide a trailing action either via [actionLabel] + [onAction] (renders the
/// standard "label ›" text button) or a custom [trailing] widget (wins if both).
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.trailing,
    super.key,
  });

  final String title;

  /// Optional leading glyph, tinted with the brand color.
  final IconData? icon;

  /// Text for the standard trailing action button (with a chevron).
  final String? actionLabel;
  final VoidCallback? onAction;

  /// A custom trailing widget; takes precedence over [actionLabel].
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    var resolvedTrailing = trailing;
    if (resolvedTrailing == null && actionLabel != null) {
      resolvedTrailing = TextButton(
        onPressed: onAction,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(actionLabel!),
            const Icon(Icons.chevron_right, size: 16),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: AppType.bold,
                color: scheme.onSurface,
              ),
            ),
          ),
          if (resolvedTrailing != null) resolvedTrailing,
        ],
      ),
    );
  }
}

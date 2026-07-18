import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

enum AppBadgeTone { neutral, success, warning, danger, info, brand }

/// Tinted pill label. Colors resolve through [AppSemanticColors] so the tone
/// adapts to light/dark automatically.
class AppBadge extends StatelessWidget {
  const AppBadge({
    required this.text,
    this.tone = AppBadgeTone.neutral,
    this.icon,
    super.key,
  });

  final String text;
  final AppBadgeTone tone;

  /// Optional leading glyph (e.g. a check on "Done", a clock on "Pending").
  final IconData? icon;

  ({Color fg, Color bg}) _colors(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantics = AppSemanticColors.of(context);
    switch (tone) {
      case AppBadgeTone.success:
        return (fg: semantics.success, bg: semantics.successContainer);
      case AppBadgeTone.warning:
        return (fg: semantics.warning, bg: semantics.warningContainer);
      case AppBadgeTone.danger:
        return (fg: semantics.danger, bg: semantics.dangerContainer);
      case AppBadgeTone.info:
        return (fg: semantics.info, bg: semantics.infoContainer);
      case AppBadgeTone.brand:
        return (fg: scheme.primary, bg: scheme.primaryContainer);
      case AppBadgeTone.neutral:
        return (
          fg: scheme.onSurfaceVariant,
          bg: scheme.surfaceContainerHighest,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _colors(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon == null ? AppSpacing.sm : 7,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: colors.fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.fg,
              fontWeight: AppType.semibold,
            ),
          ),
        ],
      ),
    );
  }
}

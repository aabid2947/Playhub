import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

enum AppBadgeTone { neutral, success, warning, danger, info, brand }

/// Tinted pill label. Colors resolve through [AppSemanticColors] so the tone
/// adapts to light/dark automatically.
class AppBadge extends StatelessWidget {
  const AppBadge({
    required this.text,
    this.tone = AppBadgeTone.neutral,
    super.key,
  });

  final String text;
  final AppBadgeTone tone;

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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colors.fg,
          fontWeight: AppType.semibold,
        ),
      ),
    );
  }
}

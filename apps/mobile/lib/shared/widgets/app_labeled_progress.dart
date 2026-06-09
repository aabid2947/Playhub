import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// A thin labeled progress bar — the v1 skill/capacity/collection meter. A
/// label on the left, an optional trailing value, and a rounded determinate
/// bar below. [value] is clamped to 0..1.
class AppLabeledProgress extends StatelessWidget {
  const AppLabeledProgress({
    required this.label,
    required this.value,
    this.trailing,
    this.color,
    super.key,
  });

  final String label;
  final double value;
  final String? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = color ?? scheme.primary;
    final trailingText = trailing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: AppType.semibold,
                ),
              ),
            ),
            if (trailingText != null)
              Text(
                trailingText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: c,
                  fontWeight: AppType.heavy,
                ),
              ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(c),
          ),
        ),
      ],
    );
  }
}

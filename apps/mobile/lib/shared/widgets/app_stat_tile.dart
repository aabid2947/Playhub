import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/shared/widgets/app_card.dart';

/// KPI tile: icon + label + big value, optional trend chip.
/// Renders inside an [AppCard].
class AppStatTile extends StatelessWidget {
  const AppStatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.trend,
    this.trendUp = true,
    this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? trend;

  /// Direction of [trend]: up → success/green pill, down → danger/red pill.
  final bool trendUp;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = AppSemanticColors.of(context);
    final accent = color ?? scheme.primary;
    final trendFg = trendUp ? semantics.success : semantics.danger;
    final trendBg = trendUp ? semantics.successContainer : semantics.dangerContainer;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: accent),
              ),
              if (trend != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: trendBg,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trendUp ? Icons.trending_up : Icons.trending_down,
                        size: 13,
                        color: trendFg,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        trend!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: trendFg,
                          fontWeight: AppType.semibold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: AppType.bold,
            ),
          ),
        ],
      ),
    );
  }
}

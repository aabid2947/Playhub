import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// A dependency-free mini bar chart (the v1 dashboard trend chart). Each bar is
/// a gradient column with its value above and a label below; the peak bar (or
/// the last, configurable) is highlighted with the brand gradient.
///
/// Deliberately not `fl_chart` — for small trend strips on dashboards this is
/// lighter and matches the demo. Wrap it in an [SizedBox] with a fixed height.
class AppMiniBarChart extends StatelessWidget {
  const AppMiniBarChart({
    required this.values,
    required this.labels,
    this.barHeight = 70,
    this.highlight = BarHighlight.peak,
    this.valueSuffix = '',
    super.key,
  });

  final List<double> values;
  final List<String> labels;
  final double barHeight;
  final BarHighlight highlight;

  /// Appended to each value label (e.g. 'k' → "12k", '%' → "84%").
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (values.isEmpty) return const SizedBox.shrink();
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final safeMax = maxV == 0 ? 1 : maxV;
    final peakIndex = values.indexOf(maxV);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(values.length, (i) {
        final h = values[i] / safeMax;
        final isHighlighted = switch (highlight) {
          BarHighlight.peak => i == peakIndex,
          BarHighlight.last => i == values.length - 1,
          BarHighlight.none => false,
        };
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${values[i].toInt()}$valueSuffix',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    fontWeight: AppType.bold,
                    letterSpacing: 0,
                    color: isHighlighted
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: (barHeight * h).clamp(2, barHeight).toDouble(),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isHighlighted
                          ? AppPalette.brandGradient
                          : [
                              scheme.primary.withValues(alpha: 0.35),
                              scheme.primary.withValues(alpha: 0.55),
                            ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  labels.length > i ? labels[i] : '',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10.5,
                    fontWeight: AppType.semibold,
                    letterSpacing: 0,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Which bar to highlight with the brand gradient in [AppMiniBarChart].
enum BarHighlight { peak, last, none }

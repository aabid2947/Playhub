import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// System health + global revenue snapshot.
///
/// App-bar-less body of the super-admin shell (the shell owns the single,
/// constant AppBar) — do not add a Scaffold/AppBar here.
class GlobalHealthPage extends ConsumerWidget {
  const GlobalHealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpiAsync = ref.watch(globalKpiProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(allAcademiesProvider)
          ..invalidate(globalKpiProvider)
          ..invalidate(revenueByMonthProvider)
          ..invalidate(signupsByMonthProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          kpiAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: AppLoading(),
            ),
            error: (e, _) => AppErrorView(
              message: friendlyError(e),
              onRetry: () => ref.invalidate(globalKpiProvider),
            ),
            data: _HealthBody.new,
          ),
          const SizedBox(height: AppSpacing.xl),
          const AppSectionHeader(title: 'SaaS revenue · last 12 months'),
          const _RevenueTrendCard(),
          const SizedBox(height: AppSpacing.xl),
          const AppSectionHeader(title: 'New academies · last 12 months'),
          const _SignupsTrendCard(),
        ],
      ),
    );
  }
}

class _HealthBody extends StatelessWidget {
  const _HealthBody(this.k);

  final GlobalKpi k;

  @override
  Widget build(BuildContext context) {
    final sem = AppSemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GlobalRevenueCard(
          totalRevenue: k.totalRevenue,
          outstandingAmount: k.outstandingAmount,
        ),
        const SizedBox(height: AppSpacing.md),
        AppStatTile(
          icon: Icons.confirmation_number_outlined,
          label: 'Open tickets',
          value: '${k.openTickets}',
          color: k.openTickets > 0 ? sem.warning : null,
        ),
        const SizedBox(height: AppSpacing.xl),
        const AppSectionHeader(title: 'Academies'),
        // "Active" (is_active) is a different axis from the four subscription
        // states below, so it leads as a full-width emphasis tile. That also
        // tidies the odd count: a clean 2×2 grid of the 4 states follows, with
        // no orphaned fifth tile.
        AppStatTile(
          icon: Icons.check_circle_outline,
          label: 'Active academies',
          value: '${k.academiesActive}',
          color: sem.success,
        ),
        const SizedBox(height: AppSpacing.md),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.4,
          children: [
            AppStatTile(
              icon: Icons.schedule_outlined,
              label: 'Trial',
              value: '${k.academiesTrial}',
              color: sem.info,
            ),
            AppStatTile(
              icon: Icons.payments_outlined,
              label: 'Paying',
              value: '${k.academiesPaying}',
            ),
            AppStatTile(
              icon: Icons.warning_amber_outlined,
              label: 'Past due',
              value: '${k.academiesPastDue}',
              color: sem.warning,
            ),
            AppStatTile(
              icon: Icons.block_outlined,
              label: 'Suspended',
              value: '${k.academiesSuspended}',
              color: sem.danger,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const AppSectionHeader(title: 'System'),
        const _SystemHealthCard(),
      ],
    );
  }
}

/// Headline global-revenue callout: the total as the hero value, with
/// outstanding dues as a clearly-delimited secondary fact.
class _GlobalRevenueCard extends StatelessWidget {
  const _GlobalRevenueCard({
    required this.totalRevenue,
    required this.outstandingAmount,
  });

  final double totalRevenue;
  final double outstandingAmount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sem = AppSemanticColors.of(context);
    final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Global revenue',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            f.format(totalRevenue),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: AppType.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 20,
                color: sem.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Outstanding',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                f.format(outstandingAmount),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: AppType.semibold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Placeholder for the full status board, clearly marked as deferred to v1.1.
class _SystemHealthCard extends StatelessWidget {
  const _SystemHealthCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sem = AppSemanticColors.of(context);
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.cloud_done_outlined, color: sem.success),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'System health',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const AppBadge(text: 'v1.1', tone: AppBadgeTone.info),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Edge Functions + cron deployed. The full status board '
                  'lands in v1.1.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _monthAbbrev(DateTime m) => DateFormat('MMM').format(m);

/// Bottom-axis month label, decluttered to every other month so 12 labels
/// don't overlap on a phone.
Widget _monthLabel(BuildContext context, List<MonthPoint> points, double v) {
  final i = v.toInt();
  if (i < 0 || i >= points.length || i.isOdd) return const SizedBox.shrink();
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(top: AppSpacing.xs),
    child: Text(
      _monthAbbrev(points[i].month),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

Widget _emptyChart(BuildContext context, String message) {
  final theme = Theme.of(context);
  return SizedBox(
    height: 120,
    child: Center(
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

/// SaaS revenue collected per month (last 12), as an area/line trend.
class _RevenueTrendCard extends ConsumerWidget {
  const _RevenueTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(revenueByMonthProvider);
    final compact = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹');
    final full = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    return AppCard(
      child: async.when(
        loading: () => const SizedBox(height: 120, child: AppLoading()),
        error: (e, _) => Text(friendlyError(e)),
        data: (points) {
          if (points.every((p) => p.value == 0)) {
            return _emptyChart(context, 'No revenue recorded yet');
          }
          final primary = theme.colorScheme.primary;
          return SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < points.length; i++)
                        FlSpot(i.toDouble(), points[i].value),
                    ],
                    isCurved: true,
                    color: primary,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: primary.withValues(alpha: 0.12),
                    ),
                  ),
                ],
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: theme.colorScheme.outlineVariant,
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      getTitlesWidget: (v, _) => Text(
                        compact.format(v),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      interval: 1,
                      getTitlesWidget: (v, _) => _monthLabel(context, points, v),
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((s) {
                      final p = points[s.x.toInt()];
                      return LineTooltipItem(
                        '${_monthAbbrev(p.month)}\n${full.format(p.value)}',
                        theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onInverseSurface,
                            ) ??
                            const TextStyle(),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// New academy signups per month (last 12), as bars.
class _SignupsTrendCard extends ConsumerWidget {
  const _SignupsTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(signupsByMonthProvider);
    return AppCard(
      child: async.when(
        loading: () => const SizedBox(height: 120, child: AppLoading()),
        error: (e, _) => Text(friendlyError(e)),
        data: (points) {
          if (points.every((p) => p.value == 0)) {
            return _emptyChart(context, 'No signups yet');
          }
          final primary = theme.colorScheme.primary;
          return SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                barGroups: [
                  for (var i = 0; i < points.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: points[i].value,
                          color: primary,
                          width: 12,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(AppRadius.sm),
                          ),
                        ),
                      ],
                    ),
                ],
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: theme.colorScheme.outlineVariant,
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      interval: 1,
                      getTitlesWidget: (v, _) => _monthLabel(context, points, v),
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, _, __, ___) {
                      final p = points[group.x];
                      return BarTooltipItem(
                        '${_monthAbbrev(p.month)}\n${p.value.toInt()}',
                        theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onInverseSurface,
                            ) ??
                            const TextStyle(),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

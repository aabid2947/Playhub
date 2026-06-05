import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/analytics/data/analytics_providers.dart';
import 'package:playhub/features/analytics/data/sport_breakdown.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// KPI dashboard backed by the analytics_* materialized views (refreshed
/// hourly by the analytics-aggregations Edge Function). Shape adapts to
/// the calling user's role so each role sees what's relevant to them.
class KpiDashboardPage extends ConsumerWidget {
  const KpiDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final role = profile?.role ?? '';
    final isOwner = role == 'academy_owner';
    final isAdmin = role == 'academy_admin' || role == 'center_admin';
    final isHeadCoach = role == 'head_coach';

    return Scaffold(
      appBar: AppBar(
        title: const Text('KPI dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref
                ..invalidate(revenueByMonthProvider)
                ..invalidate(enrollmentByMonthProvider)
                ..invalidate(leadFunnelProvider)
                ..invalidate(batchUtilizationProvider)
                ..invalidate(collectionSummaryProvider)
                ..invalidate(sportBreakdownProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (isOwner || isAdmin) ...const [
            _CollectionSummaryCard(),
            SizedBox(height: AppSpacing.md),
            _RevenueTrendCard(),
            SizedBox(height: AppSpacing.md),
          ],
          if (isOwner || isAdmin || isHeadCoach) ...const [
            _EnrollmentTrendCard(),
            SizedBox(height: AppSpacing.md),
            _SportBreakdownCard(),
            SizedBox(height: AppSpacing.md),
            _BatchUtilizationCard(),
            SizedBox(height: AppSpacing.md),
          ],
          if (isOwner || isAdmin) const _LeadFunnelCard(),
        ],
      ),
    );
  }
}

class _CollectionSummaryCard extends ConsumerWidget {
  const _CollectionSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(collectionSummaryProvider);
    return async.when(
      loading: () => const AppCard(child: LinearProgressIndicator()),
      error: (e, _) => AppCard(child: Text(friendlyError(e))),
      data: (s) {
        if (s == null) {
          return const AppCard(child: Text('No invoice data yet'));
        }
        final semantics = AppSemanticColors.of(context);
        final money =
            NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionHeader(title: 'Collection summary'),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: AppStatTile(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Collected',
                    value: money.format(s.collectedTotal),
                    color: semantics.success,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppStatTile(
                    icon: Icons.hourglass_bottom_outlined,
                    label: 'Outstanding (${s.outstandingCount})',
                    value: money.format(s.outstandingAmount),
                    color: semantics.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppStatTile(
                    icon: Icons.warning_amber_outlined,
                    label: 'Overdue invoices',
                    value: '${s.overdueCount}',
                    color: semantics.danger,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppStatTile(
                    icon: Icons.check_circle_outline,
                    label: 'Paid invoices',
                    value: '${s.paidCount}',
                    color: semantics.success,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _RevenueTrendCard extends ConsumerWidget {
  const _RevenueTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(revenueByMonthProvider);
    return AppCard(
      child: async.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text(friendlyError(e)),
        data: (rows) {
          if (rows.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Revenue (last 12 months)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text('No revenue yet'),
              ],
            );
          }
          final maxV = rows
              .map((r) => r.collected)
              .fold<double>(0, (a, b) => a > b ? a : b);
          final f =
              NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹');
          final primary = Theme.of(context).colorScheme.primary;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Revenue trend',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 180,
                child: BarChart(
                  BarChartData(
                    maxY: maxV == 0 ? 1 : maxV * 1.15,
                    alignment: BarChartAlignment.spaceAround,
                    barGroups: [
                      for (var i = 0; i < rows.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: rows[i].collected,
                              color: primary,
                              width: 12,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ],
                        ),
                    ],
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: maxV == 0 ? 1 : maxV / 4,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: Theme.of(context).dividerColor,
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
                          reservedSize: 44,
                          getTitlesWidget: (v, _) => Text(
                            f.format(v),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= rows.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                DateFormat.MMM().format(rows[i].monthStart),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, _, __, ___) {
                          final r = rows[group.x];
                          return BarTooltipItem(
                            '${DateFormat.yMMM().format(r.monthStart)}\n'
                            '${f.format(r.collected)}',
                            const TextStyle(color: Colors.white),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Last month: ${f.format(rows.last.collected)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EnrollmentTrendCard extends ConsumerWidget {
  const _EnrollmentTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(enrollmentByMonthProvider);
    return AppCard(
      child: async.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text(friendlyError(e)),
        data: (rows) {
          final maxV = rows
              .map((r) => r.count.toDouble())
              .fold<double>(0, (a, b) => a > b ? a : b);
          final primary = Theme.of(context).colorScheme.primary;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'New enrollments / month',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              if (rows.isEmpty)
                const Text('No enrollments yet')
              else
                SizedBox(
                  height: 160,
                  child: LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: maxV == 0 ? 1 : maxV * 1.2,
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < rows.length; i++)
                              FlSpot(i.toDouble(), rows[i].count.toDouble()),
                          ],
                          isCurved: true,
                          color: primary,
                          barWidth: 3,
                          belowBarData: BarAreaData(
                            show: true,
                            color: primary.withValues(alpha: 0.12),
                          ),
                        ),
                      ],
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        horizontalInterval: maxV == 0 ? 1 : maxV / 4,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: Theme.of(context).dividerColor,
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
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: 1,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i < 0 || i >= rows.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  DateFormat.MMM().format(rows[i].monthStart),
                                  style:
                                      Theme.of(context).textTheme.labelSmall,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (spots) => spots.map((s) {
                            final r = rows[s.x.toInt()];
                            return LineTooltipItem(
                              '${DateFormat.yMMM().format(r.monthStart)}\n'
                              '${r.count} new',
                              const TextStyle(color: Colors.white),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BatchUtilizationCard extends ConsumerWidget {
  const _BatchUtilizationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(batchUtilizationProvider);
    return AppCard(
      child: async.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text(friendlyError(e)),
        data: (rows) {
          if (rows.isEmpty) return const Text('No active batches');
          final scheme = Theme.of(context).colorScheme;
          final semantics = AppSemanticColors.of(context);
          final sorted = [...rows]..sort((a, b) {
              final ua = a.utilization ?? 0;
              final ub = b.utilization ?? 0;
              return ub.compareTo(ua);
            });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Batch utilization',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              for (final r in sorted.take(10))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            r.capacity == null
                                ? '${r.enrolled}'
                                : '${r.enrolled}/${r.capacity}'
                                    '  ${((r.utilization ?? 0) * 100).toStringAsFixed(0)}%',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      if (r.capacity != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: LinearProgressIndicator(
                            value: (r.utilization ?? 0.0).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: scheme.surfaceContainerHighest,
                            color: _utilColor(semantics, r.utilization ?? 0.0),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SportBreakdownCard extends ConsumerWidget {
  const _SportBreakdownCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sportBreakdownProvider);
    return AppCard(
      child: async.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text(friendlyError(e)),
        data: (rows) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('By sport', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              if (rows.isEmpty)
                const Text(
                  'Add sports under Settings → Sports to see this breakdown.',
                )
              else ...[
                Row(
                  children: [
                    const Expanded(flex: 4, child: Text('')),
                    Expanded(
                      child: Text(
                        'Students',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Batches',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Coaches',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const Divider(height: AppSpacing.md),
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            r.sportName,
                            style: r.sportId == null
                                ? Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontStyle: FontStyle.italic)
                                : null,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${r.studentCount}',
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${r.batchCount}',
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${r.coachCount}',
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LeadFunnelCard extends ConsumerWidget {
  const _LeadFunnelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leadFunnelProvider);
    return AppCard(
      child: async.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text(friendlyError(e)),
        data: (rows) {
          final byStatus = <String, int>{};
          for (final r in rows) {
            byStatus[r.status] = (byStatus[r.status] ?? 0) + r.count;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lead funnel', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              if (byStatus.isEmpty)
                const Text('No leads yet')
              else
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final e in byStatus.entries)
                      AppBadge(
                        text: '${e.key}: ${e.value}',
                        tone: _funnelTone(e.key),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

AppBadgeTone _funnelTone(String status) {
  switch (status) {
    case 'converted':
      return AppBadgeTone.success;
    case 'lost':
      return AppBadgeTone.danger;
    case 'trial':
      return AppBadgeTone.warning;
    case 'new':
    case 'contacted':
    case 'interested':
      return AppBadgeTone.info;
  }
  return AppBadgeTone.neutral;
}

Color _utilColor(AppSemanticColors s, double util) {
  if (util >= 0.75) return s.success;
  if (util >= 0.4) return s.warning;
  return s.danger;
}

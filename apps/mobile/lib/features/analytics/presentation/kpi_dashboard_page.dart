import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/analytics/data/analytics_providers.dart';
import 'package:playhub/features/analytics/data/growth_metrics.dart';
import 'package:playhub/features/analytics/data/sport_breakdown.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// KPI dashboard backed by the analytics_* materialized views (refreshed
/// hourly by the analytics-aggregations Edge Function). Shape adapts to
/// the calling user's role so each role sees what's relevant to them.
class KpiDashboardPage extends ConsumerWidget {
  const KpiDashboardPage({super.key});

  void _refreshAll(WidgetRef ref) {
    ref
      ..invalidate(revenueByMonthProvider)
      ..invalidate(enrollmentByMonthProvider)
      ..invalidate(leadFunnelProvider)
      ..invalidate(batchUtilizationProvider)
      ..invalidate(collectionSummaryProvider)
      ..invalidate(sportBreakdownProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final role = profile?.role ?? '';
    final isOwner = role == 'academy_owner';
    final isAdmin = role == 'academy_admin' || role == 'center_admin';
    final isHeadCoach = role == 'head_coach';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => _refreshAll(ref),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Navy analytics hero. Owners/admins get a top-level collected /
            // outstanding stat strip pulled from the existing collection
            // summary provider; everyone else gets a simple titled hero.
            _AnalyticsHero(
              showFinanceStats: isOwner || isAdmin,
              onBack: () => Navigator.of(context).maybePop(),
              onRefresh: () => _refreshAll(ref),
            ),
            // Body overlaps the hero band upward, v1-style.
            Transform.translate(
              offset: const Offset(0, -AppSpacing.xl),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isOwner || isAdmin) ...const [
                      _GrowthMetricsSection(),
                      SizedBox(height: AppSpacing.lg),
                      _CollectionSummarySection(),
                      SizedBox(height: AppSpacing.lg),
                      _RevenueTrendCard(),
                      SizedBox(height: AppSpacing.lg),
                    ],
                    if (isOwner || isAdmin || isHeadCoach) ...const [
                      _EnrollmentTrendCard(),
                      SizedBox(height: AppSpacing.lg),
                      _SportBreakdownCard(),
                      SizedBox(height: AppSpacing.lg),
                      _BatchUtilizationCard(),
                      SizedBox(height: AppSpacing.lg),
                    ],
                    if (isOwner || isAdmin) const _LeadFunnelCard(),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Archetype-A analytics hero: a navy gradient band with a back + refresh
/// circle button, the page title, the hourly-refresh freshness cue, and — for
/// finance-visible roles — a translucent stat strip with collected /
/// outstanding / overdue figures from [collectionSummaryProvider]. Falls back
/// to a simple titled hero while loading, on error, or for coaching roles.
class _AnalyticsHero extends ConsumerWidget {
  const _AnalyticsHero({
    required this.showFinanceStats,
    required this.onBack,
    required this.onRefresh,
  });

  final bool showFinanceStats;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary =
        showFinanceStats ? ref.watch(collectionSummaryProvider) : null;
    final stats = summary?.valueOrNull;
    final money = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹');

    return AppGradientHeader(
      colors: AppPalette.navyGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppCircleIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: onBack,
              ),
              const Spacer(),
              AppCircleIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onTap: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Analytics',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: AppType.heavy,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 15,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'Figures refresh hourly · pull down to reload',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
          if (stats != null) ...[
            const SizedBox(height: AppSpacing.lg),
            AppHeroStatRow(
              stats: [
                (money.format(stats.collectedTotal), 'Collected'),
                (money.format(stats.outstandingAmount), 'Outstanding'),
                ('${stats.overdueCount}', 'Overdue'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Thin wrapper that gives every chart/breakdown section the same anatomy:
/// a labeled [AppSectionHeader] (with a leading brand-tinted glyph) inside an
/// [AppCard], with consistent async states (loading / error+retry / empty
/// handled by the caller's [child]).
class _ChartSection extends StatelessWidget {
  const _ChartSection({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(title: title, icon: icon),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// Owner/admin growth overview — students, coaches and centers (live total vs
/// 30 days ago) plus revenue (latest month vs prior). A 2×2 grid of
/// [AppStatTile]; each shows the current figure with a colored growth-% pill.
/// Backed by [growthMetricsProvider] (computed client-side, no extra query).
class _GrowthMetricsSection extends ConsumerWidget {
  const _GrowthMetricsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(growthMetricsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'Growth',
          icon: Icons.trending_up_rounded,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (m == null)
          const AppCard(child: AppLoading())
        else ...[
          Row(
            children: [
              Expanded(
                child: _GrowthTile(
                  icon: Icons.groups_rounded,
                  label: 'Students',
                  stat: m.students,
                  color: AppPalette.brandPrimary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _GrowthTile(
                  icon: Icons.sports_rounded,
                  label: 'Coaches',
                  stat: m.coaches,
                  color: AppPalette.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _GrowthTile(
                  icon: Icons.apartment_rounded,
                  label: 'Centers',
                  stat: m.centers,
                  color: AppPalette.categorySwatch[4],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _GrowthTile(
                  icon: Icons.payments_rounded,
                  label: 'Revenue',
                  stat: m.revenue,
                  color: AppPalette.success,
                  money: true,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One growth tile. Shows the current figure as the headline and the growth-%
/// (vs the stat's baseline) as a colored up/down pill via [AppStatTile].
class _GrowthTile extends StatelessWidget {
  const _GrowthTile({
    required this.icon,
    required this.label,
    required this.stat,
    required this.color,
    this.money = false,
  });

  final IconData icon;
  final String label;

  /// Null while a metric has no data yet (e.g. revenue before the first month).
  final GrowthStat? stat;
  final Color color;

  /// Format the value as compact INR currency rather than a plain count.
  final bool money;

  @override
  Widget build(BuildContext context) {
    final s = stat;
    if (s == null) {
      return AppStatTile(
        icon: icon,
        label: label,
        value: money ? '₹0' : '0',
        color: color,
      );
    }
    final f = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹');
    return AppStatTile(
      icon: icon,
      label: label,
      value: money ? f.format(s.current) : s.current.toInt().toString(),
      trend: _trendLabel(s, money: money),
      trendUp: s.isUp,
      color: color,
    );
  }

  static String _trendLabel(GrowthStat s, {required bool money}) {
    final pct = s.pct;
    if (pct == null) {
      // No baseline to grow from. Counts show the absolute gain; revenue "New".
      if (s.delta == 0) return '0%';
      if (money) return 'New';
      final d = s.delta.toInt();
      return d > 0 ? '+$d' : '$d';
    }
    final sign = pct >= 0 ? '+' : '';
    final dp = (pct != 0 && pct.abs() < 10) ? 1 : 0;
    return '$sign${pct.toStringAsFixed(dp)}%';
  }
}

class _CollectionSummarySection extends ConsumerWidget {
  const _CollectionSummarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(collectionSummaryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'Collection summary',
          icon: Icons.account_balance_wallet_rounded,
        ),
        const SizedBox(height: AppSpacing.sm),
        async.when(
          loading: () => const AppCard(child: AppLoading()),
          error: (e, _) => AppCard(
            child: AppErrorView(
              message: friendlyError(e),
              onRetry: () => ref.invalidate(collectionSummaryProvider),
            ),
          ),
          data: (s) {
            if (s == null) {
              return const AppCard(
                child: AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No invoice data yet',
                  subtitle: 'Collection figures appear once invoices exist.',
                ),
              );
            }
            final semantics = AppSemanticColors.of(context);
            final money =
                NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹');
            // Two-up responsive grid: tiles wrap to full width if the row
            // can't fit two side by side at a large text scale.
            return _StatGrid(
              tiles: [
                AppStatTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Collected',
                  value: money.format(s.collectedTotal),
                  color: semantics.success,
                ),
                AppStatTile(
                  icon: Icons.hourglass_bottom_outlined,
                  label: 'Outstanding (${s.outstandingCount})',
                  value: money.format(s.outstandingAmount),
                  color: semantics.warning,
                ),
                AppStatTile(
                  icon: Icons.warning_amber_outlined,
                  label: 'Overdue invoices',
                  value: '${s.overdueCount}',
                  color: semantics.danger,
                ),
                AppStatTile(
                  icon: Icons.check_circle_outline,
                  label: 'Paid invoices',
                  value: '${s.paidCount}',
                  color: semantics.success,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Lays out KPI tiles two-per-row, falling back to a single column on very
/// narrow widths so a long currency value never overflows the tile.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoUp = constraints.maxWidth >= 320;
        final columns = twoUp ? 2 : 1;
        const spacing = AppSpacing.md;
        final tileWidth = twoUp
            ? (constraints.maxWidth - spacing * (columns - 1)) / columns
            : constraints.maxWidth;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles)
              SizedBox(width: tileWidth, child: tile),
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
    final theme = Theme.of(context);
    return _ChartSection(
      title: 'Revenue trend',
      icon: Icons.bar_chart_rounded,
      child: async.when(
        loading: () => const SizedBox(height: 180, child: AppLoading()),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(revenueByMonthProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const AppEmptyState(
              icon: Icons.bar_chart_outlined,
              title: 'No revenue yet',
              subtitle: 'Collected payments will chart here by month.',
            );
          }
          final maxV = rows
              .map((r) => r.collected)
              .fold<double>(0, (a, b) => a > b ? a : b);
          final f =
              NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹');
          final primary = theme.colorScheme.primary;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Collected over the last ${rows.length} months',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
                                top: Radius.circular(AppRadius.sm),
                              ),
                            ),
                          ],
                        ),
                    ],
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: maxV == 0 ? 1 : maxV / 4,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: theme.dividerColor,
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
                            style: theme.textTheme.labelSmall,
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
                              padding: const EdgeInsets.only(top: AppSpacing.xs),
                              child: Text(
                                DateFormat.MMM().format(rows[i].monthStart),
                                style: theme.textTheme.labelSmall,
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
                style: theme.textTheme.bodySmall,
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
    final theme = Theme.of(context);
    return _ChartSection(
      title: 'New enrollments / month',
      icon: Icons.show_chart_rounded,
      child: async.when(
        loading: () => const SizedBox(height: 160, child: AppLoading()),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(enrollmentByMonthProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const AppEmptyState(
              icon: Icons.show_chart_outlined,
              title: 'No enrollments yet',
              subtitle: 'New joiners will trend here once students enroll.',
            );
          }
          final maxV = rows
              .map((r) => r.count.toDouble())
              .fold<double>(0, (a, b) => a > b ? a : b);
          final primary = theme.colorScheme.primary;
          return SizedBox(
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
                    color: theme.dividerColor,
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
                        style: theme.textTheme.labelSmall,
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
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            DateFormat.MMM().format(rows[i].monthStart),
                            style: theme.textTheme.labelSmall,
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
    final theme = Theme.of(context);
    const icon = Icons.donut_large_rounded;
    return async.when(
      loading: () => const _ChartSection(
        title: 'Batch utilization',
        icon: icon,
        child: AppLoading(),
      ),
      error: (e, _) => _ChartSection(
        title: 'Batch utilization',
        icon: icon,
        child: AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(batchUtilizationProvider),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const _ChartSection(
            title: 'Batch utilization',
            icon: icon,
            child: AppEmptyState(
              icon: Icons.groups_outlined,
              title: 'No active batches',
              subtitle: 'Fill rates appear once batches have capacity.',
            ),
          );
        }
        final scheme = theme.colorScheme;
        final semantics = AppSemanticColors.of(context);
        final sorted = [...rows]..sort((a, b) {
            final ua = a.utilization ?? 0;
            final ub = b.utilization ?? 0;
            return ub.compareTo(ua);
          });
        final shown = sorted.take(10).toList(growable: false);
        final hiddenCount = sorted.length - shown.length;
        return _ChartSection(
          title: 'Batch utilization',
          icon: icon,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  // Capacity-less batches can't show a fill rate — render the
                  // name + headcount only, no meter.
                  child: r.capacity == null
                      ? Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: AppType.semibold,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              '${r.enrolled}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        )
                      : AppLabeledProgress(
                          label: r.name,
                          value: (r.utilization ?? 0.0).clamp(0.0, 1.0),
                          color: _utilColor(semantics, r.utilization ?? 0.0),
                          trailing: '${r.enrolled}/${r.capacity}'
                              '  ${((r.utilization ?? 0) * 100).toStringAsFixed(0)}%',
                        ),
                ),
              if (hiddenCount > 0)
                Text(
                  'Showing top 10 of ${sorted.length} batches by fill rate.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SportBreakdownCard extends ConsumerWidget {
  const _SportBreakdownCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sportBreakdownProvider);
    final theme = Theme.of(context);
    const icon = Icons.sports_soccer_rounded;
    return async.when(
      loading: () => const _ChartSection(
        title: 'By sport',
        icon: icon,
        child: AppLoading(),
      ),
      error: (e, _) => _ChartSection(
        title: 'By sport',
        icon: icon,
        child: AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(sportBreakdownProvider),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const _ChartSection(
            title: 'By sport',
            icon: icon,
            child: AppEmptyState(
              icon: Icons.sports_outlined,
              title: 'No sports configured',
              subtitle: 'Add sports under Settings → Sports to see this '
                  'breakdown.',
            ),
          );
        }
        final scheme = theme.colorScheme;
        return _ChartSection(
          title: 'By sport',
          icon: icon,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: the sport name flexes, the three metric columns
              // are fixed-width so a long name can never squeeze them.
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    const Expanded(child: SizedBox.shrink()),
                    _SportMetricCell(
                      label: 'Students',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    _SportMetricCell(
                      label: 'Batches',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    _SportMetricCell(
                      label: 'Coaches',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: AppSpacing.md),
              for (final r in rows)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      // Deterministic per-sport accent dot; the unassigned
                      // bucket (null sport) reads as a muted, hollow marker.
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: AppSpacing.sm),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: r.sportId == null
                              ? scheme.outlineVariant
                              : colorFromName(r.sportName),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          r.sportName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: r.sportId == null
                              ? theme.textTheme.bodyMedium
                                  ?.copyWith(fontStyle: FontStyle.italic)
                              : null,
                        ),
                      ),
                      _SportMetricCell(label: '${r.studentCount}'),
                      _SportMetricCell(label: '${r.batchCount}'),
                      _SportMetricCell(label: '${r.coachCount}'),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Fixed-width, right-aligned numeric column for the sport breakdown table so
/// long sport names flex into the [Expanded] name column instead of pushing
/// the metric columns off-screen.
class _SportMetricCell extends StatelessWidget {
  const _SportMetricCell({required this.label, this.style});

  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Text(
        label,
        textAlign: TextAlign.right,
        style: style,
      ),
    );
  }
}

class _LeadFunnelCard extends ConsumerWidget {
  const _LeadFunnelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leadFunnelProvider);
    const icon = Icons.filter_alt_rounded;
    return async.when(
      loading: () => const _ChartSection(
        title: 'Lead funnel',
        icon: icon,
        child: AppLoading(),
      ),
      error: (e, _) => _ChartSection(
        title: 'Lead funnel',
        icon: icon,
        child: AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(leadFunnelProvider),
        ),
      ),
      data: (rows) {
        final byStatus = <String, int>{};
        for (final r in rows) {
          byStatus[r.status] = (byStatus[r.status] ?? 0) + r.count;
        }
        if (byStatus.isEmpty) {
          return const _ChartSection(
            title: 'Lead funnel',
            icon: icon,
            child: AppEmptyState(
              icon: Icons.filter_alt_outlined,
              title: 'No leads yet',
              subtitle: 'Captured leads progress through stages here.',
            ),
          );
        }
        // Render the canonical pipeline order as a funnel (widest = busiest
        // stage). Any status not in the canonical order is appended after.
        final ordered = <String>[
          for (final s in _funnelOrder)
            if (byStatus.containsKey(s)) s,
          for (final s in byStatus.keys)
            if (!_funnelOrder.contains(s)) s,
        ];
        final maxCount = byStatus.values
            .fold<int>(0, (a, b) => a > b ? a : b)
            .clamp(1, 1 << 30);
        return _ChartSection(
          title: 'Lead funnel',
          icon: icon,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final status in ordered)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _FunnelStage(
                    status: status,
                    count: byStatus[status] ?? 0,
                    fraction: (byStatus[status] ?? 0) / maxCount,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One horizontal funnel bar: a label, a tone-tinted bar whose width scales to
/// the busiest stage, and the count. Reads as a funnel rather than a badge wrap.
class _FunnelStage extends StatelessWidget {
  const _FunnelStage({
    required this.status,
    required this.count,
    required this.fraction,
  });

  final String status;
  final int count;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = _funnelTone(status);
    final colors = _toneColors(context, tone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _funnelLabel(status),
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$count',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: AppType.semibold,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Stack(
            children: [
              Container(
                height: 10,
                color: scheme.surfaceContainerHighest,
              ),
              FractionallySizedBox(
                widthFactor: fraction.clamp(0.04, 1.0),
                child: Container(height: 10, color: colors.fg),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Canonical lead pipeline order, widest (top) to narrowest, with the lost
/// bucket parked at the bottom.
const _funnelOrder = <String>[
  'new',
  'contacted',
  'interested',
  'trial',
  'converted',
  'lost',
];

String _funnelLabel(String status) =>
    status.isEmpty ? status : status[0].toUpperCase() + status.substring(1);

({Color fg, Color bg}) _toneColors(BuildContext context, AppBadgeTone tone) {
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

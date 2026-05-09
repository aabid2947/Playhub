import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/features/analytics/data/analytics_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';

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
            onPressed: () {
              ref.invalidate(revenueByMonthProvider);
              ref.invalidate(enrollmentByMonthProvider);
              ref.invalidate(leadFunnelProvider);
              ref.invalidate(batchUtilizationProvider);
              ref.invalidate(collectionSummaryProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (isOwner || isAdmin) ...const [
            _CollectionSummaryCard(),
            SizedBox(height: 12),
            _RevenueTrendCard(),
            SizedBox(height: 12),
          ],
          if (isOwner || isAdmin || isHeadCoach) ...const [
            _EnrollmentTrendCard(),
            SizedBox(height: 12),
            _BatchUtilizationCard(),
            SizedBox(height: 12),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
          data: (s) {
            if (s == null) return const Text('No invoice data yet');
            final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Collection summary',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _Row(label: 'Collected total', value: f.format(s.collectedTotal)),
                _Row(
                    label: 'Outstanding',
                    value:
                        '${f.format(s.outstandingAmount)} (${s.outstandingCount})'),
                _Row(
                    label: 'Overdue invoices', value: '${s.overdueCount}'),
                _Row(label: 'Paid invoices', value: '${s.paidCount}'),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RevenueTrendCard extends ConsumerWidget {
  const _RevenueTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(revenueByMonthProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
          data: (rows) {
            if (rows.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Revenue (last 12 months)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('No revenue yet'),
                ],
              );
            }
            final maxV = rows
                .map((r) => r.collected)
                .fold<double>(0, (a, b) => a > b ? a : b);
            final f = NumberFormat.compactCurrency(
                locale: 'en_IN', symbol: '₹');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Revenue trend',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final r in rows) ...[
                        Expanded(
                          child: Tooltip(
                            message:
                                '${DateFormat.yMMM().format(r.monthStart)}: ${f.format(r.collected)}',
                            child: Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              height: maxV == 0
                                  ? 1
                                  : (r.collected / maxV) * 100 + 2,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Last month: ${f.format(rows.last.collected)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EnrollmentTrendCard extends ConsumerWidget {
  const _EnrollmentTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(enrollmentByMonthProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
          data: (rows) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('New enrollments / month',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  const Text('No enrollments yet')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in rows)
                        Chip(
                          label: Text(
                            '${DateFormat.MMM().format(r.monthStart)}: ${r.count}',
                          ),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BatchUtilizationCard extends ConsumerWidget {
  const _BatchUtilizationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(batchUtilizationProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
          data: (rows) {
            if (rows.isEmpty) return const Text('No active batches');
            final sorted = [...rows]..sort((a, b) {
                final ua = a.utilization ?? 0;
                final ub = b.utilization ?? 0;
                return ub.compareTo(ua);
              });
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Batch utilization',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final r in sorted.take(10))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(r.name)),
                        Text(
                          r.capacity == null
                              ? '${r.enrolled}'
                              : '${r.enrolled}/${r.capacity}'
                                  ' (${((r.utilization ?? 0) * 100).toStringAsFixed(0)}%)',
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LeadFunnelCard extends ConsumerWidget {
  const _LeadFunnelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leadFunnelProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: async.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Error: $e'),
          data: (rows) {
            final byStatus = <String, int>{};
            for (final r in rows) {
              byStatus[r.status] = (byStatus[r.status] ?? 0) + r.count;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lead funnel',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (byStatus.isEmpty)
                  const Text('No leads yet')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in byStatus.entries)
                        Chip(label: Text('${e.key}: ${e.value}')),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

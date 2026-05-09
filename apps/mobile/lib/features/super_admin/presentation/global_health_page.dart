import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';

/// System health + global revenue snapshot.
class GlobalHealthPage extends ConsumerWidget {
  const GlobalHealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpiAsync = ref.watch(globalKpiProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(allAcademiesProvider);
        ref.invalidate(globalKpiProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          kpiAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Error: $e'),
            data: (k) {
              final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Global revenue',
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(f.format(k.totalRevenue),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall),
                          const SizedBox(height: 4),
                          Text(
                              'Outstanding: ${f.format(k.outstandingAmount)}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Academies',
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          _kv('Active', '${k.academiesActive}'),
                          _kv('Trial', '${k.academiesTrial}'),
                          _kv('Paying (active)',
                              '${k.academiesPaying}'),
                          _kv('Past due', '${k.academiesPastDue}'),
                          _kv('Suspended', '${k.academiesSuspended}'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_done_outlined),
                      title: const Text('System health'),
                      subtitle: const Text(
                        'Edge Functions + cron deployed; full status board '
                        'lands in v1.1',
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(k)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

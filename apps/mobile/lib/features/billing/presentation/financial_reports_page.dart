import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/invoice.dart';

class FinancialReportsPage extends ConsumerWidget {
  const FinancialReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoicesProvider);
    return invoicesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (invoices) {
        final now = DateTime.now();
        final thirtyDays = now.subtract(const Duration(days: 30));
        var revenue30d = 0.0;
        var outstanding = 0.0;
        var overdueCount = 0;
        final byStatus = <InvoiceStatus, int>{};
        for (final i in invoices) {
          byStatus[i.status] = (byStatus[i.status] ?? 0) + 1;
          if (i.issuedAt.isAfter(thirtyDays)) {
            revenue30d += i.amountPaid;
          }
          outstanding += i.balance;
          if (i.status == InvoiceStatus.overdue) overdueCount++;
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _BigStat(
              label: 'Collected (last 30 days)',
              value: '₹${revenue30d.toStringAsFixed(0)}',
              color: Colors.green,
            ),
            const SizedBox(height: 12),
            _BigStat(
              label: 'Outstanding',
              value: '₹${outstanding.toStringAsFixed(0)}',
              color: outstanding > 0 ? Colors.orange : null,
            ),
            const SizedBox(height: 12),
            _BigStat(
              label: 'Overdue invoices',
              value: '$overdueCount',
              color: overdueCount > 0 ? Colors.red : null,
            ),
            const SizedBox(height: 16),
            Text('By status', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final s in InvoiceStatus.values)
                    ListTile(
                      title: Text(s.label),
                      trailing: Text(
                        '${byStatus[s] ?? 0}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat(
      {required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color?.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(color: color)),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

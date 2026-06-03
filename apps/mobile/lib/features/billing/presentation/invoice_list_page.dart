import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/invoice.dart';
import 'package:playhub/features/billing/presentation/invoice_detail_page.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/core/error_messages.dart';

class InvoiceListPage extends ConsumerWidget {
  const InvoiceListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoicesProvider);
    final filter = ref.watch(invoiceFilterProvider);
    final students =
        ref.watch(studentsProvider).valueOrNull ?? const <Student>[];
    final byId = {for (final s in students) s.id: s};

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      _StatusFilterChip(
                        label: 'All',
                        selected: filter.status == null,
                        onSelected: () => ref
                            .read(invoiceFilterProvider.notifier)
                            .state = const InvoiceFilter(),
                      ),
                      for (final s in InvoiceStatus.values)
                        _StatusFilterChip(
                          label: s.label,
                          selected: filter.status == s,
                          onSelected: () => ref
                              .read(invoiceFilterProvider.notifier)
                              .state = InvoiceFilter(status: s),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: invoicesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(friendlyError(e))),
              data: (invoices) {
                if (invoices.isEmpty) return const _EmptyState();
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(invoicesProvider),
                  child: ListView.separated(
                    itemCount: invoices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => _InvoiceTile(
                      invoice: invoices[i],
                      student: byId[invoices[i].studentId],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.student});
  final Invoice invoice;
  final Student? student;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(invoice.status);
    final due = invoice.dueDate.toIso8601String().substring(0, 10);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(_statusIcon(invoice.status), color: color, size: 18),
      ),
      title: Text(invoice.invoiceNumber),
      subtitle: Text(
        '${student?.fullName ?? 'unknown student'} · due $due',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('₹${invoice.amount.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.titleMedium),
          Text(
            invoice.status.label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                ),
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              InvoiceDetailPage(invoiceId: invoice.id),
        ),
      ),
    );
  }

  Color _statusColor(InvoiceStatus s) => switch (s) {
        InvoiceStatus.paid => Colors.green,
        InvoiceStatus.partial => Colors.orange,
        InvoiceStatus.overdue => Colors.red,
        InvoiceStatus.cancelled => Colors.grey,
        InvoiceStatus.draft => Colors.grey,
        InvoiceStatus.issued => Colors.blue,
      };

  IconData _statusIcon(InvoiceStatus s) => switch (s) {
        InvoiceStatus.paid => Icons.check,
        InvoiceStatus.partial => Icons.hourglass_bottom,
        InvoiceStatus.overdue => Icons.warning_amber_outlined,
        InvoiceStatus.cancelled => Icons.cancel_outlined,
        InvoiceStatus.draft => Icons.drafts_outlined,
        InvoiceStatus.issued => Icons.description_outlined,
      };
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_outlined, size: 48),
            const SizedBox(height: 12),
            Text('No invoices yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'Recurring invoices generate via cron when fees are assigned.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

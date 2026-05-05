import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/invoice.dart';
import 'package:playhub/features/billing/data/payment.dart';
import 'package:playhub/features/billing/presentation/record_payment_page.dart';
import 'package:playhub/features/billing/presentation/refund_form_page.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

final _invoiceProvider =
    FutureProvider.family<Invoice, String>((ref, id) async {
  final client = ref.read(supabaseClientProvider);
  final row =
      await client.from('invoices').select().eq('id', id).single();
  return Invoice.fromMap(row);
});

class InvoiceDetailPage extends ConsumerWidget {
  const InvoiceDetailPage({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(_invoiceProvider(invoiceId));
    return invoiceAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (invoice) => _Body(invoice: invoice),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(invoiceLineItemsProvider(invoice.id));
    final payments = ref.watch(paymentsForInvoiceProvider(invoice.id));
    final students =
        ref.watch(studentsProvider).valueOrNull ?? const <Student>[];
    Student? student;
    for (final s in students) {
      if (s.id == invoice.studentId) {
        student = s;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(invoice.invoiceNumber),
        actions: [
          IconButton(
            tooltip: 'Download receipt',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => _downloadReceipt(context, ref, invoice.id),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryCard(invoice: invoice, student: student),
          const SizedBox(height: 12),
          if (invoice.balance > 0) ...[
            _OutstandingActions(invoice: invoice),
            const SizedBox(height: 12),
          ],
          Text('Line items',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          lines.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (e, _) => Text('Error: $e'),
            data: (items) => Card(
              child: Column(
                children: [
                  for (final l in items)
                    ListTile(
                      title: Text(l.description),
                      subtitle: Text(l.kind),
                      trailing: Text(
                        '₹${l.totalAmount.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Payments',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          payments.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (e, _) => Text('Error: $e'),
            data: (list) {
              if (list.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No payments recorded yet.'),
                  ),
                );
              }
              return Card(
                child: Column(
                  children: [
                    for (final p in list) _PaymentTile(payment: p),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _downloadReceipt(
    BuildContext context,
    WidgetRef ref,
    String invoiceId,
  ) async {
    try {
      final url = await generateInvoiceReceipt(ref, invoiceId);
      if (!context.mounted) return;
      await launcher.launchUrl(
        Uri.parse(url),
        mode: launcher.LaunchMode.externalApplication,
      );
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Receipt failed: $e')),
        );
      }
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.invoice, required this.student});
  final Invoice invoice;
  final Student? student;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(student?.fullName ?? 'Unknown student',
                style: Theme.of(context).textTheme.titleLarge),
            if (student?.parentName != null)
              Text('Parent: ${student!.parentName}',
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                _Cell(label: 'Total', value: '₹${invoice.amount.toStringAsFixed(0)}'),
                const SizedBox(width: 12),
                _Cell(
                    label: 'Paid',
                    value: '₹${invoice.amountPaid.toStringAsFixed(0)}',
                    color: Colors.green),
                const SizedBox(width: 12),
                _Cell(
                    label: 'Balance',
                    value: '₹${invoice.balance.toStringAsFixed(0)}',
                    color: invoice.balance > 0 ? Colors.red : Colors.green),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Due ${invoice.dueDate.toIso8601String().substring(0, 10)}'
              ' · status: ${invoice.status.label}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: color)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _OutstandingActions extends ConsumerWidget {
  const _OutstandingActions({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Record manual payment'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => RecordPaymentPage(invoice: invoice),
                ),
              ),
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.link),
              label: const Text('Razorpay order'),
              onPressed: () => _createRazorpayOrder(context, ref, invoice.id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createRazorpayOrder(
    BuildContext context,
    WidgetRef ref,
    String invoiceId,
  ) async {
    try {
      final order = await createRazorpayOrder(ref, invoiceId);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Razorpay order created'),
          content: SelectableText(
            'order_id: ${order['order_id']}\n'
            'attempt: ${order['attempt_number']}/3\n'
            'amount: ₹${((order['amount_paise'] as num) / 100).toStringAsFixed(2)}\n'
            'key_id: ${order['key_id']}\n\n'
            'Share with parent or hand off to razorpay_flutter SDK.',
          ),
          actions: [
            TextButton(
              child: const Text('Copy order_id'),
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: order['order_id'] as String),
                );
                Navigator.of(ctx).pop();
              },
            ),
            TextButton(
              child: const Text('Close'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order failed: $e')),
        );
      }
    }
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});
  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final canRefund = payment.status == 'completed';
    return ListTile(
      leading: Icon(_methodIcon(payment.method)),
      title: Text(
        '₹${payment.amount.toStringAsFixed(0)} · ${payment.method.label}',
      ),
      subtitle: Text(
        '${payment.paidAt.toIso8601String().substring(0, 10)} · ${payment.status}',
      ),
      trailing: canRefund
          ? IconButton(
              tooltip: 'Refund',
              icon: const Icon(Icons.undo_outlined),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => RefundFormPage(payment: payment),
                ),
              ),
            )
          : null,
    );
  }

  IconData _methodIcon(PaymentMethod m) => switch (m) {
        PaymentMethod.razorpay => Icons.account_balance_wallet_outlined,
        PaymentMethod.cash => Icons.payments_outlined,
        PaymentMethod.cheque => Icons.receipt_outlined,
        PaymentMethod.bankTransfer => Icons.account_balance_outlined,
        PaymentMethod.upiManual => Icons.qr_code_outlined,
      };
}

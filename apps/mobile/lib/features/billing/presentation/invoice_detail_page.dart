import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/invoice.dart';
import 'package:playhub/features/billing/data/payment.dart';
import 'package:playhub/features/billing/presentation/record_payment_page.dart';
import 'package:playhub/features/billing/presentation/refund_form_page.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

final _invoiceProvider =
    FutureProvider.family<Invoice, String>((ref, id) async {
  final client = ref.read(supabaseClientProvider);
  final row = await client.from('invoices').select().eq('id', id).single();
  return Invoice.fromMap(row);
});

class InvoiceDetailPage extends ConsumerWidget {
  const InvoiceDetailPage({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(_invoiceProvider(invoiceId));
    return invoiceAsync.when(
      loading: () => const Scaffold(body: AppLoading()),
      error: (e, _) => Scaffold(
        body: AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(_invoiceProvider(invoiceId)),
        ),
      ),
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
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _SummaryCard(invoice: invoice, student: student),
          const SizedBox(height: AppSpacing.xl),
          const AppSectionHeader(title: 'Line items'),
          lines.when(
            loading: () => const AppSkeletonList(count: 3),
            error: (e, _) => AppErrorView(
              message: friendlyError(e),
              onRetry: () =>
                  ref.invalidate(invoiceLineItemsProvider(invoice.id)),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const AppCard(
                  child: Text('No line items on this invoice.'),
                );
              }
              return AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _LineItemTile(item: items[i]),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          const AppSectionHeader(title: 'Payments'),
          payments.when(
            loading: () => const AppSkeletonList(count: 2),
            error: (e, _) => AppErrorView(
              message: friendlyError(e),
              onRetry: () =>
                  ref.invalidate(paymentsForInvoiceProvider(invoice.id)),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const AppCard(
                  child: Text('No payments recorded yet.'),
                );
              }
              return AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _PaymentTile(payment: list[i]),
                    ],
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
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }
}

/// Balance-forward header: the outstanding balance is the headline; total and
/// paid are secondary facts. The primary "Record payment" action lives here
/// when there's anything still owed.
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.invoice, required this.student});
  final Invoice invoice;
  final Student? student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = AppSemanticColors.of(context);
    final hasBalance = invoice.balance > 0;
    final balanceColor = hasBalance ? semantics.danger : semantics.success;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student?.fullName ?? 'Unknown student',
                      style: theme.textTheme.titleLarge,
                    ),
                    if (student?.parentName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          'Parent: ${student!.parentName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppBadge(
                text: invoice.status.label,
                tone: _statusTone(invoice.status),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // Balance callout — the number that matters, full-width.
          Text(
            hasBalance ? 'Balance due' : 'Balance',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _inr(invoice.balance),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: balanceColor,
              fontWeight: AppType.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _Fact(
                  label: 'Total',
                  value: _inr(invoice.amount),
                ),
              ),
              Expanded(
                child: _Fact(
                  label: 'Paid',
                  value: _inr(invoice.amountPaid),
                  color: invoice.amountPaid > 0 ? semantics.success : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(
                Icons.event_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Due ${_date(invoice.dueDate)}'
                  '${_period(invoice)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (hasBalance) ...[
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Record payment'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => RecordPaymentPage(invoice: invoice),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.link),
                label: const Text('Create Razorpay order'),
                onPressed: () =>
                    _createRazorpayOrder(context, ref, invoice.id),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _period(Invoice invoice) {
    final start = invoice.periodStart;
    final end = invoice.periodEnd;
    if (start == null || end == null) return '';
    return ' · ${_date(start)} – ${_date(end)}';
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
            'amount: ${_inr((order['amount_paise'] as num) / 100)}\n'
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
        AppSnackbar.error(context, friendlyError(e));
      }
    }
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(color: color),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _LineItemTile extends StatelessWidget {
  const _LineItemTile({required this.item});
  final InvoiceLineItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppListTile(
      title: Text(item.description),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Align(
          alignment: Alignment.centerLeft,
          child: AppBadge(
            text: _kindLabel(item.kind),
            tone: _kindTone(item.kind),
          ),
        ),
      ),
      trailing: Text(
        _inr(item.totalAmount),
        style: theme.textTheme.titleMedium,
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});
  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRefund = payment.status == 'completed';
    return AppListTile(
      leading: Icon(_methodIcon(payment.method)),
      title: Text('${_inr(payment.amount)} · ${payment.method.label}'),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          children: [
            Text(
              _date(payment.paidAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppBadge(
              text: _paymentStatusLabel(payment.status),
              tone: _paymentStatusTone(payment.status),
            ),
          ],
        ),
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

// ---- formatting + status mapping helpers ----------------------------------

String _inr(num value) => '₹${value.toStringAsFixed(0)}';

String _date(DateTime d) => d.toIso8601String().substring(0, 10);

AppBadgeTone _statusTone(InvoiceStatus status) => switch (status) {
      InvoiceStatus.paid => AppBadgeTone.success,
      InvoiceStatus.partial => AppBadgeTone.warning,
      InvoiceStatus.overdue => AppBadgeTone.danger,
      InvoiceStatus.cancelled => AppBadgeTone.neutral,
      InvoiceStatus.draft => AppBadgeTone.neutral,
      InvoiceStatus.issued => AppBadgeTone.info,
    };

String _kindLabel(String kind) => switch (kind) {
      'base' => 'Base fee',
      'tax' => 'Tax',
      'late_fee' => 'Late fee',
      'discount' => 'Discount',
      'adjustment' => 'Adjustment',
      _ => kind,
    };

AppBadgeTone _kindTone(String kind) => switch (kind) {
      'tax' => AppBadgeTone.info,
      'late_fee' => AppBadgeTone.warning,
      'discount' => AppBadgeTone.success,
      'adjustment' => AppBadgeTone.brand,
      _ => AppBadgeTone.neutral,
    };

String _paymentStatusLabel(String status) =>
    status.isEmpty ? status : '${status[0].toUpperCase()}${status.substring(1)}';

AppBadgeTone _paymentStatusTone(String status) => switch (status) {
      'completed' => AppBadgeTone.success,
      'pending' => AppBadgeTone.warning,
      'failed' => AppBadgeTone.danger,
      'refunded' => AppBadgeTone.neutral,
      _ => AppBadgeTone.neutral,
    };

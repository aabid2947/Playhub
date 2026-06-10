import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
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
        body: SafeArea(
          child: AppErrorView(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(_invoiceProvider(invoiceId)),
          ),
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
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Navy finance hero — invoice # + balance headline + status, with
          // back and download-receipt circle buttons.
          _Hero(
            invoice: invoice,
            student: student,
            onBack: () => Navigator.of(context).pop(),
            onDownload: () => _downloadReceipt(context, ref, invoice.id),
          ),
          // Body overlaps the hero band upward, v1-style.
          Transform.translate(
            offset: const Offset(0, -AppSpacing.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SummaryCard(invoice: invoice),
                  const SizedBox(height: AppSpacing.lg),
                  const AppSectionHeader(
                    title: 'Line items',
                    icon: Icons.list_alt_outlined,
                  ),
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
                  const SizedBox(height: AppSpacing.lg),
                  const AppSectionHeader(
                    title: 'Payments',
                    icon: Icons.receipt_long_outlined,
                  ),
                  payments.when(
                    loading: () => const AppSkeletonList(count: 2),
                    error: (e, _) => AppErrorView(
                      message: friendlyError(e),
                      onRetry: () => ref
                          .invalidate(paymentsForInvoiceProvider(invoice.id)),
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
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
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

/// Archetype-E finance hero: a navy gradient band leading with the outstanding
/// balance (the number that matters), the student/invoice identity, a status
/// badge, and translucent hero chips for total · paid. Carries the back button
/// and the download-receipt action.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.invoice,
    required this.student,
    required this.onBack,
    required this.onDownload,
  });

  final Invoice invoice;
  final Student? student;
  final VoidCallback onBack;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBalance = invoice.balance > 0;
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
                icon: Icons.file_download_outlined,
                tooltip: 'Download receipt',
                onTap: onDownload,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.invoiceNumber,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: AppType.semibold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      student?.fullName ?? 'Unknown student',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: AppType.heavy,
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
          Text(
            hasBalance ? 'Balance due' : 'Balance',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _inr(invoice.balance),
            style: theme.textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontWeight: AppType.heavy,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppGlassChip(
                'Total ${_inr(invoice.amount)}',
                icon: Icons.receipt_outlined,
              ),
              AppGlassChip(
                'Paid ${_inr(invoice.amountPaid)}',
                icon: Icons.check_circle_outline,
              ),
              AppGlassChip(
                'Due ${_date(invoice.dueDate)}',
                icon: Icons.event_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The invoice's facts plus the primary money actions. The balance headline
/// lives in the hero; here we surface period, parent, and the outstanding
/// actions (Record payment + Create Razorpay order) when anything is owed.
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = AppSemanticColors.of(context);
    final hasBalance = invoice.balance > 0;
    final students =
        ref.watch(studentsProvider).valueOrNull ?? const <Student>[];
    Student? student;
    for (final s in students) {
      if (s.id == invoice.studentId) {
        student = s;
        break;
      }
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              Expanded(
                child: _Fact(
                  label: 'Balance',
                  value: _inr(invoice.balance),
                  color: hasBalance ? semantics.danger : semantics.success,
                ),
              ),
            ],
          ),
          if (student?.parentName != null) ...[
            const SizedBox(height: AppSpacing.md),
            _MetaRow(
              icon: Icons.person_outline,
              label: 'Parent',
              value: student!.parentName,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _MetaRow(
            icon: Icons.event_outlined,
            label: 'Due',
            value: '${_date(invoice.dueDate)}${_period(invoice)}',
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
          if (!hasBalance)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: semantics.success,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Fully settled',
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
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: AppType.bold,
          ),
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

/// One labeled fact line: leading icon · fixed-width label · value.
class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: muted),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: AppType.semibold,
            ),
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
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: AppType.bold,
        ),
      ),
    );
  }
}

class _PaymentTile extends ConsumerWidget {
  const _PaymentTile({required this.payment});
  final Payment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Refunds are admin-only (manageRefunds). A center_admin can record payments
    // but not refund them, so don't surface the action RLS would reject.
    final canRefund = payment.status == 'completed' &&
        ref.watch(capabilitiesProvider).manageRefunds;
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

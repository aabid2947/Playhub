import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/invoice.dart';
import 'package:playhub/features/billing/data/payment.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class RecordPaymentPage extends ConsumerStatefulWidget {
  const RecordPaymentPage({required this.invoice, super.key});

  final Invoice invoice;

  @override
  ConsumerState<RecordPaymentPage> createState() => _RecordPaymentPageState();
}

class _RecordPaymentPageState extends ConsumerState<RecordPaymentPage> {
  late final _amount = TextEditingController(
    text: widget.invoice.balance.toStringAsFixed(2),
  );
  final _notes = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Keep the "remaining after this payment" line live as the user types.
    _amount.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amount
      ..removeListener(_onAmountChanged)
      ..dispose();
    _notes.dispose();
    super.dispose();
  }

  void _onAmountChanged() => setState(() {});

  double? get _parsedAmount {
    final raw = double.tryParse(_amount.text.trim());
    if (raw == null || raw <= 0) return null;
    return raw;
  }

  String _money(double v) => '₹${v.toStringAsFixed(2)}';

  void _payFullBalance() {
    _amount.text = widget.invoice.balance.toStringAsFixed(2);
    _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
  }

  /// Step 1 — validate, then open the confirmation step.
  Future<void> _review() async {
    final amount = _parsedAmount;
    if (amount == null) {
      AppSnackbar.error(context, 'Enter a valid amount.');
      return;
    }
    if (amount > widget.invoice.balance) {
      AppSnackbar.error(context, 'Amount exceeds invoice balance.');
      return;
    }
    final confirmed = await _confirm(amount);
    if (confirmed ?? false) await _save(amount);
  }

  /// Step 2 — confirmation step before the irreversible money write.
  Future<bool?> _confirm(double amount) {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Record this payment? This updates the invoice balance and '
              "can't be undone from here.",
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            _ConfirmRow(label: 'Invoice', value: widget.invoice.invoiceNumber),
            _ConfirmRow(label: 'Method', value: _method.label),
            _ConfirmRow(
              label: 'Amount',
              value: _money(amount),
              emphasize: true,
            ),
            _ConfirmRow(
              label: 'Remaining after',
              value: _money(widget.invoice.balance - amount),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Record ${_money(amount)}'),
          ),
        ],
      ),
    );
  }

  /// Step 3 — the write. `recordManualPayment` wiring is unchanged.
  Future<void> _save(double amount) async {
    setState(() => _busy = true);
    try {
      await recordManualPayment(
        ref,
        invoice: widget.invoice,
        amount: amount,
        method: _method,
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      await _showSuccessSummary(amount);
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Step 4 — success summary before returning to the invoice.
  Future<void> _showSuccessSummary(double amount) {
    final theme = Theme.of(context);
    final semantics = AppSemanticColors.of(context);
    final remaining = widget.invoice.balance - amount;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.check_circle_outline, color: semantics.success),
        title: const Text('Payment recorded'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_money(amount)} recorded against '
              '${widget.invoice.invoiceNumber} via ${_method.label}.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            _ConfirmRow(
              label: 'Remaining balance',
              value: _money(remaining),
              emphasize: true,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  ({String label, AppBadgeTone tone}) _statusBadge() {
    switch (widget.invoice.status) {
      case InvoiceStatus.paid:
        return (label: widget.invoice.status.label, tone: AppBadgeTone.success);
      case InvoiceStatus.overdue:
        return (label: widget.invoice.status.label, tone: AppBadgeTone.danger);
      case InvoiceStatus.partial:
        return (label: widget.invoice.status.label, tone: AppBadgeTone.warning);
      case InvoiceStatus.issued:
        return (label: widget.invoice.status.label, tone: AppBadgeTone.info);
      case InvoiceStatus.draft:
      case InvoiceStatus.cancelled:
        return (
          label: widget.invoice.status.label,
          tone: AppBadgeTone.neutral
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final invoice = widget.invoice;
    final amount = _parsedAmount;
    final badge = _statusBadge();
    // Reserved-space remaining line: always rendered so the layout never jumps.
    final remaining = amount == null
        ? null
        : (invoice.balance - amount).clamp(0.0, double.infinity);

    return Scaffold(
      // NAVY finance hero (pushed page) with its own back button.
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          AppGradientHeader(
            colors: AppPalette.navyGradient,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppCircleIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Back',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Record payment',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: AppType.heavy,
                        ),
                      ),
                    ),
                    AppBadge(text: badge.label, tone: badge.tone),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    AppGlassChip(invoice.invoiceNumber, icon: Icons.receipt_long),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppHeroStatRow(
                  stats: [
                    (_money(invoice.balance), 'Balance due'),
                    (_money(invoice.amount), 'Total'),
                    (_money(invoice.amountPaid), 'Paid'),
                  ],
                ),
              ],
            ),
          ),

          // Body overlaps the hero band upward, v1-style.
          Transform.translate(
            offset: const Offset(0, -AppSpacing.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- Amount ----------------------------------------------
                  AppSectionHeader(
                    title: 'Amount',
                    icon: Icons.payments_outlined,
                    trailing: TextButton(
                      onPressed: _busy ? null : _payFullBalance,
                      child: const Text('Pay full balance'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppFormField(
                    controller: _amount,
                    label: 'Amount (INR ₹)',
                    hint: '0.00',
                    enabled: !_busy,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // Reserved space: live "remaining after this payment" cue.
                  SizedBox(
                    height: 20,
                    child: amount == null
                        ? null
                        : Text(
                            'Remaining after this payment: '
                            '${_money(remaining!)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // ---- Method & notes --------------------------------------
                  const AppSectionHeader(
                    title: 'Payment details',
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppDropdownField<PaymentMethod>(
                    label: 'Method',
                    value: _method,
                    items: PaymentMethod.values
                        .where((m) => m != PaymentMethod.razorpay)
                        .map(
                          (m) =>
                              DropdownMenuItem(value: m, child: Text(m.label)),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (v) =>
                            setState(() => _method = v ?? PaymentMethod.cash),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Online (Razorpay) payments are recorded automatically — '
                    'only manual methods are entered here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppFormField(
                    controller: _notes,
                    label: 'Notes (optional)',
                    hint: 'Cheque #, transaction ID, …',
                    enabled: !_busy,
                    maxLines: 2,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ],
      ),
      // ---- Pinned primary action: opens the confirmation step ------------
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.lg),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _review,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Review payment'),
          ),
        ),
      ),
    );
  }
}

/// Label/value row used in the confirmation and success summaries.
class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = emphasize
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: AppType.semibold)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/payment.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class RefundFormPage extends ConsumerStatefulWidget {
  const RefundFormPage({required this.payment, super.key});

  final Payment payment;

  @override
  ConsumerState<RefundFormPage> createState() => _RefundFormPageState();
}

class _RefundFormPageState extends ConsumerState<RefundFormPage> {
  late final _amount = TextEditingController(
    text: widget.payment.amount.toStringAsFixed(2),
  );
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Keep the "partial vs full" cue live as the user edits the amount.
    _amount.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amount
      ..removeListener(_onAmountChanged)
      ..dispose();
    _reason.dispose();
    super.dispose();
  }

  void _onAmountChanged() => setState(() {});

  bool get _isRazorpay => widget.payment.method == PaymentMethod.razorpay;

  double? get _parsedAmount {
    final raw = double.tryParse(_amount.text.trim());
    if (raw == null || raw <= 0) return null;
    return raw;
  }

  bool get _isPartial {
    final amount = _parsedAmount;
    return amount != null && amount < widget.payment.amount;
  }

  String _money(double v) => '₹${v.toStringAsFixed(2)}';

  void _refundFullAmount() {
    _amount.text = widget.payment.amount.toStringAsFixed(2);
    _amount.selection = TextSelection.collapsed(offset: _amount.text.length);
  }

  /// Step 1 — validate, then open the confirmation step.
  Future<void> _review() async {
    final amount = _parsedAmount;
    if (amount == null) {
      AppSnackbar.error(context, 'Enter a valid amount.');
      return;
    }
    if (amount > widget.payment.amount) {
      AppSnackbar.error(context, 'Refund cannot exceed the payment.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      AppSnackbar.error(context, 'A reason is required for the audit trail.');
      return;
    }
    final confirmed = await _confirm(amount);
    if (confirmed ?? false) await _save(amount);
  }

  /// Step 2 — confirmation step before the irreversible money write.
  Future<bool?> _confirm(double amount) {
    final theme = Theme.of(context);
    final partial = amount < widget.payment.amount;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm refund'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isRazorpay
                  ? 'This initiates a Razorpay refund to the payer. '
                      "It can't be undone from here."
                  : 'This records a manual refund and updates the invoice. '
                      "It can't be undone from here.",
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            _ConfirmRow(label: 'Method', value: widget.payment.method.label),
            _ConfirmRow(
              label: 'Original payment',
              value: _money(widget.payment.amount),
            ),
            _ConfirmRow(
              label: partial ? 'Refund (partial)' : 'Refund (full)',
              value: _money(amount),
              emphasize: true,
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
            child: Text('Refund ${_money(amount)}'),
          ),
        ],
      ),
    );
  }

  /// Step 3 — the write. `requestRefund` wiring is unchanged.
  Future<void> _save(double amount) async {
    setState(() => _busy = true);
    try {
      await requestRefund(
        ref,
        paymentId: widget.payment.id,
        amount: amount,
        reason: _reason.text.trim(),
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

  /// Step 4 — success summary before returning to the payment.
  Future<void> _showSuccessSummary(double amount) {
    final theme = Theme.of(context);
    final semantics = AppSemanticColors.of(context);
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.check_circle_outline, color: semantics.success),
        title: const Text('Refund recorded'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isRazorpay
                  ? '${_money(amount)} refund initiated via Razorpay. '
                      'The payer is credited once Razorpay settles it.'
                  : '${_money(amount)} manual refund recorded. Hand the cash '
                      'back / void the cheque physically.',
              style: theme.textTheme.bodyMedium,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final payment = widget.payment;

    return Scaffold(
      appBar: AppBar(title: const Text('Refund payment')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // ---- Header: what you're refunding against ----------------------
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Original payment',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    AppBadge(
                      text: payment.method.label,
                      tone: _isRazorpay
                          ? AppBadgeTone.brand
                          : AppBadgeTone.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _money(payment.amount),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: AppType.bold,
                  ),
                ),
                if (payment.razorpayPaymentId != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Razorpay ${payment.razorpayPaymentId}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ---- How this refund is processed -------------------------------
          _RefundPathNote(isRazorpay: _isRazorpay),
          const SizedBox(height: AppSpacing.xl),

          // ---- Amount -----------------------------------------------------
          AppSectionHeader(
            title: 'Refund amount',
            trailing: TextButton(
              onPressed: _busy ? null : _refundFullAmount,
              child: const Text('Refund full amount'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppFormField(
            controller: _amount,
            label: 'Amount (INR ₹)',
            hint: '0.00',
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Reserved space: live "partial vs full" cue so layout never jumps.
          SizedBox(
            height: 20,
            child: _parsedAmount == null
                ? null
                : Text(
                    _isPartial
                        ? 'Partial refund of '
                            '${_money(payment.amount)} payment.'
                        : 'Full refund of the original payment.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ---- Reason -----------------------------------------------------
          const AppSectionHeader(title: 'Reason'),
          const SizedBox(height: AppSpacing.sm),
          AppFormField(
            controller: _reason,
            label: 'Reason *',
            hint: 'Required for the audit trail',
            enabled: !_busy,
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Primary action: opens the confirmation step ----------------
          FilledButton(
            onPressed: _busy ? null : _review,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Review refund'),
          ),
        ],
      ),
    );
  }
}

/// Info-toned note explaining how the refund will be processed.
class _RefundPathNote extends StatelessWidget {
  const _RefundPathNote({required this.isRazorpay});

  final bool isRazorpay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = AppSemanticColors.of(context).info;
    final text = isRazorpay
        ? 'A Razorpay refund call is initiated — the payer is credited once '
            'Razorpay settles it.'
        : 'Manual refund: marked processed immediately. Hand the cash back / '
            'void the cheque physically.';
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
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

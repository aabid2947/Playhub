import 'package:flutter/material.dart';
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
      text: widget.payment.amount.toStringAsFixed(2));
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      AppSnackbar.error(context, 'Enter a valid amount.');
      return;
    }
    if (amount > widget.payment.amount) {
      AppSnackbar.error(context, 'Refund cannot exceed payment.');
      return;
    }
    setState(() => _busy = true);
    try {
      await requestRefund(
        ref,
        paymentId: widget.payment.id,
        amount: amount,
        reason: _reason.text.trim(),
      );
      if (!mounted) return;
      AppSnackbar.success(context, 'Refund recorded.');
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRazorpay = widget.payment.method == PaymentMethod.razorpay;
    return Scaffold(
      appBar: AppBar(title: const Text('Refund payment')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Original payment',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    Text(
                      '₹${widget.payment.amount.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: AppType.semibold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.payment.method.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.md),
                _RefundNote(isRazorpay: isRazorpay),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const AppSectionHeader(title: 'Refund details'),
          const SizedBox(height: AppSpacing.sm),
          AppFormField(
            controller: _amount,
            label: 'Refund amount (₹)',
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: AppSpacing.md),
          AppFormField(
            controller: _reason,
            label: 'Reason',
            hint: 'Required for audit trail',
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Process refund'),
          ),
        ],
      ),
    );
  }
}

/// Info-toned note explaining how the refund will be processed.
class _RefundNote extends StatelessWidget {
  const _RefundNote({required this.isRazorpay});

  final bool isRazorpay;

  @override
  Widget build(BuildContext context) {
    final info = AppSemanticColors.of(context).info;
    final text = isRazorpay
        ? 'A Razorpay refund call will be initiated.'
        : 'Manual refund: marked processed immediately. Hand the cash '
            'back / void the cheque physically.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: info),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      ],
    );
  }
}

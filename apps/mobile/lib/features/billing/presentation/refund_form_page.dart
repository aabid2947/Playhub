import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/payment.dart';
import 'package:playhub/core/error_messages.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }
    if (amount > widget.payment.amount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Refund cannot exceed payment')),
      );
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Refund recorded.')),
        );
        Navigator.of(context).pop();
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
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
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₹${widget.payment.amount.toStringAsFixed(2)} · ${widget.payment.method.label}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  if (isRazorpay)
                    const Text(
                      'A Razorpay refund call will be initiated.',
                    )
                  else
                    const Text(
                      'Manual refund: marked processed immediately. '
                      'Hand the cash back / void the cheque physically.',
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Refund amount (₹)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Required for audit trail',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
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

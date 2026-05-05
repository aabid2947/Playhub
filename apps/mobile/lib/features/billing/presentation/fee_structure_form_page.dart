import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/fee_structure.dart';

class FeeStructureFormPage extends ConsumerStatefulWidget {
  const FeeStructureFormPage({super.key, this.existing});

  final FeeStructure? existing;

  @override
  ConsumerState<FeeStructureFormPage> createState() =>
      _FeeStructureFormPageState();
}

class _FeeStructureFormPageState
    extends ConsumerState<FeeStructureFormPage> {
  late final _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _sport =
      TextEditingController(text: widget.existing?.sport ?? '');
  late final _base = TextEditingController(
      text: widget.existing?.baseAmount.toStringAsFixed(2) ?? '');
  late final _tax = TextEditingController(
      text: widget.existing?.taxPct.toStringAsFixed(2) ?? '0');
  late final _lateFlat = TextEditingController(
      text: widget.existing?.lateFeeFlat?.toStringAsFixed(2) ?? '');
  late final _latePct = TextEditingController(
      text: widget.existing?.lateFeePct?.toStringAsFixed(2) ?? '');
  late final _grace = TextEditingController(
      text: (widget.existing?.lateFeeGraceDays ?? 5).toString());

  late FeeType _type = widget.existing?.type ?? FeeType.monthly;
  late String _latePolicy = widget.existing?.lateFeePolicy ?? 'one_time';
  late bool _isActive = widget.existing?.isActive ?? true;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  bool get isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _sport.dispose();
    _base.dispose();
    _tax.dispose();
    _lateFlat.dispose();
    _latePct.dispose();
    _grace.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final patch = <String, dynamic>{
        'name': _name.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'sport': _sport.text.trim().isEmpty ? null : _sport.text.trim(),
        'type': _type.dbValue,
        'base_amount': double.parse(_base.text.trim()),
        'tax_pct': double.tryParse(_tax.text.trim()) ?? 0,
        'late_fee_flat': _lateFlat.text.trim().isEmpty
            ? null
            : double.tryParse(_lateFlat.text.trim()),
        'late_fee_pct': _latePct.text.trim().isEmpty
            ? null
            : double.tryParse(_latePct.text.trim()),
        'late_fee_grace_days':
            int.tryParse(_grace.text.trim()) ?? 5,
        'late_fee_policy': _latePolicy,
        'is_active': _isActive,
      };
      if (isEdit) {
        await updateFeeStructure(ref, widget.existing!.id, patch);
      } else {
        await createFeeStructure(ref, patch);
      }
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit fee' : 'New fee')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<FeeType>(
              initialValue: _type,
              items: FeeType.values
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? FeeType.monthly),
              decoration: const InputDecoration(
                labelText: 'Frequency',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sport,
              decoration: const InputDecoration(
                labelText: 'Sport (optional)',
                hintText: 'cricket / football / …',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _base,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Base amount (₹) *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v?.trim() ?? '');
                      if (n == null || n < 0) return 'Required';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _tax,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Tax %',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Late fee',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _latePolicy,
              items: const [
                DropdownMenuItem(value: 'none', child: Text('No late fee')),
                DropdownMenuItem(
                    value: 'one_time', child: Text('One-time fee')),
                DropdownMenuItem(
                    value: 'daily', child: Text('Per-day after grace')),
              ],
              onChanged: (v) =>
                  setState(() => _latePolicy = v ?? 'one_time'),
              decoration: const InputDecoration(
                labelText: 'Policy',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _lateFlat,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Flat ₹ / period',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _latePct,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Or % of base',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _grace,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Grace days',
                hintText: 'Days after due date before fee applies',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title: const Text('Active'),
              subtitle: const Text(
                'When off, recurring invoices stop generating.',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isEdit ? 'Save changes' : 'Create fee'),
            ),
            if (isEdit) ...[
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 12),
              Text('Bulk-assign',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Assign this fee to every active enrollment in a batch. '
                'Already-assigned students are skipped.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Apply to batch…'),
                onPressed: () =>
                    _showBatchPicker(context, widget.existing!.id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showBatchPicker(
    BuildContext context,
    String feeStructureId,
  ) async {
    final batches = ref.read(batchesProvider).valueOrNull ?? const <Batch>[];
    final active = batches.where((b) => b.isActive).toList();
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active batches.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<Batch>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: active.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            if (i == 0) {
              return const ListTile(
                dense: true,
                title: Text('Pick a batch'),
              );
            }
            final b = active[i - 1];
            return ListTile(
              title: Text(b.name),
              subtitle: Text(
                '${b.schedule.summary} · ${b.enrolledCount} enrolled',
              ),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () => Navigator.of(ctx).pop(b),
            );
          },
        ),
      ),
    );
    if (picked == null) return;
    try {
      final n = await assignFeeToBatch(
        ref,
        feeStructureId: feeStructureId,
        batchId: picked.id,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? 'No new assignments — all students already had this fee.'
                : 'Assigned to $n student${n == 1 ? '' : 's'}.',
          ),
        ),
      );
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bulk-assign failed: $e')),
        );
      }
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/fee_structure.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
  late String? _sportId = widget.existing?.sportId;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  bool get isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
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
        'sport_id': _sportId,
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
      if (!mounted) return;
      AppSnackbar.success(context, isEdit ? 'Fee updated.' : 'Fee created.');
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
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
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const AppSectionHeader(title: 'Fee details'),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _name,
              label: 'Name *',
              hint: 'e.g. Monthly coaching fee',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<FeeType>(
              label: 'Frequency',
              value: _type,
              items: FeeType.values
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? FeeType.monthly),
            ),
            const SizedBox(height: AppSpacing.md),
            SportPicker(
              value: _sportId,
              onChanged: (v) => setState(() => _sportId = v),
              label: 'Sport (optional)',
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _base,
                    label: 'Base amount (₹) *',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    validator: (v) {
                      final n = double.tryParse(v?.trim() ?? '');
                      if (n == null || n < 0) return 'Required';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppFormField(
                    controller: _tax,
                    label: 'Tax %',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'Late fee'),
            const SizedBox(height: AppSpacing.sm),
            AppDropdownField<String>(
              label: 'Policy',
              value: _latePolicy,
              items: const [
                DropdownMenuItem(value: 'none', child: Text('No late fee')),
                DropdownMenuItem(
                    value: 'one_time', child: Text('One-time fee')),
                DropdownMenuItem(
                    value: 'daily', child: Text('Per-day after grace')),
              ],
              onChanged: (v) => setState(() => _latePolicy = v ?? 'one_time'),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppFormField(
                    controller: _lateFlat,
                    label: 'Flat ₹ / period',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppFormField(
                    controller: _latePct,
                    label: 'Or % of base',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _grace,
              label: 'Grace days',
              hint: 'Days after due date before fee applies',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppSectionHeader(title: 'Status'),
            const SizedBox(height: AppSpacing.xs),
            AppCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                title: const Text('Active'),
                subtitle: const Text(
                  'When off, recurring invoices stop generating.',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isEdit ? 'Save changes' : 'Create fee'),
            ),
          ],
        ),
      ),
    );
  }
}

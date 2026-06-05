import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/discount.dart';
import 'package:playhub/features/billing/data/discount_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class DiscountStructureFormPage extends ConsumerStatefulWidget {
  const DiscountStructureFormPage({super.key, this.existing});

  final DiscountStructure? existing;

  @override
  ConsumerState<DiscountStructureFormPage> createState() =>
      _DiscountStructureFormPageState();
}

class _DiscountStructureFormPageState
    extends ConsumerState<DiscountStructureFormPage> {
  late final _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _value = TextEditingController(
      text: widget.existing?.value.toStringAsFixed(2) ?? '');

  late DiscountType _type =
      widget.existing?.type ?? DiscountType.percentage;
  late bool _isActive = widget.existing?.isActive ?? true;
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  bool get isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _value.dispose();
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
        'type': _type.dbValue,
        'value': double.parse(_value.text.trim()),
        'is_active': _isActive,
      };
      if (isEdit) {
        await updateDiscountStructure(ref, widget.existing!.id, patch);
      } else {
        await createDiscountStructure(ref, patch);
      }
      if (!mounted) return;
      AppSnackbar.success(
          context, isEdit ? 'Discount updated.' : 'Discount created.');
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPct = _type == DiscountType.percentage;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit discount' : 'New discount')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const AppSectionHeader(title: 'Discount details'),
            const SizedBox(height: AppSpacing.sm),
            AppFormField(
              controller: _name,
              label: 'Name *',
              hint: 'Sibling, Scholarship, First-month promo…',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _description,
              label: 'Description (optional)',
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<DiscountType>(
              label: 'Type',
              value: _type,
              items: DiscountType.values
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _type = v ?? DiscountType.percentage),
            ),
            const SizedBox(height: AppSpacing.md),
            AppFormField(
              controller: _value,
              label: isPct ? 'Percentage (%) *' : 'Flat amount (₹) *',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                if (n == null || n < 0) return 'Required';
                if (isPct && n > 100) return 'Max 100';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isPct
                  ? 'Applied to base_amount of each invoice (excludes tax).'
                  : 'Flat ₹ subtracted from each invoice.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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
                  'When off, this discount is no longer applied to '
                  'new invoices.',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isEdit ? 'Save changes' : 'Create discount'),
            ),
          ],
        ),
      ),
    );
  }
}

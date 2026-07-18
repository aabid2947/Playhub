import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/discount.dart';
import 'package:playhub/features/billing/data/discount_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Discount structure create/edit form — v1 "Sports-Light", archetype D (form,
/// pushed). A plain [AppBar] tops a [Form] → padded [ListView] of
/// [AppSectionHeader]-titled [AppCard] groups (details · type & value ·
/// stacking explainer · status), closed by a full-width [FilledButton] that
/// shows a spinner while saving. Presentation only — the save path, providers,
/// and `ref.invalidate` after the write are untouched; the create/edit entry
/// point is gated on `Capabilities.manageFinance` by the calling list page.
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
            // ---- Details ----------------------------------------------------
            const AppSectionHeader(title: 'Details'),
            const SizedBox(height: AppSpacing.xs),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormField(
                    controller: _name,
                    label: 'Name *',
                    hint: 'Sibling, Scholarship, First-month promo…',
                    enabled: !_busy,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppFormField(
                    controller: _description,
                    label: 'Description (optional)',
                    hint: 'Shown when this discount is assigned',
                    enabled: !_busy,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            // ---- Type & value ----------------------------------------------
            const AppSectionHeader(title: 'Discount type & value'),
            const SizedBox(height: AppSpacing.xs),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TypeSelector(
                    value: _type,
                    enabled: !_busy,
                    onChanged: (t) => setState(() => _type = t),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppFormField(
                    controller: _value,
                    label: isPct ? 'Percentage (%) *' : 'Flat amount (₹) *',
                    hint: isPct ? 'e.g. 10' : 'e.g. 500',
                    prefixIcon: Icon(
                      isPct
                          ? Icons.percent_outlined
                          : Icons.currency_rupee_outlined,
                    ),
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    validator: (v) {
                      final n = double.tryParse(v?.trim() ?? '');
                      if (n == null || n < 0) return 'Required';
                      if (isPct && n > 100) return 'Max 100';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _TypeHelp(isPercentage: isPct),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            // ---- Stacking ---------------------------------------------------
            const AppSectionHeader(title: 'How it stacks'),
            const SizedBox(height: AppSpacing.xs),
            const _StackingHelpCard(),
            const SizedBox(height: AppSpacing.xl),
            // ---- Status -----------------------------------------------------
            const AppSectionHeader(title: 'Status'),
            const SizedBox(height: AppSpacing.xs),
            AppCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                value: _isActive,
                onChanged:
                    _busy ? null : (v) => setState(() => _isActive = v),
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
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Save changes' : 'Create discount'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented Percentage/Flat picker. Sits above the value field and visibly
/// reshapes it (label, prefix, suffix, validation) so the unit a coach is
/// entering is never ambiguous.
class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  final DiscountType value;
  final ValueChanged<DiscountType> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Type',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: AppType.semibold,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<DiscountType>(
            segments: const [
              ButtonSegment(
                value: DiscountType.percentage,
                label: Text('Percentage'),
                icon: Icon(Icons.percent_outlined),
              ),
              ButtonSegment(
                value: DiscountType.flat,
                label: Text('Flat ₹'),
                icon: Icon(Icons.currency_rupee_outlined),
              ),
            ],
            selected: {value},
            onSelectionChanged: enabled
                ? (sel) => onChanged(sel.first)
                : null,
          ),
        ),
      ],
    );
  }
}

/// Inline explainer for what the entered value applies to — swaps with the
/// selected type so the percentage/flat distinction is spelled out.
class _TypeHelp extends StatelessWidget {
  const _TypeHelp({required this.isPercentage});

  final bool isPercentage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 16,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            isPercentage
                ? 'A percentage off the base amount of each invoice '
                    '(before tax).'
                : 'A flat ₹ amount subtracted from each invoice.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Explains how this discount combines with others once it is assigned —
/// stacking is decided per-assignment (the `stack_with_batch` flag), so this
/// card is purely informational and writes nothing on the structure itself.
class _StackingHelpCard extends StatelessWidget {
  const _StackingHelpCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.layers_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'This just defines the discount. Whether it stacks on top of a '
              'batch discount is chosen when you assign it to a student. '
              'Percentage discounts apply to the pre-tax base; flat discounts '
              'come straight off the invoice total.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

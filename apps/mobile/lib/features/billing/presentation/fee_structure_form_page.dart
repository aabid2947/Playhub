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

class _FeeStructureFormPageState extends ConsumerState<FeeStructureFormPage> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
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

  /// Fields that feed the live invoice preview — rebuild it on every keystroke.
  @override
  void initState() {
    super.initState();
    _base.addListener(_onPreviewInput);
    _tax.addListener(_onPreviewInput);
  }

  void _onPreviewInput() => setState(() {});

  @override
  void dispose() {
    _base.removeListener(_onPreviewInput);
    _tax.removeListener(_onPreviewInput);
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
        'late_fee_grace_days': int.tryParse(_grace.text.trim()) ?? 5,
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
            // ---- Fee --------------------------------------------------------
            const AppSectionHeader(title: 'Fee'),
            const SizedBox(height: AppSpacing.xs),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppFormField(
                    controller: _name,
                    label: 'Name *',
                    hint: 'e.g. Monthly coaching fee',
                    enabled: !_busy,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppFormField(
                    controller: _description,
                    label: 'Description (optional)',
                    hint: 'Shown on the invoice line item',
                    enabled: !_busy,
                    maxLines: 2,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppDropdownField<FeeType>(
                    label: 'Frequency',
                    value: _type,
                    items: FeeType.values
                        .map((t) =>
                            DropdownMenuItem(value: t, child: Text(t.label)))
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (v) =>
                            setState(() => _type = v ?? FeeType.monthly),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SportPicker(
                    value: _sportId,
                    onChanged: (v) => setState(() => _sportId = v),
                    label: 'Sport (optional)',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _PairedFields(
                    first: AppFormField(
                      controller: _base,
                      label: 'Base amount (₹) *',
                      hint: '0.00',
                      enabled: !_busy,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      validator: (v) {
                        final n = double.tryParse(v?.trim() ?? '');
                        if (n == null || n < 0) return 'Required';
                        return null;
                      },
                    ),
                    second: AppFormField(
                      controller: _tax,
                      label: 'Tax %',
                      hint: '0',
                      enabled: !_busy,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // ---- Invoice preview -------------------------------------------
            const AppSectionHeader(title: 'Invoice preview'),
            const SizedBox(height: AppSpacing.xs),
            _InvoicePreviewCard(
              name: _name.text.trim(),
              baseText: _base.text.trim(),
              taxText: _tax.text.trim(),
            ),
            const SizedBox(height: AppSpacing.xl),
            // ---- Late fee ---------------------------------------------------
            const AppSectionHeader(title: 'Late fee'),
            const SizedBox(height: AppSpacing.xs),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppDropdownField<String>(
                    label: 'Policy',
                    value: _latePolicy,
                    items: const [
                      DropdownMenuItem(
                          value: 'none', child: Text('No late fee')),
                      DropdownMenuItem(
                          value: 'one_time', child: Text('One-time fee')),
                      DropdownMenuItem(
                          value: 'daily', child: Text('Per-day after grace')),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) =>
                            setState(() => _latePolicy = v ?? 'one_time'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _PolicyHelp(policy: _latePolicy),
                  if (_latePolicy != 'none') ...[
                    const SizedBox(height: AppSpacing.md),
                    _PairedFields(
                      first: AppFormField(
                        controller: _lateFlat,
                        label: 'Flat ₹ / period',
                        hint: '0.00',
                        enabled: !_busy,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                      second: AppFormField(
                        controller: _latePct,
                        label: 'Or % of base',
                        hint: '0',
                        enabled: !_busy,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppFormField(
                      controller: _grace,
                      label: 'Grace days',
                      hint: 'Days after due date before the fee applies',
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            // ---- Status -----------------------------------------------------
            const AppSectionHeader(title: 'Status'),
            const SizedBox(height: AppSpacing.xs),
            AppCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                value: _isActive,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _isActive = v),
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Save changes' : 'Create fee'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lays out two fields side-by-side on roomy widths and stacks them on narrow
/// ones, so numeric inputs (base+tax, flat+%) never crush to unusable widths.
class _PairedFields extends StatelessWidget {
  const _PairedFields({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppBreakpoints.phone / 2) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              first,
              const SizedBox(height: AppSpacing.md),
              second,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

/// Short inline explainer for the selected late-fee policy.
class _PolicyHelp extends StatelessWidget {
  const _PolicyHelp({required this.policy});

  final String policy;

  String get _text {
    switch (policy) {
      case 'one_time':
        return 'Charged once when an invoice stays unpaid past the grace '
            'period.';
      case 'daily':
        return 'Accrues for each day the invoice remains unpaid after the '
            'grace period.';
      case 'none':
      default:
        return 'No late fee is added — invoices never accrue a penalty.';
    }
  }

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
            _text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// A live worked example of how this fee renders on an invoice — a base line,
/// an optional tax line, and the total the student is billed (INR-marked).
class _InvoicePreviewCard extends StatelessWidget {
  const _InvoicePreviewCard({
    required this.name,
    required this.baseText,
    required this.taxText,
  });

  final String name;
  final String baseText;
  final String taxText;

  String _money(double v) => '₹${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final base = double.tryParse(baseText);
    if (base == null || base < 0) {
      return AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Enter a base amount to preview the invoice line.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final taxPct = double.tryParse(taxText) ?? 0;
    final taxAmount = base * taxPct / 100;
    final total = base + taxAmount;
    final lineLabel = name.isEmpty ? 'Fee' : name;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PreviewRow(label: lineLabel, value: _money(base)),
          if (taxPct > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            _PreviewRow(
              label: 'Tax (${taxPct.toStringAsFixed(taxPct % 1 == 0 ? 0 : 2)}%)',
              value: _money(taxAmount),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Divider(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total billed',
                style: theme.textTheme.titleMedium,
              ),
              Text(
                _money(total),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

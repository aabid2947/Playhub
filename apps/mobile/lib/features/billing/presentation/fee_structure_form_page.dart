import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/fee_structure.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class FeeStructureFormPage extends ConsumerStatefulWidget {
  const FeeStructureFormPage({
    super.key,
    this.existing,
    /// Pre-seed the per-day calculator with the batch's days/week when
    /// navigating here from a batch detail page.
    this.prefilledDaysPerWeek,
    /// Tag the new fee to this batch when coming from a batch detail page, so
    /// "New fee" there creates a price for THAT batch in one step.
    this.prefilledBatchId,
  });

  final FeeStructure? existing;
  final int? prefilledDaysPerWeek;
  final String? prefilledBatchId;

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

  // Per-day pricing fields
  late bool _perDayMode = widget.existing?.pricePerDay != null;
  late final _perDay = TextEditingController(
      text: widget.existing?.pricePerDay?.toStringAsFixed(2) ?? '');
  late final _daysPerWeek = TextEditingController(
      text: (widget.existing?.daysPerWeek ??
              widget.prefilledDaysPerWeek ??
              5)
          .toString());

  late FeeType _type = widget.existing?.type ?? FeeType.monthly;
  late String _latePolicy = widget.existing?.lateFeePolicy ?? 'one_time';
  late bool _isActive = widget.existing?.isActive ?? true;
  late String? _sportId = widget.existing?.sportId;
  // Optional scope tags. A fee tagged to a batch is a price for THAT batch;
  // untagged fees stay academy-wide templates. Assignment (who actually gets
  // billed) is still batch_fee_assignments / student fee assignments — this
  // narrows what's offered and what the list shows.
  late String? _batchId = widget.existing?.batchId ?? widget.prefilledBatchId;

  final _formKey = GlobalKey<FormState>();
  bool _busy = false;

  bool get isEdit => widget.existing != null;

  /// All inputs that feed the live invoice preview or per-day calculator.
  @override
  void initState() {
    super.initState();
    _base.addListener(_onPreviewInput);
    _tax.addListener(_onPreviewInput);
    _perDay.addListener(_onPerDayInput);
    _daysPerWeek.addListener(_onPerDayInput);
  }

  void _onPreviewInput() => setState(() {});

  void _onPerDayInput() {
    if (!_perDayMode) return;
    final computed = _computeBase();
    if (computed != null) {
      _base.text = computed.toStringAsFixed(2);
    }
    setState(() {});
  }

  /// Returns the calculated base amount for the current fee type, or null if
  /// the per-day inputs are incomplete.
  double? _computeBase() {
    final ppd = double.tryParse(_perDay.text.trim());
    final dpw = int.tryParse(_daysPerWeek.text.trim());
    if (ppd == null || ppd <= 0 || dpw == null || dpw < 1 || dpw > 7) {
      return null;
    }
    // Weeks per billing period
    const weeksPerYear = 52.0;
    switch (_type) {
      case FeeType.weekly:
        return ppd * dpw;
      case FeeType.monthly:
        return ppd * dpw * (weeksPerYear / 12);
      case FeeType.quarterly:
        return ppd * dpw * (weeksPerYear / 4);
      case FeeType.annual:
        return ppd * dpw * weeksPerYear;
      case FeeType.oneTime:
        // Per-day doesn't map to a one-time fee — return null so the user
        // keeps whatever they typed in the base-amount field.
        return null;
    }
  }

  @override
  void dispose() {
    _base.removeListener(_onPreviewInput);
    _tax.removeListener(_onPreviewInput);
    _perDay.removeListener(_onPerDayInput);
    _daysPerWeek.removeListener(_onPerDayInput);
    _name.dispose();
    _description.dispose();
    _base.dispose();
    _tax.dispose();
    _lateFlat.dispose();
    _latePct.dispose();
    _grace.dispose();
    _perDay.dispose();
    _daysPerWeek.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final ppd = _perDayMode
          ? double.tryParse(_perDay.text.trim())
          : null;
      final dpw = _perDayMode
          ? int.tryParse(_daysPerWeek.text.trim())
          : null;
      final patch = <String, dynamic>{
        'name': _name.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'sport_id': _sportId,
        'batch_id': _batchId,
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
        'price_per_day': ppd,
        'days_per_week': (ppd != null) ? dpw : null,
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
                        : (v) {
                            setState(() => _type = v ?? FeeType.monthly);
                            _onPerDayInput();
                          },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SportPicker(
                    value: _sportId,
                    // Changing the sport can strand a batch from the old sport,
                    // so clear it (same rule as the batch/student forms). The
                    // equality guard matters: the dropdown fires onChanged even
                    // when the same item is re-picked, which would otherwise
                    // wipe the batch tag of anyone tidying up the sport field.
                    onChanged: (v) => setState(() {
                      if (v == _sportId) return;
                      _sportId = v;
                      _batchId = null;
                    }),
                    label: 'Sport (optional)',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _BatchPicker(
                    value: _batchId,
                    sportId: _sportId,
                    enabled: !_busy,
                    onChanged: (batch) => setState(() {
                      _batchId = batch?.id;
                      // Tagging a batch implies its sport — fill it in so the
                      // fee reads consistently in the list and pickers.
                      if (batch?.sportId != null) _sportId = batch!.sportId;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            // ---- Per-day pricing --------------------------------------------
            AppSectionHeader(
              title: 'Per-day pricing',
              trailing: Switch(
                value: _perDayMode,
                onChanged: _busy
                    ? null
                    : (on) {
                        setState(() => _perDayMode = on);
                        if (on) _onPerDayInput();
                      },
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_perDayMode) ...[
              _PerDayCard(
                perDayCtrl: _perDay,
                daysPerWeekCtrl: _daysPerWeek,
                feeType: _type,
                busy: _busy,
                computed: _computeBase(),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            // ---- Base amount (auto-filled when per-day mode is on) ----------
            const AppSectionHeader(title: 'Amount'),
            const SizedBox(height: AppSpacing.xs),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PairedFields(
                    first: AppFormField(
                      controller: _base,
                      label: _perDayMode
                          ? 'Calculated amount (₹) *'
                          : 'Base amount (₹) *',
                      hint: '0.00',
                      // Editable even in per-day mode so the owner can
                      // round off or override the calculated figure.
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
            const SizedBox(height: AppSpacing.xl),
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

/// Per-day pricing calculator card. Shows price/day + days/week inputs and
/// a live breakdown of what the fee works out to per week and per billing
/// period. The [computed] value is derived by the parent and written into
/// the base-amount field automatically.
class _PerDayCard extends StatelessWidget {
  const _PerDayCard({
    required this.perDayCtrl,
    required this.daysPerWeekCtrl,
    required this.feeType,
    required this.busy,
    required this.computed,
  });

  final TextEditingController perDayCtrl;
  final TextEditingController daysPerWeekCtrl;
  final FeeType feeType;
  final bool busy;
  final double? computed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ppd = double.tryParse(perDayCtrl.text.trim());
    final dpw = int.tryParse(daysPerWeekCtrl.text.trim());
    final hasInputs = ppd != null && ppd > 0 && dpw != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PairedFields(
            first: AppFormField(
              controller: perDayCtrl,
              label: 'Price per day (₹) *',
              hint: '0.00',
              enabled: !busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            second: AppFormField(
              controller: daysPerWeekCtrl,
              label: 'Days per week *',
              hint: '5',
              enabled: !busy,
              keyboardType: TextInputType.number,
            ),
          ),
          if (hasInputs && feeType != FeeType.oneTime) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            // Weekly breakdown (always shown)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Weekly  (₹${ppd!.toStringAsFixed(0)} × $dpw days)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '₹${(ppd * dpw!).toStringAsFixed(0)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            if (computed != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _periodLabel(feeType),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    '₹${computed!.toStringAsFixed(0)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    _formulaHint(feeType),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (feeType == FeeType.oneTime && hasInputs) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Per-day pricing does not auto-calculate for one-time '
                    'fees — enter the base amount manually below.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _periodLabel(FeeType type) {
    switch (type) {
      case FeeType.weekly:
        return 'Weekly  (price × days)';
      case FeeType.monthly:
        return 'Monthly  (× 52 ÷ 12 weeks)';
      case FeeType.quarterly:
        return 'Quarterly  (× 13 weeks)';
      case FeeType.annual:
        return 'Annual  (× 52 weeks)';
      case FeeType.oneTime:
        return '';
    }
  }

  static String _formulaHint(FeeType type) {
    switch (type) {
      case FeeType.weekly:
        return 'price/day × days/week';
      case FeeType.monthly:
        return 'price/day × days/week × 4.33 avg weeks/month';
      case FeeType.quarterly:
        return 'price/day × days/week × 13 weeks';
      case FeeType.annual:
        return 'price/day × days/week × 52 weeks';
      case FeeType.oneTime:
        return '';
    }
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

/// Optional "this price is for one batch" picker.
///
/// Scoped to the chosen sport when one is set (a batch from another sport can't
/// be the target of a sport-tagged fee), and falls back to "— any batch —" when
/// the stored value isn't in the current options — an archived batch, or a sport
/// change — instead of tripping DropdownButtonFormField's value-in-items assert.
class _BatchPicker extends ConsumerWidget {
  const _BatchPicker({
    required this.value,
    required this.sportId,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final String? sportId;
  final bool enabled;

  /// Passes the whole batch (not just its id) so the caller can adopt its sport.
  final ValueChanged<Batch?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batchesAsync = ref.watch(batchesProvider);
    final all = batchesAsync.valueOrNull ?? const <Batch>[];
    // A sport-tagged fee only offers that sport's batches; batches with no
    // sport stay available either way (same NULL-sport relaxation used
    // elsewhere for batch scoping).
    final options = sportId == null
        ? all
        : all.where((b) => b.sportId == null || b.sportId == sportId).toList();
    final safeValue =
        options.any((b) => b.id == value) ? value : null;

    return AppDropdownField<String?>(
      label: 'Batch (optional)',
      value: safeValue,
      hint: batchesAsync.isLoading ? 'Loading batches…' : null,
      items: [
        const DropdownMenuItem<String?>(child: Text('— any batch —')),
        for (final b in options)
          DropdownMenuItem<String?>(value: b.id, child: Text(b.name)),
      ],
      onChanged: enabled
          ? (v) => onChanged(
                v == null ? null : options.where((b) => b.id == v).firstOrNull,
              )
          : null,
    );
  }
}

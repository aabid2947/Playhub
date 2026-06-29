import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/fee_structure.dart';
import 'package:playhub/features/billing/presentation/fee_structure_form_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Embedded section listing a batch's fee assignments. Mirrors
/// StudentFeesSection but at the batch level — every active enrollment
/// in the batch gets billed automatically by recur-invoice-generation.
class BatchFeesSection extends ConsumerWidget {
  const BatchFeesSection({
    required this.batchId,
    this.canManage = true,
    this.daysPerWeek,
    super.key,
  });

  final String batchId;

  /// When false the section is read-only: the assignment list shows but the
  /// "Assign fee" / stop-billing controls are hidden (e.g. a center_admin who
  /// can view revenue but not write finance).
  final bool canManage;

  /// Number of days/week the batch runs. When provided, the "New fee" button
  /// pre-seeds the per-day calculator in [FeeStructureFormPage].
  final int? daysPerWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync = ref.watch(assignmentsForBatchProvider(batchId));
    final feesAsync = ref.watch(feeStructuresProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Batch fees',
          trailing: canManage
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New fee'),
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => FeeStructureFormPage(
                            prefilledDaysPerWeek: daysPerWeek,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Assign'),
                      onPressed: () => _showAssignSheet(
                        context,
                        ref,
                        feesAsync.valueOrNull ?? const [],
                      ),
                    ),
                  ],
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        assignmentsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: AppLoading(),
          ),
          error: (e, _) => AppErrorView(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(assignmentsForBatchProvider(batchId)),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const AppCard(
                child: Text(
                  'No fees assigned to this batch yet. Each active '
                  'enrollment will be billed for assigned fees by the '
                  'nightly cron.',
                ),
              );
            }
            final fees = feesAsync.valueOrNull ?? const <FeeStructure>[];
            final byId = {for (final f in fees) f.id: f};
            return AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _AssignmentTile(
                      assignment: rows[i],
                      fee: byId[rows[i].feeStructureId],
                      onDeactivate: canManage
                          ? () async {
                              final ok = await _confirmDeactivate(
                                context,
                                byId[rows[i].feeStructureId],
                              );
                              if (!ok) return;
                              await deactivateBatchAssignment(
                                ref,
                                assignmentId: rows[i].id,
                                batchId: batchId,
                              );
                            }
                          : null,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _showAssignSheet(
    BuildContext context,
    WidgetRef ref,
    List<FeeStructure> fees,
  ) async {
    final active = fees.where((f) => f.isActive).toList();
    if (active.isEmpty) {
      AppSnackbar.info(context, 'No active fee structures. Create one first.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _AssignSheet(
        batchId: batchId,
        fees: active,
        ref: ref,
      ),
    );
  }

  Future<bool> _confirmDeactivate(
    BuildContext context,
    FeeStructure? fee,
  ) async {
    final name = fee?.name ?? 'this fee';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop billing?'),
        content: Text(
          'New invoices for "$name" will no longer be generated for this '
          'batch. Invoices already issued are unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppSemanticColors.of(ctx).danger,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stop billing'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

class _AssignmentTile extends StatelessWidget {
  const _AssignmentTile({
    required this.assignment,
    required this.fee,
    required this.onDeactivate,
  });

  final BatchFeeAssignment assignment;
  final FeeStructure? fee;

  /// Null in read-only mode — the stop-billing control is then hidden, but the
  /// active/inactive badge still shows.
  final Future<void> Function()? onDeactivate;

  @override
  Widget build(BuildContext context) {
    return _AssignmentRow(
      icon: Icons.receipt_long_outlined,
      tint: colorFromName(fee?.name ?? 'fee'),
      title: fee?.name ?? '(unknown fee)',
      subtitle: [
        fee?.type.label,
        'starts ${assignment.startDate.toIso8601String().substring(0, 10)}',
        if (assignment.billingDay != null)
          'billing day ${assignment.billingDay}',
        if (assignment.endDate != null)
          'ends ${assignment.endDate!.toIso8601String().substring(0, 10)}',
      ].whereType<String>().join(' · '),
      isActive: assignment.isActive,
      stopTooltip: 'Stop billing for this batch',
      onDeactivate: onDeactivate,
    );
  }
}

/// Shared v1 assignment-row layout used by all four billing-assignment
/// sections (student/batch × fees/discounts): a category-tinted leading glyph
/// box, a title, one tight subtitle line, an always-present active/inactive
/// [AppBadge], and the gated stop control (hidden when [onDeactivate] is null
/// or the assignment is already inactive). Renders a real [AppListTile].
class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.stopTooltip,
    required this.onDeactivate,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final bool isActive;
  final String stopTooltip;
  final Future<void> Function()? onDeactivate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glyph = isActive ? tint : scheme.outline;
    final badge = isActive
        ? const AppBadge(
            text: 'Active',
            tone: AppBadgeTone.success,
            icon: Icons.check_circle_outline,
          )
        : const AppBadge(text: 'Inactive', icon: Icons.pause_circle_outline);
    // The status badge is always present so active/inactive reads consistently;
    // the stop control is appended only when active and manageable.
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        if (isActive && onDeactivate != null) ...[
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            tooltip: stopTooltip,
            icon: Icon(Icons.stop_circle_outlined, color: scheme.error),
            onPressed: onDeactivate,
          ),
        ],
      ],
    );
    return AppListTile(
      wrapLeading: false,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: glyph.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: glyph, size: 20),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      trailing: trailing,
    );
  }
}

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({
    required this.batchId,
    required this.fees,
    required this.ref,
  });

  final String batchId;
  final List<FeeStructure> fees;
  final WidgetRef ref;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  String? _feeId;
  DateTime _start = DateTime.now();
  final _billingDay = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _feeId = widget.fees.first.id;
    _billingDay.text = DateTime.now().day.clamp(1, 28).toString();
    // Keep the invoice-generation explainer in sync as the billing day changes.
    _billingDay.addListener(_onBillingDayChanged);
  }

  @override
  void dispose() {
    _billingDay
      ..removeListener(_onBillingDayChanged)
      ..dispose();
    super.dispose();
  }

  void _onBillingDayChanged() => setState(() {});

  /// One-line summary of when the recurring-invoice cron will bill this fee.
  String _invoiceExplainer(FeeType type, int? billingDay) {
    final day = (billingDay == null || billingDay < 1 || billingDay > 28)
        ? 'the billing day'
        : 'day $billingDay';
    switch (type) {
      case FeeType.weekly:
        return 'Generates an invoice every week from the start date.';
      case FeeType.monthly:
        return 'Generates an invoice every month on $day.';
      case FeeType.quarterly:
        return 'Generates an invoice every quarter on $day.';
      case FeeType.annual:
        return 'Generates an invoice every year on $day.';
      case FeeType.oneTime:
        return 'Generates a single invoice on the start date.';
    }
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _save() async {
    if (_feeId == null || _saving) return;
    setState(() => _saving = true);
    try {
      await assignFeeToBatch(
        widget.ref,
        batchId: widget.batchId,
        feeStructureId: _feeId!,
        startDate: _start,
        billingDay: int.tryParse(_billingDay.text.trim()),
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.fees.firstWhere(
      (f) => f.id == _feeId,
      orElse: () => widget.fees.first,
    );
    final billingDay = int.tryParse(_billingDay.text.trim());
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.xs,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Assign fee to batch',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: AppType.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _invoiceExplainer(selected.type, billingDay),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppDropdownField<String>(
            label: 'Fee structure',
            value: _feeId,
            items: widget.fees
                .map(
                  (f) => DropdownMenuItem(
                    value: f.id,
                    child: Text(
                      f.pricePerDay != null
                          ? '${f.name} · ${f.type.label} · ₹${f.baseAmount.toStringAsFixed(0)}'
                              ' (₹${f.pricePerDay!.toStringAsFixed(0)}/day)'
                          : '${f.name} · ${f.type.label} · ₹${f.baseAmount.toStringAsFixed(0)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _feeId = v),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppDateField(
                  label: 'Start date',
                  value: _start,
                  onTap: _pickStart,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppFormField(
                  controller: _billingDay,
                  label: 'Billing day (1–28)',
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Assign'),
          ),
        ],
      ),
    );
  }
}

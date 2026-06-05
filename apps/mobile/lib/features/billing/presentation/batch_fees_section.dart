import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/fee_structure.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Embedded section listing a batch's fee assignments. Mirrors
/// StudentFeesSection but at the batch level — every active enrollment
/// in the batch gets billed automatically by recur-invoice-generation.
class BatchFeesSection extends ConsumerWidget {
  const BatchFeesSection({required this.batchId, super.key});

  final String batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync = ref.watch(assignmentsForBatchProvider(batchId));
    final feesAsync = ref.watch(feeStructuresProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Batch fees',
          trailing: FilledButton.tonalIcon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Assign fee'),
            onPressed: () => _showAssignSheet(
              context,
              ref,
              feesAsync.valueOrNull ?? const [],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        assignmentsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.sm),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          error: (e, _) => Text(friendlyError(e)),
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
                  for (final a in rows)
                    _AssignmentTile(
                      assignment: a,
                      fee: byId[a.feeStructureId],
                      onDeactivate: () async {
                        await deactivateBatchAssignment(
                          ref,
                          assignmentId: a.id,
                          batchId: batchId,
                        );
                      },
                    ),
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
      builder: (ctx) => _AssignSheet(
        batchId: batchId,
        fees: active,
        ref: ref,
      ),
    );
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
  final Future<void> Function() onDeactivate;

  @override
  Widget build(BuildContext context) {
    final isActive = assignment.isActive;
    final scheme = Theme.of(context).colorScheme;
    return AppListTile(
      wrapLeading: false,
      leading: Icon(
        Icons.receipt_long_outlined,
        color: isActive ? scheme.onSurfaceVariant : scheme.outline,
      ),
      title: Text(fee?.name ?? '(unknown fee)'),
      subtitle: Text(
        [
          fee?.type.label,
          'starts ${assignment.startDate.toIso8601String().substring(0, 10)}',
          if (assignment.billingDay != null)
            'billing day ${assignment.billingDay}',
          if (assignment.endDate != null)
            'ends ${assignment.endDate!.toIso8601String().substring(0, 10)}',
        ].whereType<String>().join(' · '),
      ),
      trailing: isActive
          ? IconButton(
              tooltip: 'Stop billing for this batch',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: onDeactivate,
            )
          : const AppBadge(text: 'Inactive'),
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
  }

  @override
  void dispose() {
    _billingDay.dispose();
    super.dispose();
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
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Assign fee to batch',
            style: Theme.of(context).textTheme.titleLarge,
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
                      '${f.name} · ${f.type.label} · ₹${f.baseAmount.toStringAsFixed(0)}',
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

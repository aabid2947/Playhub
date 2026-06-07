import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/billing/data/discount.dart';
import 'package:playhub/features/billing/data/discount_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Embedded section listing a student's discount assignments. Mirrors the
/// fee-assignment sections: a gated "Assign discount" action, tiles with a
/// consistent active/inactive [AppBadge], a titled assign sheet, and a
/// confirmation before deactivation.
///
/// Write actions are gated on `manageFinance` (admin tier + center_admin for
/// their own center's students; RLS scopes it via can_manage_finance).
class StudentDiscountsSection extends ConsumerWidget {
  const StudentDiscountsSection({required this.studentId, super.key});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync =
        ref.watch(studentDiscountAssignmentsProvider(studentId));
    final structuresAsync = ref.watch(discountStructuresProvider);
    final canManage = ref.watch(capabilitiesProvider).manageFinance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Discounts',
          trailing: canManage
              ? FilledButton.tonalIcon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Assign discount'),
                  onPressed: () => _showAssignSheet(
                    context,
                    ref,
                    structuresAsync.valueOrNull ?? const [],
                  ),
                )
              : null,
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
                child: Text('No discounts assigned to this student.'),
              );
            }
            final structures =
                structuresAsync.valueOrNull ?? const <DiscountStructure>[];
            final byId = {for (final s in structures) s.id: s};
            return AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final a in rows)
                    _Tile(
                      assignment: a,
                      structure: byId[a.discountStructureId],
                      onDeactivate: canManage
                          ? () async {
                              final ok = await _confirmDeactivate(
                                context,
                                byId[a.discountStructureId],
                              );
                              if (!ok) return;
                              await deactivateStudentDiscount(
                                ref,
                                assignmentId: a.id,
                                studentId: studentId,
                              );
                            }
                          : null,
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
    List<DiscountStructure> structures,
  ) async {
    final active = structures.where((s) => s.isActive).toList();
    if (active.isEmpty) {
      AppSnackbar.info(context, 'No active discounts. Create one first.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _Sheet(
        studentId: studentId,
        structures: active,
        ref: ref,
      ),
    );
  }

  Future<bool> _confirmDeactivate(
    BuildContext context,
    DiscountStructure? structure,
  ) async {
    final name = structure?.name ?? 'this discount';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop discount?'),
        content: Text(
          'New invoices for this student will no longer apply "$name". '
          'Invoices already issued are unaffected.',
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
            child: const Text('Stop discount'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.assignment,
    required this.structure,
    required this.onDeactivate,
  });

  final StudentDiscountAssignment assignment;
  final DiscountStructure? structure;

  /// Null in read-only mode — the stop control is then hidden, but the
  /// active/inactive badge still shows.
  final Future<void> Function()? onDeactivate;

  @override
  Widget build(BuildContext context) {
    final isActive = assignment.isActive;
    final scheme = Theme.of(context).colorScheme;
    final badge = isActive
        ? const AppBadge(text: 'Active', tone: AppBadgeTone.success)
        : const AppBadge(text: 'Inactive');
    // The status badge is always present so active/inactive reads consistently;
    // the deactivate control is appended only when active and manageable.
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        if (isActive && onDeactivate != null) ...[
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            tooltip: 'Stop discount',
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: onDeactivate,
          ),
        ],
      ],
    );
    return AppListTile(
      wrapLeading: false,
      leading: Icon(
        Icons.local_offer_outlined,
        color: isActive ? scheme.onSurfaceVariant : scheme.outline,
      ),
      title: Text(structure?.name ?? '(unknown discount)'),
      subtitle: Text(
        [
          structure?.summary,
          'starts ${assignment.startDate.toIso8601String().substring(0, 10)}',
          if (!assignment.stackWithBatch) 'overrides batch',
          if (assignment.endDate != null)
            'ends ${assignment.endDate!.toIso8601String().substring(0, 10)}',
        ].whereType<String>().join(' · '),
      ),
      trailing: trailing,
    );
  }
}

class _Sheet extends StatefulWidget {
  const _Sheet({
    required this.studentId,
    required this.structures,
    required this.ref,
  });

  final String studentId;
  final List<DiscountStructure> structures;
  final WidgetRef ref;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  String? _id;
  DateTime _start = DateTime.now();
  bool _stack = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _id = widget.structures.first.id;
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
    if (_id == null || _saving) return;
    setState(() => _saving = true);
    try {
      await assignDiscountToStudent(
        widget.ref,
        studentId: widget.studentId,
        discountStructureId: _id!,
        startDate: _start,
        stackWithBatch: _stack,
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
            'Assign discount',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Applies to invoices generated for this student from the start '
            'date onward.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppDropdownField<String>(
            label: 'Discount',
            value: _id,
            items: widget.structures
                .map(
                  (s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      '${s.name} · ${s.summary}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _id = v),
          ),
          const SizedBox(height: AppSpacing.md),
          AppDateField(
            label: 'Start date',
            value: _start,
            onTap: _pickStart,
          ),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            value: _stack,
            onChanged: (v) => setState(() => _stack = v),
            contentPadding: EdgeInsets.zero,
            title: const Text('Stack with batch discounts'),
            subtitle: Text(
              _stack
                  ? 'Both this discount and any batch-level discounts will apply.'
                  : 'Only this discount applies. Batch-level discounts are '
                      'suppressed for this student.',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
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

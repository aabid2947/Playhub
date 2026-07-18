import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/discount.dart';
import 'package:playhub/features/billing/data/discount_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Embedded section listing a batch's discount assignments. Mirrors the
/// fee-assignment sections: a gated "Assign discount" action, tiles with a
/// consistent active/inactive [AppBadge], a titled assign sheet, and a
/// confirmation before deactivation.
class BatchDiscountsSection extends ConsumerWidget {
  const BatchDiscountsSection({
    required this.batchId,
    this.canManage = true,
    super.key,
  });

  final String batchId;

  /// When false the section is read-only: the assignment list shows but the
  /// "Assign discount" / stop controls are hidden.
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync =
        ref.watch(batchDiscountAssignmentsProvider(batchId));
    final structuresAsync = ref.watch(discountStructuresProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Batch discounts',
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
            padding: EdgeInsets.all(AppSpacing.lg),
            child: AppLoading(),
          ),
          error: (e, _) => AppErrorView(
            message: friendlyError(e),
            onRetry: () =>
                ref.invalidate(batchDiscountAssignmentsProvider(batchId)),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const AppCard(
                child: Text(
                  'No batch-level discounts. Each enrolled student '
                  'with stack-with-batch enabled will receive these.',
                ),
              );
            }
            final structures =
                structuresAsync.valueOrNull ?? const <DiscountStructure>[];
            final byId = {for (final s in structures) s.id: s};
            return AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _Tile(
                      assignment: rows[i],
                      structure: byId[rows[i].discountStructureId],
                      onDeactivate: canManage
                          ? () async {
                              final ok = await _confirmDeactivate(
                                context,
                                byId[rows[i].discountStructureId],
                              );
                              if (!ok) return;
                              await deactivateBatchDiscount(
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
      showDragHandle: true,
      builder: (ctx) => _Sheet(
        batchId: batchId,
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
          'New invoices for this batch will no longer apply "$name". '
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

  final BatchDiscountAssignment assignment;
  final DiscountStructure? structure;

  /// Null in read-only mode — the stop control is then hidden, but the
  /// active/inactive badge still shows.
  final Future<void> Function()? onDeactivate;

  @override
  Widget build(BuildContext context) {
    return _AssignmentRow(
      icon: Icons.local_offer_outlined,
      tint: colorFromName(structure?.name ?? 'discount'),
      title: structure?.name ?? '(unknown discount)',
      subtitle: [
        structure?.summary,
        'starts ${assignment.startDate.toIso8601String().substring(0, 10)}',
        if (assignment.endDate != null)
          'ends ${assignment.endDate!.toIso8601String().substring(0, 10)}',
      ].whereType<String>().join(' · '),
      isActive: assignment.isActive,
      stopTooltip: 'Stop discount for this batch',
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

class _Sheet extends StatefulWidget {
  const _Sheet({
    required this.batchId,
    required this.structures,
    required this.ref,
  });

  final String batchId;
  final List<DiscountStructure> structures;
  final WidgetRef ref;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  String? _id;
  DateTime _start = DateTime.now();
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
      await assignDiscountToBatch(
        widget.ref,
        batchId: widget.batchId,
        discountStructureId: _id!,
        startDate: _start,
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
        top: AppSpacing.xs,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Assign discount to batch',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: AppType.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Applies to invoices generated for every enrolled student with '
            'stack-with-batch enabled.',
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

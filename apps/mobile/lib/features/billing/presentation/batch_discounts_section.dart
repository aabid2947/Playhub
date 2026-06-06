import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/billing/data/discount.dart';
import 'package:playhub/features/billing/data/discount_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
            padding: EdgeInsets.all(AppSpacing.sm),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          error: (e, _) => Text(friendlyError(e)),
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
                  for (final a in rows)
                    _Tile(
                      assignment: a,
                      structure: byId[a.discountStructureId],
                      onDeactivate: canManage
                          ? () async {
                              await deactivateBatchDiscount(
                                ref,
                                assignmentId: a.id,
                                batchId: batchId,
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
        batchId: batchId,
        structures: active,
        ref: ref,
      ),
    );
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

  /// Null in read-only mode — the tile then shows a status badge instead of a
  /// stop control.
  final Future<void> Function()? onDeactivate;

  @override
  Widget build(BuildContext context) {
    final active = assignment.isActive;
    final scheme = Theme.of(context).colorScheme;
    final Widget trailing;
    if (!active) {
      trailing = const AppBadge(text: 'Inactive');
    } else if (onDeactivate != null) {
      trailing = IconButton(
        tooltip: 'Stop discount',
        icon: const Icon(Icons.stop_circle_outlined),
        onPressed: onDeactivate,
      );
    } else {
      trailing = const AppBadge(text: 'Active', tone: AppBadgeTone.success);
    }
    return AppListTile(
      wrapLeading: false,
      leading: Icon(
        Icons.local_offer_outlined,
        color: active ? scheme.onSurfaceVariant : scheme.outline,
      ),
      title: Text(structure?.name ?? '(unknown discount)'),
      subtitle: Text(
        [
          structure?.summary,
          'starts ${assignment.startDate.toIso8601String().substring(0, 10)}',
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
            'Assign discount to batch',
            style: Theme.of(context).textTheme.titleLarge,
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

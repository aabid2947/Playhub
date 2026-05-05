import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/billing/data/discount.dart';
import 'package:playhub/features/billing/data/discount_providers.dart';

class BatchDiscountsSection extends ConsumerWidget {
  const BatchDiscountsSection({required this.batchId, super.key});

  final String batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync =
        ref.watch(batchDiscountAssignmentsProvider(batchId));
    final structuresAsync = ref.watch(discountStructuresProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Batch discounts',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Assign discount'),
              onPressed: () => _showAssignSheet(
                context,
                ref,
                structuresAsync.valueOrNull ?? const [],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        assignmentsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          error: (e, _) => Text('Error: $e'),
          data: (rows) {
            if (rows.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No batch-level discounts. Each enrolled student '
                  'with stack-with-batch enabled will receive these.',
                ),
              );
            }
            final structures =
                structuresAsync.valueOrNull ?? const <DiscountStructure>[];
            final byId = {for (final s in structures) s.id: s};
            return Card(
              child: Column(
                children: [
                  for (final a in rows)
                    _Tile(
                      assignment: a,
                      structure: byId[a.discountStructureId],
                      onDeactivate: () async {
                        await deactivateBatchDiscount(
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
    List<DiscountStructure> structures,
  ) async {
    final active = structures.where((s) => s.isActive).toList();
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active discounts. Create one first.'),
        ),
      );
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
  final Future<void> Function() onDeactivate;

  @override
  Widget build(BuildContext context) {
    final active = assignment.isActive;
    return ListTile(
      leading: Icon(
        Icons.local_offer_outlined,
        color: active ? null : Colors.grey,
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
      trailing: active
          ? IconButton(
              tooltip: 'Stop discount',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: onDeactivate,
            )
          : const Chip(
              label: Text('inactive'),
              visualDensity: VisualDensity.compact,
            ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Assign failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Assign discount to batch',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _id,
            items: widget.structures
                .map((s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        '${s.name} · ${s.summary}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _id = v),
            decoration: const InputDecoration(
              labelText: 'Discount',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _start,
                firstDate:
                    DateTime.now().subtract(const Duration(days: 60)),
                lastDate:
                    DateTime.now().add(const Duration(days: 365 * 2)),
              );
              if (picked != null) setState(() => _start = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Start date',
                border: OutlineInputBorder(),
              ),
              child: Text(_start.toIso8601String().substring(0, 10)),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Assign'),
          ),
        ],
      ),
    );
  }
}

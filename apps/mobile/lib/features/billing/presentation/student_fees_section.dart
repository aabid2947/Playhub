import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/data/fee_structure.dart';
import 'package:playhub/core/error_messages.dart';

/// Embedded section listing a student's fee assignments and offering
/// "Assign fee" + "Deactivate" actions. Caller renders this from the
/// student edit form (existing student only).
class StudentFeesSection extends ConsumerWidget {
  const StudentFeesSection({required this.studentId, super.key});

  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignmentsAsync =
        ref.watch(assignmentsForStudentProvider(studentId));
    final feesAsync = ref.watch(feeStructuresProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Assigned fees',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Assign fee'),
              onPressed: () => _showAssignSheet(
                context,
                ref,
                feesAsync.valueOrNull ?? const [],
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
          error: (e, _) => Text(friendlyError(e)),
          data: (rows) {
            if (rows.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No fee structures assigned yet. The recurring-invoice '
                  'cron only generates invoices for assigned fees.',
                ),
              );
            }
            final fees = feesAsync.valueOrNull ?? const <FeeStructure>[];
            final byId = {for (final f in fees) f.id: f};
            return Card(
              child: Column(
                children: [
                  for (final a in rows)
                    _AssignmentTile(
                      assignment: a,
                      fee: byId[a.feeStructureId],
                      onDeactivate: () async {
                        await deactivateAssignment(
                          ref,
                          assignmentId: a.id,
                          studentId: studentId,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active fee structures. Create one first.'),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AssignSheet(
        studentId: studentId,
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

  final StudentFeeAssignment assignment;
  final FeeStructure? fee;
  final Future<void> Function() onDeactivate;

  @override
  Widget build(BuildContext context) {
    final isActive = assignment.isActive;
    return ListTile(
      leading: Icon(
        Icons.receipt_long_outlined,
        color: isActive ? null : Colors.grey,
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
              tooltip: 'Stop billing',
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

class _AssignSheet extends StatefulWidget {
  const _AssignSheet({
    required this.studentId,
    required this.fees,
    required this.ref,
  });

  final String studentId;
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

  Future<void> _save() async {
    if (_feeId == null || _saving) return;
    setState(() => _saving = true);
    try {
      await assignFee(
        widget.ref,
        studentId: widget.studentId,
        feeStructureId: _feeId!,
        startDate: _start,
        billingDay: int.tryParse(_billingDay.text.trim()),
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
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
          Text('Assign fee', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _feeId,
            items: widget.fees
                .map((f) => DropdownMenuItem(
                      value: f.id,
                      child: Text(
                        '${f.name} · ${f.type.label} · ₹${f.baseAmount.toStringAsFixed(0)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _feeId = v),
            decoration: const InputDecoration(
              labelText: 'Fee structure',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
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
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _billingDay,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Billing day (1–28)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
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

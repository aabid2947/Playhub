import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Bottom sheet for recording a stock movement (in / out / return / adjustment).
class MovementSheet extends ConsumerStatefulWidget {
  const MovementSheet({required this.item, super.key});
  final InventoryItem item;

  @override
  ConsumerState<MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends ConsumerState<MovementSheet> {
  String _kind = 'in';
  final _qty = TextEditingController(text: '1');
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  String? _studentId;
  String? _coachId;
  bool _saving = false;

  @override
  void dispose() {
    _qty.dispose();
    _ref.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    if (qty == 0) {
      AppSnackbar.error(context, 'Enter a non-zero quantity.');
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = await ref.read(inventoryRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.recordMovement(
        itemId: widget.item.id,
        kind: _kind,
        qty: qty,
        studentId: _studentId,
        coachId: _coachId,
        vendorId: widget.item.vendorId,
        reference: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      ref
        ..invalidate(itemMovementsProvider(widget.item.id))
        ..invalidate(inventoryItemsProvider);
      if (!mounted) return;
      AppSnackbar.success(context, 'Movement recorded.');
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(studentsProvider).valueOrNull ?? const <Student>[];
    final coaches = ref.watch(coachesProvider).valueOrNull ?? const [];
    final needsRecipient = _kind == 'out' || _kind == 'return';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Movement · ${widget.item.name}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'in', label: Text('In')),
              ButtonSegment(value: 'out', label: Text('Out')),
              ButtonSegment(value: 'return', label: Text('Return')),
              ButtonSegment(value: 'adjustment', label: Text('Adjust')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: AppSpacing.md),
          AppFormField(
            controller: _qty,
            label: _kind == 'adjustment'
                ? 'Qty (signed)'
                : 'Qty (positive number)',
            keyboardType: TextInputType.number,
          ),
          if (needsRecipient) ...[
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<String?>(
              label: 'Student',
              value: _studentId,
              items: [
                const DropdownMenuItem<String?>(child: Text('— None —')),
                for (final s in students)
                  DropdownMenuItem<String?>(
                    value: s.id,
                    child: Text(s.fullName),
                  ),
              ],
              onChanged: (v) => setState(() => _studentId = v),
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<String?>(
              label: 'Coach',
              value: _coachId,
              items: [
                const DropdownMenuItem<String?>(child: Text('— None —')),
                for (final c in coaches)
                  DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text(c.fullName),
                  ),
              ],
              onChanged: (v) => setState(() => _coachId = v),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppFormField(
            controller: _ref,
            label: 'Reference (PO #, etc.)',
          ),
          const SizedBox(height: AppSpacing.md),
          AppFormField(
            controller: _notes,
            label: 'Notes',
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Record'),
          ),
        ],
      ),
    );
  }
}

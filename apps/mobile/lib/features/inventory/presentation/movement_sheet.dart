import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/inventory/data/inventory.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';

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
    if (qty == 0) return;
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
      ref.invalidate(itemMovementsProvider(widget.item.id));
      ref.invalidate(inventoryItemsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(studentsProvider).valueOrNull ?? const <Student>[];
    final coaches = ref.watch(coachesProvider).valueOrNull ?? const [];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Movement · ${widget.item.name}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _kind == 'adjustment'
                  ? 'Qty (signed)'
                  : 'Qty (positive number)',
            ),
          ),
          const SizedBox(height: 12),
          if (_kind == 'out' || _kind == 'return')
            DropdownButtonFormField<String?>(
              initialValue: _studentId,
              decoration: const InputDecoration(labelText: 'Student'),
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
          if (_kind == 'out' || _kind == 'return') const SizedBox(height: 12),
          if (_kind == 'out' || _kind == 'return')
            DropdownButtonFormField<String?>(
              initialValue: _coachId,
              decoration: const InputDecoration(labelText: 'Coach'),
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
          if (_kind == 'out' || _kind == 'return') const SizedBox(height: 12),
          TextField(
            controller: _ref,
            decoration:
                const InputDecoration(labelText: 'Reference (PO #, etc.)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: 16),
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

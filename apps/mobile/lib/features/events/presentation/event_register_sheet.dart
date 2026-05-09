import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:playhub/features/events/data/event_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';

/// Bottom sheet — staff picks a student from their academy and registers
/// them for [event]. Parents/students see only their linked students; the
/// caller passes a pre-filtered list via the optional [studentsOverride].
class EventRegisterSheet extends ConsumerStatefulWidget {
  const EventRegisterSheet({
    required this.event,
    this.studentsOverride,
    super.key,
  });
  final EventEntry event;
  final List<Student>? studentsOverride;

  @override
  ConsumerState<EventRegisterSheet> createState() =>
      _EventRegisterSheetState();
}

class _EventRegisterSheetState extends ConsumerState<EventRegisterSheet> {
  String? _studentId;
  final _notes = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_studentId == null) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(eventsRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.register(
        eventId: widget.event.id,
        studentId: _studentId!,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      ref.invalidate(eventRegistrationsProvider(widget.event.id));
      ref.invalidate(myStudentsEventRegsProvider);
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
    final students = widget.studentsOverride ??
        ref.watch(studentsProvider).valueOrNull ??
        const <Student>[];
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
          Text('Register for ${widget.event.title}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _studentId,
            decoration: const InputDecoration(labelText: 'Student'),
            items: [
              for (final s in students)
                DropdownMenuItem(value: s.id, child: Text(s.fullName)),
            ],
            onChanged: (v) => setState(() => _studentId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration:
                const InputDecoration(labelText: 'Notes (category, etc.)'),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          if (widget.event.feeAmount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Fee: ₹${widget.event.feeAmount} (collect separately for now)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          FilledButton(
            onPressed: _saving || _studentId == null ? null : _register,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Register'),
          ),
        ],
      ),
    );
  }
}

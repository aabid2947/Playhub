import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:playhub/features/events/data/event_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
      ref
        ..invalidate(eventRegistrationsProvider(widget.event.id))
        ..invalidate(myStudentsEventRegsProvider);
      if (!mounted) return;
      AppSnackbar.success(context, 'Registered.');
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
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
            'Register for ${widget.event.title}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppDropdownField<String>(
            label: 'Student',
            value: _studentId,
            items: [
              for (final s in students)
                DropdownMenuItem(value: s.id, child: Text(s.fullName)),
            ],
            onChanged: (v) => setState(() => _studentId = v),
          ),
          const SizedBox(height: AppSpacing.md),
          AppFormField(
            controller: _notes,
            label: 'Notes (category, etc.)',
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (widget.event.feeAmount > 0) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppSemanticColors.of(context).info,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Fee: ₹${widget.event.feeAmount} '
                    '(collect separately for now)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
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

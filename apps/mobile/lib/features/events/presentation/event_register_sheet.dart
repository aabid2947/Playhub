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
  final _search = TextEditingController();
  String _query = '';
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    _search.dispose();
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

  List<Student> _filtered(List<Student> students) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return students;
    return students
        .where((s) => s.fullName.toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final students = widget.studentsOverride ??
        ref.watch(studentsProvider).valueOrNull ??
        const <Student>[];
    final filtered = _filtered(students);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            _Header(event: widget.event),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                shrinkWrap: true,
                children: [
                  const AppSectionHeader(
                    title: 'Choose a student',
                    icon: Icons.person_search_outlined,
                  ),
                  AppFormField(
                    controller: _search,
                    hint: 'Search students by name',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _StudentPicker(
                    students: filtered,
                    hasAny: students.isNotEmpty,
                    selectedId: _studentId,
                    onSelected: (id) => setState(() => _studentId = id),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const AppSectionHeader(
                    title: 'Notes',
                    icon: Icons.notes_rounded,
                  ),
                  AppFormField(
                    controller: _notes,
                    label: 'Category, weight class, etc. (optional)',
                    maxLines: 3,
                  ),
                  if (widget.event.feeAmount > 0) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _FeeNote(feeAmount: widget.event.feeAmount),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_studentId == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        'Select a student to continue.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed:
                        _saving || _studentId == null ? null : _register,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Register'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rounded drag affordance at the top of the sheet.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
    );
  }
}

/// Title row: event title + a short context line (kind · date) and a close
/// button so the sheet reads as a deliberate task, not a bare form.
class _Header extends StatelessWidget {
  const _Header({required this.event});
  final EventEntry event;

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Deterministic accent from the event kind, matching the detail hero.
    final c = colorFromName(event.kind.label);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(Icons.how_to_reg_rounded, color: c, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Register for ${event.title}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: AppType.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${event.kind.label} · ${_formatDate(event.startsAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Searchable, single-select student list. Renders selectable [AppListTile]s
/// with a leading initial avatar and a trailing check for the chosen student;
/// shows an [AppEmptyState] when there are no students or no search matches.
class _StudentPicker extends StatelessWidget {
  const _StudentPicker({
    required this.students,
    required this.hasAny,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Student> students;
  final bool hasAny;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (students.isEmpty) {
      return AppCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: AppEmptyState(
            icon: hasAny ? Icons.search_off : Icons.person_outline,
            title: hasAny ? 'No matches' : 'No students yet',
            subtitle: hasAny
                ? 'No students match your search.'
                : 'Add a student before registering for this event.',
          ),
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < students.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _StudentTile(
              student: students[i],
              selected: students[i].id == selectedId,
              onTap: () => onSelected(students[i].id),
              scheme: scheme,
            ),
          ],
        ],
      ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({
    required this.student,
    required this.selected,
    required this.onTap,
    required this.scheme,
  });

  final Student student;
  final bool selected;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      onTap: onTap,
      wrapLeading: false,
      // A gradient-initials avatar; selection is communicated via the trailing
      // check rather than recoloring the disc, keeping each student's color.
      leading: AppAvatar(
        student.fullName,
        size: 40,
        color: selected ? scheme.primary : null,
      ),
      title: Text(student.fullName),
      subtitle: student.parentName.trim().isEmpty
          ? null
          : Text('Parent: ${student.parentName}'),
      trailing: selected
          ? Icon(Icons.check_circle, color: scheme.primary)
          : Icon(Icons.circle_outlined, color: scheme.outlineVariant),
    );
  }
}

/// Explains the fee handling: registration does not record a payment, so the
/// fee must be collected separately. A toned info callout, not a buried line.
class _FeeNote extends StatelessWidget {
  const _FeeNote({required this.feeAmount});
  final double feeAmount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = AppSemanticColors.of(context).info;
    final fee = feeAmount == feeAmount.roundToDouble()
        ? feeAmount.toStringAsFixed(0)
        : feeAmount.toStringAsFixed(2);

    return AppCard(
      color: AppSemanticColors.of(context).infoContainer,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Entry fee: ₹$fee',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: AppType.semibold,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Registering here does not record a payment — '
                  'collect the fee separately for now.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

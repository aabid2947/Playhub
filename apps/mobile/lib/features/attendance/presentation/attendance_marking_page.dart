import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/attendance/data/attendance.dart';
import 'package:playhub/features/attendance/data/attendance_providers.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Per-batch attendance marking screen. Shows enrolled students for the given
/// batch, lets the coach toggle each student's status, bulk mark all-present,
/// and add notes. Saves are upsert-on-(batch, student, date).
class AttendanceMarkingPage extends ConsumerStatefulWidget {
  const AttendanceMarkingPage({
    required this.batch,
    required this.date,
    super.key,
  });

  final Batch batch;
  final DateTime date;

  @override
  ConsumerState<AttendanceMarkingPage> createState() =>
      _AttendanceMarkingPageState();
}

class _AttendanceMarkingPageState extends ConsumerState<AttendanceMarkingPage> {
  /// In-memory edit buffer keyed by studentId. Initialised from the server
  /// snapshot on first frame.
  final Map<String, AttendanceStatus> _statuses = {};
  final Map<String, TextEditingController> _notes = {};
  bool _seeded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _seed(
    List<Student> roster,
    List<AttendanceRecord> existing,
  ) {
    if (_seeded) return;
    final byStudent = {for (final r in existing) r.studentId: r};
    for (final s in roster) {
      final r = byStudent[s.id];
      _statuses[s.id] = r?.status ?? AttendanceStatus.absent;
      _notes[s.id] = TextEditingController(text: r?.notes ?? '');
    }
    _seeded = true;
  }

  void _markAllPresent(List<Student> roster) {
    setState(() {
      for (final s in roster) {
        _statuses[s.id] = AttendanceStatus.present;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final entries = _statuses.entries
          .map((e) => (
                studentId: e.key,
                status: e.value,
                notes: _notes[e.key]?.text.trim().isEmpty ?? true
                    ? null
                    : _notes[e.key]!.text.trim(),
              ))
          .toList();
      await upsertAttendance(
        ref,
        batchId: widget.batch.id,
        date: widget.date,
        entries: entries,
      );
      if (!mounted) return;
      AppSnackbar.success(
        context,
        'Saved attendance for ${entries.length} students.',
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enrollmentsAsync =
        ref.watch(batchEnrollmentsProvider(widget.batch.id));
    final studentsAsync = ref.watch(studentsProvider);
    final attendanceAsync = ref.watch(attendanceForBatchProvider(
      AttendanceKey(batchId: widget.batch.id, date: widget.date),
    ));

    return Scaffold(
      appBar: AppBar(
        title: Text('Mark attendance · ${widget.batch.name}'),
      ),
      body: enrollmentsAsync.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () =>
              ref.invalidate(batchEnrollmentsProvider(widget.batch.id)),
        ),
        data: (enrollments) {
          final allStudents = studentsAsync.valueOrNull ?? const <Student>[];
          final roster = _rosterFromState(enrollments, allStudents);
          if (roster.isEmpty) {
            return const AppEmptyState(
              icon: Icons.group_off_outlined,
              title: 'No students enrolled',
              subtitle:
                  'There are no active students in this batch yet. Enrol '
                  'students before marking attendance.',
            );
          }
          final attendance = attendanceAsync.valueOrNull;
          if (attendance == null) {
            return const AppSkeletonList();
          }
          _seed(roster, attendance);

          final presentCount = roster
              .where((s) => _statuses[s.id] == AttendanceStatus.present)
              .length;

          return Column(
            children: [
              _DateHeader(date: widget.date),
              _ActionBar(
                presentCount: presentCount,
                total: roster.length,
                onMarkAllPresent:
                    _saving ? null : () => _markAllPresent(roster),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  itemCount: roster.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, i) {
                    final s = roster[i];
                    return _StudentCard(
                      student: s,
                      status: _statuses[s.id]!,
                      notesCtrl: _notes[s.id]!,
                      onStatus: (v) => setState(() => _statuses[s.id] = v),
                    );
                  },
                ),
              ),
              _SaveFooter(
                statuses: roster.map((s) => _statuses[s.id]!).toList(),
                saving: _saving,
                onSave: _save,
              ),
            ],
          );
        },
      ),
    );
  }

  List<Student> _rosterFromState(
    List<Enrollment> enrollments,
    List<Student> allStudents,
  ) {
    final byId = {for (final s in allStudents) s.id: s};
    final activeIds = enrollments
        .where((e) => e.status == 'active')
        .map((e) => e.studentId)
        .toList();
    return activeIds
        .map((id) => byId[id])
        .whereType<Student>()
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }
}

/// Tinted band showing the session date in a human-readable form.
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});
  final DateTime date;

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _humanDate() {
    final weekday = _weekdays[date.weekday - 1];
    final month = _months[date.month - 1];
    return '$weekday, ${date.day} $month ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _humanDate(),
              style: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Row sitting directly above the list: a marked-present count cue on the left
/// and a visible "Mark all present" action on the right.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.presentCount,
    required this.total,
    required this.onMarkAllPresent,
  });

  final int presentCount;
  final int total;
  final VoidCallback? onMarkAllPresent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$presentCount of $total marked present',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onMarkAllPresent,
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('Mark all present'),
          ),
        ],
      ),
    );
  }
}

/// One student's attendance card: name, a readable status selector, and a
/// reserved (always-present, non-jittering) note field.
class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.student,
    required this.status,
    required this.notesCtrl,
    required this.onStatus,
  });

  final Student student;
  final AttendanceStatus status;
  final TextEditingController notesCtrl;
  final ValueChanged<AttendanceStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            student.fullName,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: AppType.semibold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Readable status selector — labels, not icon-only. Scrolls if a
          // narrow screen can't fit all four segments.
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<AttendanceStatus>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AttendanceStatus.present,
                    icon: Icon(Icons.check, size: 18),
                    label: Text('Present'),
                  ),
                  ButtonSegment(
                    value: AttendanceStatus.late,
                    icon: Icon(Icons.access_time, size: 18),
                    label: Text('Late'),
                  ),
                  ButtonSegment(
                    value: AttendanceStatus.excused,
                    icon: Icon(Icons.event_busy, size: 18),
                    label: Text('Excused'),
                  ),
                  ButtonSegment(
                    value: AttendanceStatus.absent,
                    icon: Icon(Icons.close, size: 18),
                    label: Text('Absent'),
                  ),
                ],
                selected: {status},
                onSelectionChanged: (v) => onStatus(v.first),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Reserved note area — always rendered so the card height never
          // jitters as the status changes.
          TextField(
            controller: notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Footer: a per-status completion breakdown above a full-width save button.
class _SaveFooter extends StatelessWidget {
  const _SaveFooter({
    required this.statuses,
    required this.saving,
    required this.onSave,
  });

  final List<AttendanceStatus> statuses;
  final bool saving;
  final Future<void> Function() onSave;

  int _count(AttendanceStatus s) => statuses.where((v) => v == s).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: AppElevation.low,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  AppBadge(
                    text: 'Present ${_count(AttendanceStatus.present)}',
                    tone: AppBadgeTone.success,
                  ),
                  AppBadge(
                    text: 'Late ${_count(AttendanceStatus.late)}',
                    tone: AppBadgeTone.warning,
                  ),
                  AppBadge(
                    text: 'Excused ${_count(AttendanceStatus.excused)}',
                    tone: AppBadgeTone.info,
                  ),
                  AppBadge(
                    text: 'Absent ${_count(AttendanceStatus.absent)}',
                    tone: AppBadgeTone.danger,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(saving ? 'Saving…' : 'Save attendance'),
                  onPressed: saving ? null : onSave,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

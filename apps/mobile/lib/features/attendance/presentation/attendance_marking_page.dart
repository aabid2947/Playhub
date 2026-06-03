import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/attendance/data/attendance.dart';
import 'package:playhub/features/attendance/data/attendance_providers.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/core/error_messages.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved attendance for ${entries.length} students.')),
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enrollmentsAsync = ref.watch(batchEnrollmentsProvider(widget.batch.id));
    final studentsAsync = ref.watch(studentsProvider);
    final attendanceAsync = ref.watch(attendanceForBatchProvider(
      AttendanceKey(batchId: widget.batch.id, date: widget.date),
    ));

    return Scaffold(
      appBar: AppBar(
        title: Text('Mark attendance · ${widget.batch.name}'),
        actions: [
          if (_seeded)
            IconButton(
              tooltip: 'Mark all present',
              icon: const Icon(Icons.done_all),
              onPressed: _saving
                  ? null
                  : () {
                      final roster = _rosterFromState(
                        enrollmentsAsync.valueOrNull ?? const [],
                        studentsAsync.valueOrNull ?? const [],
                      );
                      _markAllPresent(roster);
                    },
            ),
        ],
      ),
      body: enrollmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (enrollments) {
          final allStudents = studentsAsync.valueOrNull ?? const <Student>[];
          final roster = _rosterFromState(enrollments, allStudents);
          if (roster.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No active students enrolled in this batch yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final attendance = attendanceAsync.valueOrNull;
          if (attendance == null) {
            return const Center(child: CircularProgressIndicator());
          }
          _seed(roster, attendance);

          return Column(
            children: [
              _DateHeader(date: widget.date),
              Expanded(
                child: ListView.separated(
                  itemCount: roster.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = roster[i];
                    return _StudentRow(
                      student: s,
                      status: _statuses[s.id]!,
                      notesCtrl: _notes[s.id]!,
                      onStatus: (v) => setState(() => _statuses[s.id] = v),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check),
                      label: Text(_saving ? 'Saving…' : 'Save'),
                      onPressed: _saving ? null : _save,
                    ),
                  ),
                ),
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

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final ymd = '${date.year}-${date.month.toString().padLeft(2, '0')}'
        '-${date.day.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Icon(Icons.calendar_today_outlined, size: 16),
          const SizedBox(width: 8),
          Text(
            ymd,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  student.fullName,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              SegmentedButton<AttendanceStatus>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AttendanceStatus.present,
                    icon: Icon(Icons.check, size: 18),
                    tooltip: 'Present',
                  ),
                  ButtonSegment(
                    value: AttendanceStatus.late,
                    icon: Icon(Icons.access_time, size: 18),
                    tooltip: 'Late',
                  ),
                  ButtonSegment(
                    value: AttendanceStatus.excused,
                    icon: Icon(Icons.event_busy, size: 18),
                    tooltip: 'Excused',
                  ),
                  ButtonSegment(
                    value: AttendanceStatus.absent,
                    icon: Icon(Icons.close, size: 18),
                    tooltip: 'Absent',
                  ),
                ],
                selected: {status},
                onSelectionChanged: (v) => onStatus(v.first),
              ),
            ],
          ),
          if (status != AttendanceStatus.present)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  hintText: 'Note (optional)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

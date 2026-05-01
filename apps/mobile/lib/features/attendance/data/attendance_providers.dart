import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/attendance/data/attendance.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';

/// (batchId, ymd) tuple keyed family. We use a stable string key so Riverpod
/// can hash-cache the family entry.
@immutable
class AttendanceKey {
  const AttendanceKey({required this.batchId, required this.date});
  final String batchId;
  final DateTime date;

  String get ymd =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is AttendanceKey && other.batchId == batchId && other.ymd == ymd;
  @override
  int get hashCode => Object.hash(batchId, ymd);
}

/// All attendance rows for a given batch+date. Empty list = nothing marked
/// yet for that day.
final attendanceForBatchProvider = FutureProvider.family<
    List<AttendanceRecord>, AttendanceKey>((ref, key) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('attendance_records')
      .select()
      .eq('batch_id', key.batchId)
      .eq('date', key.ymd);
  return (rows as List)
      .map((r) => AttendanceRecord.fromMap(r as Map<String, dynamic>))
      .toList();
});

/// Today's batches for the current user. A batch is "today's" if today's
/// 3-letter day-of-week appears in `schedule.days`.
final todaysBatchesProvider = FutureProvider<List<Batch>>((ref) async {
  final batches = await ref.watch(batchesProvider.future);
  final dow = _todayDow();
  return batches.where((b) {
    if (!b.isActive) return false;
    return b.schedule.days.any((d) => d.toLowerCase() == dow);
  }).toList()
    ..sort((a, b) {
      final at = a.schedule.startTime ?? '99:99';
      final bt = b.schedule.startTime ?? '99:99';
      return at.compareTo(bt);
    });
});

/// Last 30 days of attendance records for a single student. Used by the
/// student detail page.
final attendanceForStudentProvider = FutureProvider.family<
    List<AttendanceRecord>, String>((ref, studentId) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('attendance_records')
      .select()
      .eq('student_id', studentId)
      .gte(
        'date',
        DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String()
            .substring(0, 10),
      )
      .order('date', ascending: false);
  return (rows as List)
      .map((r) => AttendanceRecord.fromMap(r as Map<String, dynamic>))
      .toList();
});

/// Per-student summary row from the materialized view.
final attendanceSummaryProvider = FutureProvider.family<AttendanceSummary?,
    String>((ref, studentId) async {
  final client = ref.read(supabaseClientProvider);
  final row = await client
      .from('student_attendance_summary_view')
      .select()
      .eq('student_id', studentId)
      .maybeSingle();
  if (row == null) return null;
  return AttendanceSummary.fromMap(row);
});

/// Bulk-upsert attendance for an entire batch on a given date. Existing rows
/// for the same (batch, student, date) are updated by `upsert` on the
/// composite unique constraint.
Future<void> upsertAttendance(
  WidgetRef ref, {
  required String batchId,
  required DateTime date,
  required List<({String studentId, AttendanceStatus status, String? notes})>
      entries,
  String method = 'manual',
}) async {
  if (entries.isEmpty) return;
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) {
    throw StateError('No academy linked to current user');
  }

  final ymd = '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  final payload = entries
      .map((e) => <String, dynamic>{
            'academy_id': academyId,
            'batch_id': batchId,
            'student_id': e.studentId,
            'date': ymd,
            'status': e.status.dbValue,
            if (e.notes != null && e.notes!.isNotEmpty) 'notes': e.notes,
            'method': method,
            'marked_by': profile?.id,
          })
      .toList();

  await client.from('attendance_records').upsert(
        payload,
        onConflict: 'batch_id,student_id,date',
      );

  ref.invalidate(
    attendanceForBatchProvider(AttendanceKey(batchId: batchId, date: date)),
  );
  for (final e in entries) {
    ref
      ..invalidate(attendanceForStudentProvider(e.studentId))
      ..invalidate(attendanceSummaryProvider(e.studentId));
  }
}

String _todayDow() {
  // DateTime.weekday: 1=Mon ... 7=Sun. Map to 3-letter lowercase code matching
  // the values written by SchedulePicker (mon/tue/wed/thu/fri/sat/sun).
  const codes = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  return codes[DateTime.now().weekday - 1];
}

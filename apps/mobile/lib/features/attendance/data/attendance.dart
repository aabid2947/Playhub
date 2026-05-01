/// Attendance status for one student on one date.
enum AttendanceStatus {
  present('present', 'Present'),
  absent('absent', 'Absent'),
  late('late', 'Late'),
  excused('excused', 'Excused');

  const AttendanceStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static AttendanceStatus? fromDb(String? v) {
    if (v == null) return null;
    for (final s in values) {
      if (s.dbValue == v) return s;
    }
    return null;
  }
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.academyId,
    required this.batchId,
    required this.studentId,
    required this.date,
    required this.status,
    required this.method,
    this.coachId,
    this.checkInTime,
    this.checkOutTime,
    this.notes,
    this.markedBy,
  });

  factory AttendanceRecord.fromMap(Map<String, dynamic> m) => AttendanceRecord(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        batchId: m['batch_id'] as String,
        studentId: m['student_id'] as String,
        coachId: m['coach_id'] as String?,
        date: DateTime.parse(m['date'] as String),
        status: AttendanceStatus.fromDb(m['status'] as String?) ??
            AttendanceStatus.absent,
        method: m['method'] as String? ?? 'manual',
        checkInTime: m['check_in_time'] == null
            ? null
            : DateTime.parse(m['check_in_time'] as String),
        checkOutTime: m['check_out_time'] == null
            ? null
            : DateTime.parse(m['check_out_time'] as String),
        notes: m['notes'] as String?,
        markedBy: m['marked_by'] as String?,
      );

  final String id;
  final String academyId;
  final String batchId;
  final String studentId;
  final String? coachId;
  final DateTime date;
  final AttendanceStatus status;
  final String method;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String? notes;
  final String? markedBy;
}

/// Read-only summary row from `student_attendance_summary_view`.
class AttendanceSummary {
  const AttendanceSummary({
    required this.studentId,
    required this.totalSessions,
    required this.presentCount,
    required this.absentCount,
    required this.lateCount,
    required this.excusedCount,
    this.attendancePct,
    this.lastAttendedDate,
  });

  factory AttendanceSummary.fromMap(Map<String, dynamic> m) =>
      AttendanceSummary(
        studentId: m['student_id'] as String,
        totalSessions: (m['total_sessions'] as num?)?.toInt() ?? 0,
        presentCount: (m['present_count'] as num?)?.toInt() ?? 0,
        absentCount: (m['absent_count'] as num?)?.toInt() ?? 0,
        lateCount: (m['late_count'] as num?)?.toInt() ?? 0,
        excusedCount: (m['excused_count'] as num?)?.toInt() ?? 0,
        attendancePct: (m['attendance_pct'] as num?)?.toDouble(),
        lastAttendedDate: m['last_attended_date'] == null
            ? null
            : DateTime.parse(m['last_attended_date'] as String),
      );

  final String studentId;
  final int totalSessions;
  final int presentCount;
  final int absentCount;
  final int lateCount;
  final int excusedCount;
  final double? attendancePct;
  final DateTime? lastAttendedDate;
}

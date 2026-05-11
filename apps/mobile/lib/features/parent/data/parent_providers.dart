import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/students/data/student.dart';

/// IDs of students linked to the calling parent (or own user_id for student
/// role). Resolves via the my_linked_student_ids() RPC, which returns an
/// empty array for non-parent/non-student callers.
final myLinkedStudentIdsProvider = FutureProvider<List<String>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final raw = await client.rpc('my_linked_student_ids');
  if (raw is List) {
    return raw.map((e) => e.toString()).toList(growable: false);
  }
  return const [];
});

final myLinkedStudentsProvider =
    FutureProvider<List<Student>>((ref) async {
  final ids = await ref.watch(myLinkedStudentIdsProvider.future);
  if (ids.isEmpty) return const [];
  final client = ref.watch(supabaseClientProvider);
  final rows =
      await client.from('students').select().inFilter('id', ids);
  return (rows as List)
      .map((r) => Student.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

class StudentBatchRow {
  const StudentBatchRow({
    required this.batchId,
    required this.batchName,
    required this.sportId,
    required this.studentId,
    required this.scheduleDays,
    this.startTime,
    this.endTime,
    this.coachId,
    this.coachFirstName,
    this.coachLastName,
    this.coachPhoto,
    this.coachQualifications = const [],
  });
  final String batchId;
  final String batchName;
  final String? sportId;
  final String studentId;
  final List<String> scheduleDays; // 'mon'..'sun'
  final String? startTime; // 'HH:mm'
  final String? endTime;
  final String? coachId;
  final String? coachFirstName;
  final String? coachLastName;
  final String? coachPhoto;
  final List<String> coachQualifications;

  String get scheduleSummary {
    if (scheduleDays.isEmpty) return 'No schedule';
    final dayPart = scheduleDays.join(', ');
    if (startTime == null) return dayPart;
    return '$dayPart  ${startTime!}${endTime == null ? '' : '–${endTime!}'}';
  }

  String get coachDisplayName {
    final first = coachFirstName?.trim() ?? '';
    final last = coachLastName?.trim() ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? '' : full;
  }
}

final myLinkedStudentBatchesProvider =
    FutureProvider.family<List<StudentBatchRow>, String>(
  (ref, studentId) async {
    final client = ref.watch(supabaseClientProvider);
    final rows = await client
        .from('batch_enrollments')
        .select('batch_id, batches:batch_id('
            'name, sport_id, schedule, coach_id, '
            'coach:coach_id(id, first_name, last_name, '
            'photo, qualifications))')
        .eq('student_id', studentId)
        .eq('enrollment_status', 'active');
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final b = (m['batches'] as Map?)?.cast<String, dynamic>();
      final sched =
          (b?['schedule'] as Map?)?.cast<String, dynamic>() ?? const {};
      final days = ((sched['days'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false);
      final coach = (b?['coach'] as Map?)?.cast<String, dynamic>();
      return StudentBatchRow(
        batchId: m['batch_id'] as String,
        batchName: (b?['name'] as String?) ?? '(no name)',
        sportId: b?['sport_id'] as String?,
        studentId: studentId,
        scheduleDays: days,
        startTime: sched['start_time'] as String?,
        endTime: sched['end_time'] as String?,
        coachId: b?['coach_id'] as String?,
        coachFirstName: coach?['first_name'] as String?,
        coachLastName: coach?['last_name'] as String?,
        coachPhoto: coach?['photo'] as String?,
        coachQualifications: ((coach?['qualifications'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
      );
    }).toList(growable: false);
  },
);

class UpcomingSession {
  const UpcomingSession({
    required this.date,
    required this.batchId,
    required this.batchName,
    this.startTime,
    this.endTime,
    this.coachDisplayName,
  });
  final DateTime date;
  final String batchId;
  final String batchName;
  final String? startTime;
  final String? endTime;
  final String? coachDisplayName;

  String get whenLabel {
    final dow = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][
        date.weekday - 1];
    final iso =
        '${date.year}-${date.month.toString().padLeft(2, '0')}'
        '-${date.day.toString().padLeft(2, '0')}';
    final t = startTime == null ? '' : '  ${startTime!}'
        '${endTime == null ? '' : '–${endTime!}'}';
    return '$dow $iso$t';
  }
}

/// Next 7 calendar days that overlap any of the student's active batch
/// schedules. Resolves locally from myLinkedStudentBatchesProvider — no
/// extra round-trip needed.
final studentUpcomingSessionsProvider =
    FutureProvider.family<List<UpcomingSession>, String>(
  (ref, studentId) async {
    final batches =
        await ref.watch(myLinkedStudentBatchesProvider(studentId).future);
    if (batches.isEmpty) return const [];
    const dow = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <UpcomingSession>[];
    for (var i = 0; i < 7; i++) {
      final d = today.add(Duration(days: i));
      final key = dow[d.weekday - 1];
      for (final b in batches) {
        if (!b.scheduleDays.contains(key)) continue;
        out.add(UpcomingSession(
          date: d,
          batchId: b.batchId,
          batchName: b.batchName,
          startTime: b.startTime,
          endTime: b.endTime,
          coachDisplayName: b.coachDisplayName.isEmpty
              ? null
              : b.coachDisplayName,
        ));
      }
    }
    out.sort((a, b) {
      final c = a.date.compareTo(b.date);
      if (c != 0) return c;
      return (a.startTime ?? '').compareTo(b.startTime ?? '');
    });
    return out;
  },
);

class WeeklyAttendance {
  const WeeklyAttendance({
    required this.weekStart,
    required this.total,
    required this.present,
  });
  final DateTime weekStart;
  final int total;
  final int present;

  double get pct => total == 0 ? 0 : (present * 100.0 / total);
}

/// Last 4 weeks of attendance, bucketed by Monday-of-week.
final studentAttendanceWeeklyProvider =
    FutureProvider.family<List<WeeklyAttendance>, String>(
  (ref, studentId) async {
    final days = await ref.watch(studentAttendanceProvider(studentId).future);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final mondayThisWeek =
        today.subtract(Duration(days: today.weekday - 1));
    final buckets = <DateTime, _AccPair>{};
    for (var i = 3; i >= 0; i--) {
      buckets[mondayThisWeek.subtract(Duration(days: 7 * i))] =
          _AccPair();
    }
    for (final d in days) {
      final weekday = d.date.weekday;
      final monday =
          DateTime(d.date.year, d.date.month, d.date.day)
              .subtract(Duration(days: weekday - 1));
      final bucket = buckets[monday];
      if (bucket == null) continue;
      bucket.total++;
      if (d.status == 'present' || d.status == 'late') bucket.present++;
    }
    return buckets.entries
        .map((e) => WeeklyAttendance(
              weekStart: e.key,
              total: e.value.total,
              present: e.value.present,
            ))
        .toList(growable: false);
  },
);

class _AccPair {
  int total = 0;
  int present = 0;
}

class AttendanceDay {
  const AttendanceDay({required this.date, required this.status});
  final DateTime date;
  final String status; // present | absent | late | excused
}

final studentAttendanceProvider =
    FutureProvider.family<List<AttendanceDay>, String>(
  (ref, studentId) async {
    final client = ref.watch(supabaseClientProvider);
    final from =
        DateTime.now().subtract(const Duration(days: 60)).toIso8601String();
    final rows = await client
        .from('attendance_records')
        .select('date, status')
        .eq('student_id', studentId)
        .gte('date', from)
        .order('date');
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return AttendanceDay(
        date: DateTime.parse(m['date'] as String),
        status: m['status'] as String,
      );
    }).toList(growable: false);
  },
);

class PerfPoint {
  const PerfPoint({required this.date, required this.score});
  final DateTime date;
  final double score;
}

final studentPerformanceProvider =
    FutureProvider.family<List<PerfPoint>, String>(
  (ref, studentId) async {
    final client = ref.watch(supabaseClientProvider);
    final rows = await client
        .from('performance_assessments')
        .select('assessment_date, overall_score')
        .eq('student_id', studentId)
        .order('assessment_date');
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return PerfPoint(
        date: DateTime.parse(m['assessment_date'] as String),
        score: (m['overall_score'] as num).toDouble(),
      );
    }).toList(growable: false);
  },
);

class OutstandingDues {
  const OutstandingDues({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.amount,
    required this.amountPaid,
    required this.dueDate,
    required this.status,
  });

  final String invoiceId;
  final String invoiceNumber;
  final double amount;
  final double amountPaid;
  final DateTime dueDate;
  final String status;

  double get balance => amount - amountPaid;
}

final studentOutstandingDuesProvider =
    FutureProvider.family<List<OutstandingDues>, String>(
  (ref, studentId) async {
    final client = ref.watch(supabaseClientProvider);
    final rows = await client
        .from('invoices')
        .select(
            'id, invoice_number, amount, amount_paid, due_date, status')
        .eq('student_id', studentId)
        .inFilter('status', ['issued', 'partial', 'overdue'])
        .order('due_date');
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      return OutstandingDues(
        invoiceId: m['id'] as String,
        invoiceNumber: m['invoice_number'] as String,
        amount: (m['amount'] as num).toDouble(),
        amountPaid: (m['amount_paid'] as num).toDouble(),
        dueDate: DateTime.parse(m['due_date'] as String),
        status: m['status'] as String,
      );
    }).toList(growable: false);
  },
);

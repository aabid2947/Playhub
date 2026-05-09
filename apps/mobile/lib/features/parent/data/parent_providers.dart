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
  });
  final String batchId;
  final String batchName;
  final String? sportId;
  final String studentId;
}

final myLinkedStudentBatchesProvider =
    FutureProvider.family<List<StudentBatchRow>, String>(
  (ref, studentId) async {
    final client = ref.watch(supabaseClientProvider);
    final rows = await client
        .from('batch_enrollments')
        .select('batch_id, batches:batch_id(name, sport_id)')
        .eq('student_id', studentId)
        .eq('enrollment_status', 'active');
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final b = (m['batches'] as Map?)?.cast<String, dynamic>();
      return StudentBatchRow(
        batchId: m['batch_id'] as String,
        batchName: (b?['name'] as String?) ?? '(no name)',
        sportId: b?['sport_id'] as String?,
        studentId: studentId,
      );
    }).toList(growable: false);
  },
);

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

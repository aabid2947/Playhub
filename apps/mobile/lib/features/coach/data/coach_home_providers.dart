import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/coaches/data/coach.dart';

/// The coaches row owned by the signed-in user (via coaches.user_id =
/// auth.uid()). Returns null for non-coach roles or pre-link state.
final myCoachRecordProvider = FutureProvider<Coach?>((ref) async {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return null;
  final client = ref.watch(supabaseClientProvider);
  final r = await client
      .from('coaches')
      .select()
      .eq('user_id', me)
      .maybeSingle();
  return r == null ? null : Coach.fromMap(r);
});

/// Active batches the signed-in user can see in the coach shell.
///
/// - coach / trainer: only batches where coach_id == own coaches.id
/// - head_coach    : every active batch in the academy (oversight role)
final myBatchesProvider = FutureProvider<List<Batch>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final client = ref.watch(supabaseClientProvider);
  final isHeadCoach = profile?.role == 'head_coach';

  if (isHeadCoach && profile?.academyId != null) {
    final rows = await client
        .from('batches')
        .select()
        .eq('academy_id', profile!.academyId!)
        .eq('is_active', true)
        .order('name');
    return (rows as List)
        .map((r) => Batch.fromMap(r as Map<String, dynamic>))
        .toList(growable: false);
  }

  final coach = await ref.watch(myCoachRecordProvider.future);
  if (coach == null) return const [];
  final rows = await client
      .from('batches')
      .select()
      .eq('coach_id', coach.id)
      .eq('is_active', true)
      .order('name');
  return (rows as List)
      .map((r) => Batch.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

/// Subset of myBatches whose schedule includes today's day-of-week.
final myTodaysBatchesProvider = FutureProvider<List<Batch>>((ref) async {
  final mine = await ref.watch(myBatchesProvider.future);
  final dow = _dow(DateTime.now().weekday);
  return mine.where((b) => b.schedule.days.contains(dow)).toList();
});

String _dow(int weekdayMonday1) {
  // DateTime.weekday is 1=Mon..7=Sun.
  const map = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  return map[weekdayMonday1 - 1];
}

/// Headline counts for the coach home tab.
class CoachStats {
  const CoachStats({
    required this.batchCount,
    required this.studentCount,
    required this.todaysCount,
  });
  final int batchCount;
  final int studentCount;
  final int todaysCount;
}

/// Attendance % per week (last 4 weeks) across the signed-in coach's
/// batches. Used by the coach home tab's trend card.
class CoachWeeklyAttendance {
  const CoachWeeklyAttendance({
    required this.weekStart,
    required this.total,
    required this.present,
  });
  final DateTime weekStart;
  final int total;
  final int present;
  double get pct => total == 0 ? 0 : (present * 100.0 / total);
}

final coachAttendanceTrendProvider =
    FutureProvider<List<CoachWeeklyAttendance>>((ref) async {
  final batches = await ref.watch(myBatchesProvider.future);
  if (batches.isEmpty) return const [];
  final client = ref.watch(supabaseClientProvider);
  final ids = batches.map((b) => b.id).toList();

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final mondayThisWeek =
      today.subtract(Duration(days: today.weekday - 1));
  final from = mondayThisWeek.subtract(const Duration(days: 21));
  final fromIso = '${from.year}-${from.month.toString().padLeft(2, '0')}'
      '-${from.day.toString().padLeft(2, '0')}';

  final rows = await client
      .from('attendance_records')
      .select('date, status')
      .inFilter('batch_id', ids)
      .gte('date', fromIso);

  final buckets = <DateTime, List<int>>{};
  for (var i = 3; i >= 0; i--) {
    buckets[mondayThisWeek.subtract(Duration(days: 7 * i))] = [0, 0];
  }
  for (final r in rows as List) {
    final m = r as Map<String, dynamic>;
    final d = DateTime.parse(m['date'] as String);
    final monday =
        DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
    final b = buckets[monday];
    if (b == null) continue;
    b[0]++;
    final s = m['status'] as String;
    if (s == 'present' || s == 'late') b[1]++;
  }
  return buckets.entries
      .map((e) => CoachWeeklyAttendance(
            weekStart: e.key,
            total: e.value[0],
            present: e.value[1],
          ))
      .toList(growable: false);
});

final myCoachStatsProvider = FutureProvider<CoachStats>((ref) async {
  final batches = await ref.watch(myBatchesProvider.future);
  final todays = await ref.watch(myTodaysBatchesProvider.future);
  if (batches.isEmpty) {
    return CoachStats(
        batchCount: 0, studentCount: 0, todaysCount: todays.length);
  }
  final client = ref.watch(supabaseClientProvider);
  final ids = batches.map((b) => b.id).toList();
  final rows = await client
      .from('batch_enrollments')
      .select('student_id')
      .inFilter('batch_id', ids)
      .eq('enrollment_status', 'active');
  final unique = <String>{};
  for (final r in rows as List) {
    unique.add((r as Map)['student_id'] as String);
  }
  return CoachStats(
    batchCount: batches.length,
    studentCount: unique.length,
    todaysCount: todays.length,
  );
});

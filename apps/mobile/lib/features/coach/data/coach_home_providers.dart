import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/coaches/data/coach.dart';

/// The coaches row owned by the signed-in user (via coaches.user_id =
/// auth.uid()). Returns null for non-coach roles or pre-link state.
final myCoachRecordProvider = FutureProvider<Coach?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final me = client.auth.currentUser?.id;
  if (me == null) return null;
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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';

/// One row per sport for the KPI dashboard.
class SportBreakdownRow {
  const SportBreakdownRow({
    required this.sportId,
    required this.sportName,
    required this.studentCount,
    required this.batchCount,
    required this.coachCount,
  });

  final String? sportId;
  final String sportName;
  final int studentCount;
  final int batchCount;
  final int coachCount;
}

/// Aggregates academy-scoped students / batches / coaches by sport. RLS on
/// the underlying tables already filters to the caller's academy, so we
/// just count what comes back. "Unassigned" rows (sport_id is null) are
/// rolled into a single bucket at the bottom.
final sportBreakdownProvider =
    FutureProvider<List<SportBreakdownRow>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final academyId = profile!.academyId!;

  // Pull the academy's sport list so we always render one row per enabled
  // sport even if the count is zero.
  final sportRows = await client
      .from('academy_sports')
      .select('sport:sport_id(id, name), custom_name')
      .eq('academy_id', academyId)
      .eq('is_active', true);

  final names = <String, String>{};
  for (final r in sportRows as List) {
    final m = r as Map;
    final sport = (m['sport'] as Map).cast<String, dynamic>();
    final id = sport['id'] as String;
    final custom = m['custom_name'] as String?;
    names[id] = (custom != null && custom.trim().isNotEmpty)
        ? custom.trim()
        : sport['name'] as String;
  }

  final students = await client
      .from('students')
      .select('sport_id')
      .eq('academy_id', academyId);
  final batches = await client
      .from('batches')
      .select('sport_id')
      .eq('academy_id', academyId)
      .eq('is_active', true);
  final coachSports = await client
      .from('coach_sports')
      .select('sport_id')
      .eq('academy_id', academyId);

  int countWith(List rows, String? sportId) {
    var n = 0;
    for (final r in rows) {
      if (((r as Map)['sport_id']) == sportId) n++;
    }
    return n;
  }

  final out = <SportBreakdownRow>[];
  for (final entry in names.entries) {
    out.add(SportBreakdownRow(
      sportId: entry.key,
      sportName: entry.value,
      studentCount: countWith(students as List, entry.key),
      batchCount: countWith(batches as List, entry.key),
      coachCount: countWith(coachSports as List, entry.key),
    ));
  }

  // Unassigned bucket — rows whose sport_id is null. Surfaced so the user
  // can see "I have 12 students with no sport — add their sport".
  final unassigned = SportBreakdownRow(
    sportId: null,
    sportName: 'Unassigned',
    studentCount: countWith(students, null),
    batchCount: countWith(batches, null),
    coachCount: 0,
  );
  if (unassigned.studentCount > 0 || unassigned.batchCount > 0) {
    out.add(unassigned);
  }

  out.sort((a, b) => b.studentCount.compareTo(a.studentCount));
  return out;
});

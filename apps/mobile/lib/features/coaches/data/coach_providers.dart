import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/coaches/data/coach.dart';

final coachesProvider = FutureProvider<List<Coach>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return [];

  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('coaches')
      .select()
      .eq('academy_id', academyId)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => Coach.fromMap(r as Map<String, dynamic>))
      .toList();
});

Future<Coach> createCoach(WidgetRef ref, Map<String, dynamic> data) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) {
    throw StateError('No academy linked to current user');
  }
  final row = await client
      .from('coaches')
      .insert({...data, 'academy_id': academyId})
      .select()
      .single();
  ref.invalidate(coachesProvider);
  return Coach.fromMap(row);
}

Future<Coach> updateCoach(
  WidgetRef ref,
  String coachId,
  Map<String, dynamic> patch,
) async {
  final client = ref.read(supabaseClientProvider);
  final row = await client
      .from('coaches')
      .update(patch)
      .eq('id', coachId)
      .select()
      .single();
  ref.invalidate(coachesProvider);
  return Coach.fromMap(row);
}

/// Helper: parse a comma-separated field into a clean list.
List<String> splitCsv(String input) {
  return input
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

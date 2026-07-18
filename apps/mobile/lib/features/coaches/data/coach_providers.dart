import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/coaches/data/coach.dart';
import 'package:playhub/features/subscription/data/subscription_providers.dart';
import 'package:playhub/features/subscription/data/trial_limits.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      .maybeSingle();
  // Null = blocked by RLS — center_admin / head_coach can only manage coaches
  // in their own center (can_manage_coach_record). Clean 42501 over PGRST116.
  if (row == null) {
    // Frozen subscription (writes off for everyone incl. owners) vs the
    // center-scope gate — same 0-row result. Name the plan one when it applies
    // so an owner whose trial lapsed doesn't see a wrong "own center" message.
    final paused =
        ref.read(mySubscriptionProvider).valueOrNull?.isBlocked ?? false;
    throw PostgrestException(
      message: paused
          ? "Your academy's plan is paused — renew it to add or edit records."
          : 'Create blocked by row-level security '
              '(you can only manage coaches in your own center).',
      code: '42501',
    );
  }
  ref
    ..invalidate(coachesProvider)
    ..invalidate(trialLimitsProvider); // refresh trial-cap counts
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
      .maybeSingle();
  // Null = UPDATE matched nothing under RLS — caller can't write this coach
  // (center_admin / head_coach limited to own center). Clean 42501 over PGRST116.
  if (row == null) {
    throw const PostgrestException(
      message: 'Update blocked by row-level security '
          '(you can only manage coaches in your own center).',
      code: '42501',
    );
  }
  ref.invalidate(coachesProvider);
  return Coach.fromMap(row);
}

/// Soft-delete a coach: flip `is_active` off rather than hard-deleting. A hard
/// delete would drop their documents + sport links and unassign their batches;
/// archiving keeps the record and is reversible. Coaches reference is kept so
/// historical attendance/performance rows (coach_id) stay attributed.
Future<void> archiveCoach(WidgetRef ref, String coachId) async {
  final client = ref.read(supabaseClientProvider);
  await client
      .from('coaches')
      .update({'is_active': false})
      .eq('id', coachId);
  ref.invalidate(coachesProvider);
}

/// Hard-deletes a coach record. Reserved for ROLLING BACK a coach just created
/// during a head_coach invite whose login step then failed — leaving it would
/// orphan the record and consume a trial coach-record slot. For a normal removal
/// use [archiveCoach] (soft); a hard delete drops the coach's sports/documents.
/// RLS (coaches_delete) limits this to admin / own-center scope.
Future<void> deleteCoachRecord(WidgetRef ref, String coachId) async {
  final client = ref.read(supabaseClientProvider);
  await client.from('coaches').delete().eq('id', coachId);
  ref
    ..invalidate(coachesProvider)
    ..invalidate(trialLimitsProvider);
}

/// Helper: parse a comma-separated field into a clean list.
List<String> splitCsv(String input) {
  return input
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

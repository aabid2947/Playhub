import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile.dart';

/// Fetches the current user's `public.users` row.
/// Refetched whenever the auth session changes, or when explicitly invalidated
/// (e.g. after `bootstrap_owner_academy`).
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;

  final client = ref.read(supabaseClientProvider);
  final row = await client
      .from('users')
      .select()
      .eq('id', session.user.id)
      .maybeSingle();

  if (row == null) return null;
  return Profile.fromMap(row);
});

/// The full set of centers the current user is scoped to: their PRIMARY
/// [Profile.centerId] plus any additional `user_centers` grants (a center_admin
/// may manage several centers — see migration 20260614000000_user_centers_multi).
///
/// An EMPTY set means "no center scoping" — academy-wide roles (owner/admin)
/// whose [Profile.centerId] is null and who hold no grants. Center-scoped roles
/// (center_admin / head_coach / coach) get a non-empty set. Callers should treat
/// an empty set as "do not filter by center".
///
/// RLS lets a user read their own `user_centers` rows (user_centers_read), so
/// this is a single self-scoped query.
final myCenterIdsProvider = FutureProvider<Set<String>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return <String>{};

  final ids = <String>{};
  if (profile.centerId != null) ids.add(profile.centerId!);

  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('user_centers')
      .select('center_id')
      .eq('user_id', profile.id);
  for (final r in rows as List) {
    final cid = (r as Map<String, dynamic>)['center_id'] as String?;
    if (cid != null) ids.add(cid);
  }
  return ids;
});

/// Calls the `bootstrap_owner_academy` Postgres function. Returns the
/// created (or already-existing) academy row. Caller is responsible for
/// invalidating [currentProfileProvider] after.
Future<dynamic> bootstrapOwnerAcademy(
  WidgetRef ref,
  String academyName,
) async {
  final client = ref.read(supabaseClientProvider);
  final result = await client.rpc<dynamic>(
    'bootstrap_owner_academy',
    params: {'p_academy_name': academyName},
  );
  ref.invalidate(currentProfileProvider);
  return result;
}

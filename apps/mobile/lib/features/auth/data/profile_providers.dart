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

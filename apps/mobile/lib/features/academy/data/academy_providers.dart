import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/academy/data/academy.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';

/// The current user's academy (null if super_admin or not yet bootstrapped).
final myAcademyProvider = FutureProvider<Academy?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return null;

  final client = ref.read(supabaseClientProvider);
  final row = await client
      .from('academies')
      .select()
      .eq('id', academyId)
      .maybeSingle();
  if (row == null) return null;
  return Academy.fromMap(row);
});

/// Patch fields on the current academy. Returns the updated row.
Future<Academy> updateMyAcademy(
  WidgetRef ref,
  Map<String, dynamic> patch,
) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) {
    throw StateError('No academy linked to current user');
  }
  final row = await client
      .from('academies')
      .update(patch)
      .eq('id', academyId)
      .select()
      .single();
  ref.invalidate(myAcademyProvider);
  return Academy.fromMap(row);
}

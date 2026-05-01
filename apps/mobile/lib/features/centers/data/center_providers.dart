import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/centers/data/center.dart';

final centersProvider = FutureProvider<List<Centre>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return [];

  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('centers')
      .select()
      .eq('academy_id', academyId)
      .order('created_at');
  return (rows as List)
      .map((r) => Centre.fromMap(r as Map<String, dynamic>))
      .toList();
});

Future<Centre> createCenter(WidgetRef ref, Map<String, dynamic> data) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) {
    throw StateError('No academy linked to current user');
  }
  final row = await client
      .from('centers')
      .insert({...data, 'academy_id': academyId})
      .select()
      .single();
  ref.invalidate(centersProvider);
  return Centre.fromMap(row);
}

Future<Centre> updateCenter(
  WidgetRef ref,
  String centerId,
  Map<String, dynamic> patch,
) async {
  final client = ref.read(supabaseClientProvider);
  final row = await client
      .from('centers')
      .update(patch)
      .eq('id', centerId)
      .select()
      .single();
  ref.invalidate(centersProvider);
  return Centre.fromMap(row);
}

Future<void> deactivateCenter(WidgetRef ref, String centerId) async {
  final client = ref.read(supabaseClientProvider);
  await client
      .from('centers')
      .update({'is_active': false})
      .eq('id', centerId);
  ref.invalidate(centersProvider);
}

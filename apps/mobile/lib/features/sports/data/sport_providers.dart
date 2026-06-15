import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/sports/data/sport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Full global catalog. Used by Settings → Sports for the "add a sport"
/// picker; everywhere else uses one of the academy/center providers.
final allSportsProvider = FutureProvider<List<Sport>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('sports')
      .select()
      .eq('is_active', true)
      .order('name');
  return (rows as List)
      .map((r) => Sport.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

/// Every active center_sports row across all centers in the user's
/// academy. The fallback list when a form/filter has no specific center
/// scope (e.g. fee_structures, leads with no preferred_center).
final academyCenterSportsProvider =
    FutureProvider<List<CenterSport>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('center_sports')
      .select(
          'id, academy_id, center_id, custom_name, is_active, sport:sport_id(id, code, name, category, is_active)')
      .eq('academy_id', profile!.academyId!)
      .eq('is_active', true);
  return (rows as List)
      .map((r) => CenterSport.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

/// Active center_sports rows for one center.
final centerSportsProvider =
    FutureProvider.family<List<CenterSport>, String>((ref, centerId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('center_sports')
      .select(
          'id, academy_id, center_id, custom_name, is_active, sport:sport_id(id, code, name, category, is_active)')
      .eq('center_id', centerId)
      .eq('is_active', true)
      .order('created_at');
  return (rows as List)
      .map((r) => CenterSport.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

/// Per-sport skill catalog. Used by the performance assessment skill
/// picker. Empty when [sportId] is null.
final sportSkillsProvider =
    FutureProvider.family<List<SportSkill>, String?>((ref, sportId) async {
  if (sportId == null) return const [];
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('sport_skills')
      .select()
      .eq('sport_id', sportId)
      .order('sort_order');
  return (rows as List)
      .map((r) => SportSkill.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

final coachSportsProvider =
    FutureProvider.family<List<String>, String>((ref, coachId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('coach_sports')
      .select('sport_id')
      .eq('coach_id', coachId);
  return (rows as List)
      .map((r) => (r as Map)['sport_id'] as String)
      .toList(growable: false);
});

class SportsRepo {
  SportsRepo(this._client, this._academyId);
  final SupabaseClient _client;
  final String _academyId;

  /// Creates an academy-scoped custom sport (academy_id = this academy) so a
  /// center_admin can coin a sport that isn't in the global catalog. The `code`
  /// is a slug of the name, unique within the academy (RLS + the partial unique
  /// index enforce both). Returns the new catalog row to enable at a center.
  Future<Sport> createCustomSport({
    required String name,
    String? category,
  }) async {
    final trimmed = name.trim();
    var code = trimmed
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (code.isEmpty) code = 'sport';
    final r = await _client
        .from('sports')
        .insert({
          'academy_id': _academyId,
          'code': code,
          'name': trimmed,
          'category': category,
        })
        .select()
        .single();
    return Sport.fromMap(r);
  }

  Future<void> enableSportAtCenter({
    required String centerId,
    required String sportId,
    String? customName,
  }) =>
      _client.from('center_sports').insert({
        'academy_id': _academyId,
        'center_id': centerId,
        'sport_id': sportId,
        'custom_name': customName,
      });

  Future<void> updateCenterSport(
    String id, {
    String? customName,
    bool? isActive,
  }) =>
      _client.from('center_sports').update({
        if (customName != null) 'custom_name': customName,
        if (isActive != null) 'is_active': isActive,
      }).eq('id', id);

  Future<void> disableCenterSport(String id) =>
      _client.from('center_sports').delete().eq('id', id);

  /// Replaces the coach's sport list with [sportIds]. Diffs current vs new
  /// so we only insert / delete rows that actually changed.
  Future<void> setCoachSports(String coachId, List<String> sportIds) async {
    final existing = await _client
        .from('coach_sports')
        .select('id, sport_id')
        .eq('coach_id', coachId);
    final current = <String, String>{
      for (final r in existing as List)
        (r as Map)['sport_id'] as String: r['id'] as String,
    };
    final desired = sportIds.toSet();

    final toAdd = desired.where((s) => !current.containsKey(s));
    final toRemove = current.entries.where((e) => !desired.contains(e.key));

    if (toAdd.isNotEmpty) {
      await _client.from('coach_sports').insert([
        for (final sid in toAdd)
          {
            'academy_id': _academyId,
            'coach_id': coachId,
            'sport_id': sid,
          },
      ]);
    }
    for (final e in toRemove) {
      await _client.from('coach_sports').delete().eq('id', e.value);
    }
  }
}

final sportsRepoProvider = FutureProvider<SportsRepo?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return null;
  return SportsRepo(ref.watch(supabaseClientProvider), profile!.academyId!);
});

/// Resolves a sport_id to a display name.
///
/// Returns the first matching center's `custom_name` (or catalog name)
/// across the user's academy. Returns "—" when sportId is null.
final sportDisplayProvider = Provider.family<String, ({String? sportId})>(
  (ref, args) {
    final id = args.sportId;
    if (id == null) return '—';
    final list = ref.watch(academyCenterSportsProvider).valueOrNull ?? const [];
    for (final s in list) {
      if (s.sport.id == id) return s.displayName;
    }
    final all = ref.watch(allSportsProvider).valueOrNull ?? const [];
    for (final s in all) {
      if (s.id == id) return s.name;
    }
    return '—';
  },
);

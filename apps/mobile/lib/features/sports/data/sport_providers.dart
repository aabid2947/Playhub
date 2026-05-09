import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/sports/data/sport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Full global catalog. Used by Settings → Sports for the "add a sport"
/// picker; everywhere else uses `academySportsProvider`.
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

/// Sports the current user's academy has enabled. Source of truth for
/// every "pick a sport" dropdown in the app.
final academySportsProvider =
    FutureProvider<List<AcademySport>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('academy_sports')
      .select('id, academy_id, custom_name, is_active, sport:sport_id(id, code, name, category, is_active)')
      .eq('academy_id', profile!.academyId!)
      .eq('is_active', true)
      .order('created_at');
  return (rows as List)
      .map((r) => AcademySport.fromMap(r as Map<String, dynamic>))
      .toList(growable: false)
    ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
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

  Future<void> enableSport(String sportId, {String? customName}) =>
      _client.from('academy_sports').insert({
        'academy_id': _academyId,
        'sport_id': sportId,
        'custom_name': customName,
      });

  Future<void> updateAcademySport(
    String id, {
    String? customName,
    bool? isActive,
  }) =>
      _client.from('academy_sports').update({
        if (customName != null) 'custom_name': customName,
        if (isActive != null) 'is_active': isActive,
      }).eq('id', id);

  Future<void> disableAcademySport(String id) =>
      _client.from('academy_sports').delete().eq('id', id);

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
/// Returns the academy's `custom_name` when set, the catalog name when the
/// sport isn't enabled locally, or "—" when sportId is null.
final sportDisplayProvider = Provider.family<String, ({String? sportId})>(
  (ref, args) {
    final id = args.sportId;
    if (id == null) return '—';
    final list = ref.watch(academySportsProvider).valueOrNull ?? const [];
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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/leads/data/lead.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final leadsListProvider = FutureProvider<List<Lead>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('leads')
      .select()
      .eq('academy_id', profile!.academyId!)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => Lead.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

final leadByIdProvider = FutureProvider.family<Lead?, String>((ref, id) async {
  final client = ref.watch(supabaseClientProvider);
  final r = await client.from('leads').select().eq('id', id).maybeSingle();
  return r == null ? null : Lead.fromMap(r);
});

final leadActivitiesProvider =
    FutureProvider.family<List<LeadActivity>, String>((ref, leadId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('lead_activities')
      .select()
      .eq('lead_id', leadId)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => LeadActivity.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

class LeadsRepo {
  LeadsRepo(this._client, this._academyId);
  final SupabaseClient _client;
  final String _academyId;

  Future<Lead> create({
    required String firstName,
    String? lastName,
    String? email,
    String? phone,
    String? parentName,
    int? age,
    String? sportId,
    String? preferredCenterId,
    LeadSource source = LeadSource.walkIn,
    String? notes,
  }) async {
    final r = await _client
        .from('leads')
        .insert({
          'academy_id': _academyId,
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'phone': phone,
          'parent_name': parentName,
          'age': age,
          'sport_id': sportId,
          'preferred_center_id': preferredCenterId,
          'notes': notes,
          'source': source.dbValue,
        })
        .select()
        .single();
    return Lead.fromMap(r);
  }

  Future<void> updateStatus(String leadId, LeadStatus status) async {
    await _client
        .from('leads')
        .update({'status': status.dbValue})
        .eq('id', leadId);
  }

  Future<void> assignTo(String leadId, String? userId) async {
    await _client
        .from('leads')
        .update({'assigned_to': userId})
        .eq('id', leadId);
  }

  Future<void> scheduleFollowup(String leadId, DateTime when) async {
    await _client.from('leads').update(
      {'next_followup_at': when.toUtc().toIso8601String()},
    ).eq('id', leadId);
  }

  Future<void> scheduleTrial(String leadId, DateTime when) async {
    await _client.from('leads').update({
      'trial_scheduled_at': when.toUtc().toIso8601String(),
      'status': LeadStatus.trialScheduled.dbValue,
    }).eq('id', leadId);

    await _client.from('lead_activities').insert({
      'academy_id': _academyId,
      'lead_id': leadId,
      'kind': 'trial_scheduled',
      'content': 'Trial scheduled for ${when.toLocal()}',
      'metadata': {'scheduled_at': when.toUtc().toIso8601String()},
    });
  }

  Future<void> addNote(String leadId, String content) async {
    await _client.from('lead_activities').insert({
      'academy_id': _academyId,
      'lead_id': leadId,
      'kind': 'note',
      'content': content,
    });
  }

  Future<void> logCall(String leadId, String content) async {
    await _client.from('lead_activities').insert({
      'academy_id': _academyId,
      'lead_id': leadId,
      'kind': 'call_logged',
      'content': content,
    });
  }

  Future<String> convert({
    required String leadId,
    String? batchId,
    String? parentUserId,
    DateTime? startDate,
  }) async {
    final res = await _client.functions.invoke(
      'convert-lead-to-student',
      body: {
        'lead_id': leadId,
        if (batchId != null) 'batch_id': batchId,
        if (parentUserId != null) 'parent_user_id': parentUserId,
        if (startDate != null)
          'start_date':
              '${startDate.year.toString().padLeft(4, '0')}'
              '-${startDate.month.toString().padLeft(2, '0')}'
              '-${startDate.day.toString().padLeft(2, '0')}',
      },
    );
    final body = res.data as Map<String, dynamic>;
    if (body['ok'] == true) return body['student_id'] as String;
    throw StateError(body['error']?.toString() ?? 'convert failed');
  }
}

final leadsRepoProvider = FutureProvider<LeadsRepo?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return null;
  return LeadsRepo(ref.watch(supabaseClientProvider), profile!.academyId!);
});

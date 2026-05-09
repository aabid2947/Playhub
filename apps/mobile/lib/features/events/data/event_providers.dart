import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final eventsListProvider = FutureProvider<List<EventEntry>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('events')
      .select()
      .eq('academy_id', profile!.academyId!)
      .order('starts_at', ascending: false);
  return (rows as List)
      .map((r) => EventEntry.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

final eventByIdProvider =
    FutureProvider.family<EventEntry?, String>((ref, id) async {
  final client = ref.watch(supabaseClientProvider);
  final r = await client.from('events').select().eq('id', id).maybeSingle();
  return r == null ? null : EventEntry.fromMap(r);
});

final eventRegistrationsProvider =
    FutureProvider.family<List<EventRegistration>, String>((ref, eventId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('event_registrations')
      .select()
      .eq('event_id', eventId)
      .order('registered_at');
  return (rows as List)
      .map((r) => EventRegistration.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

final eventResultsProvider =
    FutureProvider.family<List<EventResult>, String>((ref, eventId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('event_results')
      .select()
      .eq('event_id', eventId)
      .order('placement', ascending: true, nullsFirst: false);
  return (rows as List)
      .map((r) => EventResult.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

/// Events the parent's linked students are registered for.
final myStudentsEventRegsProvider =
    FutureProvider<List<EventRegistration>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile == null) return const [];

  // Use the my_linked_student_ids() helper for parents/students; admins get
  // an empty list here (they should use eventsListProvider directly).
  final ids = await client.rpc('my_linked_student_ids');
  final list = (ids as List?)?.cast<String>() ?? const <String>[];
  if (list.isEmpty) return const [];

  final rows = await client
      .from('event_registrations')
      .select()
      .inFilter('student_id', list)
      .order('registered_at', ascending: false);
  return (rows as List)
      .map((r) => EventRegistration.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

class EventsRepo {
  EventsRepo(this._client, this._academyId);
  final SupabaseClient _client;
  final String _academyId;

  Future<EventEntry> create({
    required String title,
    required EventKind kind,
    required DateTime startsAt,
    String? description,
    String? sportId,
    DateTime? endsAt,
    String? location,
    String? centerId,
    DateTime? registrationOpensAt,
    DateTime? registrationClosesAt,
    int? capacity,
    double feeAmount = 0,
    List<String> eligibleBatchIds = const [],
    EventStatus status = EventStatus.draft,
  }) async {
    final r = await _client
        .from('events')
        .insert({
          'academy_id': _academyId,
          'center_id': centerId,
          'title': title,
          'description': description,
          'kind': kind.dbValue,
          'status': status.dbValue,
          'sport_id': sportId,
          'starts_at': startsAt.toUtc().toIso8601String(),
          if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
          'location': location,
          if (registrationOpensAt != null)
            'registration_opens_at': registrationOpensAt.toUtc().toIso8601String(),
          if (registrationClosesAt != null)
            'registration_closes_at':
                registrationClosesAt.toUtc().toIso8601String(),
          'capacity': capacity,
          'fee_amount': feeAmount,
          'eligible_batch_ids': eligibleBatchIds,
        })
        .select()
        .single();
    return EventEntry.fromMap(r);
  }

  Future<void> updateStatus(String id, EventStatus status) =>
      _client.from('events').update({'status': status.dbValue}).eq('id', id);

  Future<void> deleteEvent(String id) =>
      _client.from('events').delete().eq('id', id);

  Future<EventRegistration> register({
    required String eventId,
    required String studentId,
    String? notes,
  }) async {
    final r = await _client
        .from('event_registrations')
        .insert({
          'academy_id': _academyId,
          'event_id': eventId,
          'student_id': studentId,
          'notes': notes,
        })
        .select()
        .single();
    return EventRegistration.fromMap(r);
  }

  Future<void> cancelRegistration(String regId) =>
      _client.from('event_registrations').update({
        'status': 'cancelled',
        'cancelled_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', regId);

  Future<void> markAttended(String regId) =>
      _client.from('event_registrations').update({
        'status': 'attended',
      }).eq('id', regId);

  Future<EventResult> recordResult({
    required String eventId,
    required String studentId,
    String? registrationId,
    int? placement,
    double? score,
    String? category,
    String? remarks,
  }) async {
    final r = await _client
        .from('event_results')
        .upsert({
          'academy_id': _academyId,
          'event_id': eventId,
          'student_id': studentId,
          if (registrationId != null) 'registration_id': registrationId,
          'placement': placement,
          'score': score,
          'category': category,
          'remarks': remarks,
        }, onConflict: 'event_id,student_id,category')
        .select()
        .single();
    return EventResult.fromMap(r);
  }

  /// Calls `generate-certificate-pdf` and returns the signed URL.
  Future<String> generateCertificate(String resultId) async {
    final res = await _client.functions.invoke(
      'generate-certificate-pdf',
      body: {'result_id': resultId},
    );
    final body = res.data as Map<String, dynamic>;
    if (body['ok'] == true) return body['signed_url'] as String;
    throw StateError(body['error']?.toString() ?? 'certificate failed');
  }
}

final eventsRepoProvider = FutureProvider<EventsRepo?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return null;
  return EventsRepo(ref.watch(supabaseClientProvider), profile!.academyId!);
});

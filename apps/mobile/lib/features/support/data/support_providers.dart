import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart'
    show SupportTicketRow, TicketMessage;
import 'package:supabase_flutter/supabase_flutter.dart';

final myAcademyTicketsProvider =
    FutureProvider<List<SupportTicketRow>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('support_tickets')
      .select()
      .eq('academy_id', profile!.academyId!)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => SupportTicketRow.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

class SupportRepo {
  SupportRepo(this._client, this._academyId);
  final SupabaseClient _client;
  final String _academyId;

  Future<SupportTicketRow> createTicket({
    required String subject,
    required String body,
    String? category,
    String priority = 'normal',
  }) async {
    final r = await _client
        .from('support_tickets')
        .insert({
          'academy_id': _academyId,
          'subject': subject,
          'body': body,
          'category': category,
          'priority': priority,
        })
        .select()
        .single();
    return SupportTicketRow.fromMap(r);
  }

  /// Mark a ticket's status (owner/admin only — RLS rejects other roles, so the
  /// UI hides the action for center_admin). Stamps resolved_at / closed_at to
  /// match the status. Used by the academy-side "Mark resolved" action.
  Future<void> setStatus({
    required String ticketId,
    required String status,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await _client.from('support_tickets').update({
      'status': status,
      if (status == 'resolved') 'resolved_at': nowIso,
      if (status == 'closed') 'closed_at': nowIso,
    }).eq('id', ticketId);
  }

  Future<TicketMessage> postReply({
    required String ticketId,
    required String body,
  }) async {
    final r = await _client
        .from('support_ticket_messages')
        .insert({
          'ticket_id': ticketId,
          'academy_id': _academyId,
          'body': body,
          'is_staff': false,
        })
        .select()
        .single();
    return TicketMessage.fromMap(r);
  }
}

final supportRepoProvider = FutureProvider<SupportRepo?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return null;
  return SupportRepo(ref.watch(supabaseClientProvider), profile!.academyId!);
});

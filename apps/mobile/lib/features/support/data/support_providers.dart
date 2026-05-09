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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/chat/data/chat.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Threads the calling user can see (admin sees all in academy via RLS;
/// other roles see threads they participate in).
final myThreadsProvider = FutureProvider<List<MessageThread>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return const [];
  // Threads I participate in.
  final partRows = await client
      .from('thread_participants')
      .select('thread_id')
      .eq('user_id', user.id);
  final ids = (partRows as List)
      .map((r) => (r as Map)['thread_id'] as String)
      .toList(growable: false);
  if (ids.isEmpty) return const [];
  final rows = await client
      .from('message_threads')
      .select()
      .inFilter('id', ids)
      .order('last_message_at', ascending: false, nullsFirst: false);
  return (rows as List)
      .map((r) => MessageThread.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

/// Realtime stream of messages for a thread (oldest first).
final threadMessagesProvider =
    StreamProvider.family<List<Message>, String>((ref, threadId) {
  final client = ref.watch(supabaseClientProvider);
  return client
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('thread_id', threadId)
      .order('created_at')
      .map((rows) => rows
          .map((r) => Message.fromMap(r))
          .where((m) => m.deletedAt == null)
          .toList(growable: false));
});

class ChatRepo {
  ChatRepo(this._client, this._academyId);
  final SupabaseClient _client;
  final String _academyId;

  /// Lazy-create a 1:1 thread with another user; returns thread id.
  Future<String> ensureDirectThread(String otherUserId) async {
    final id = await _client.rpc(
      'ensure_direct_thread',
      params: {'p_other_user_id': otherUserId},
    );
    return id as String;
  }

  Future<String> ensureBatchThread(String batchId) async {
    final id = await _client.rpc(
      'ensure_batch_thread',
      params: {'p_batch_id': batchId},
    );
    return id as String;
  }

  Future<void> send(
    String threadId,
    String content, {
    List<String> attachments = const [],
  }) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw StateError('not authenticated');
    await _client.from('messages').insert({
      'thread_id': threadId,
      'academy_id': _academyId,
      'sender_id': me,
      'content': content,
      'attachments': attachments,
    });
  }

  /// Coach/admin batch broadcast — fans out push + notifications via
  /// the broadcast-message Edge Function.
  Future<void> broadcastToBatch(String batchId, String content) async {
    final res = await _client.functions.invoke('broadcast-message', body: {
      'batch_id': batchId,
      'content': content,
    });
    final body = res.data as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw StateError(body['error']?.toString() ?? 'broadcast failed');
    }
  }

  Future<void> markRead(String threadId) async {
    await _client.rpc('mark_thread_read', params: {'p_thread_id': threadId});
  }
}

final chatRepoProvider = FutureProvider<ChatRepo?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return null;
  return ChatRepo(ref.watch(supabaseClientProvider), profile!.academyId!);
});

/// Display-name lookup for a user id (for direct-thread headers).
final userDisplayNameProvider =
    FutureProvider.family<String, String>((ref, userId) async {
  final client = ref.watch(supabaseClientProvider);
  final r = await client
      .from('users')
      .select('first_name, last_name, email')
      .eq('id', userId)
      .maybeSingle();
  if (r == null) return '(unknown)';
  final first = (r['first_name'] as String?) ?? '';
  final last = (r['last_name'] as String?) ?? '';
  final full = '$first $last'.trim();
  if (full.isNotEmpty) return full;
  return (r['email'] as String?) ?? '(unknown)';
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/announcements/data/announcement.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// All announcements visible to the current user (admin sees full history,
/// other roles see whatever the academy_id-scoped read policy returns).
final announcementsListProvider =
    FutureProvider<List<Announcement>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('announcements')
      .select()
      .eq('academy_id', profile!.academyId!)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => Announcement.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

/// The audience-filtered feed for the current user — joins recipients to
/// only show announcements actually targeted at them. Carries read_at so
/// the UI can show unread badges.
class AnnouncementFeedItem {
  const AnnouncementFeedItem({
    required this.announcement,
    required this.recipientId,
    this.readAt,
  });
  final Announcement announcement;
  final String recipientId;
  final DateTime? readAt;
}

final announcementFeedProvider =
    FutureProvider<List<AnnouncementFeedItem>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return const [];
  final rows = await client
      .from('announcement_recipients')
      .select('id, read_at, announcements(*)')
      .eq('user_id', user.id)
      .order('delivered_at', ascending: false);
  return (rows as List).map((r) {
    final m = r as Map<String, dynamic>;
    final ann = Announcement.fromMap(
      (m['announcements'] as Map).cast<String, dynamic>(),
    );
    return AnnouncementFeedItem(
      announcement: ann,
      recipientId: m['id'] as String,
      readAt: m['read_at'] == null
          ? null
          : DateTime.parse(m['read_at'] as String).toLocal(),
    );
  }).toList(growable: false);
});

class AnnouncementsRepo {
  AnnouncementsRepo(this._client, this._academyId);
  final SupabaseClient _client;
  final String _academyId;

  Future<Announcement> draft({
    required String subject,
    required String body,
    List<String> targetRoles = const [],
    List<String> targetBatches = const [],
    List<String> targetCenters = const [],
    bool viaPush = true,
    bool viaEmail = false,
    bool viaInApp = true,
    DateTime? scheduledFor,
  }) async {
    final r = await _client
        .from('announcements')
        .insert({
          'academy_id': _academyId,
          'subject': subject,
          'body': body,
          'target_roles': targetRoles,
          'target_batches': targetBatches,
          'target_centers': targetCenters,
          'via_push': viaPush,
          'via_email': viaEmail,
          'via_in_app': viaInApp,
          if (scheduledFor != null)
            'scheduled_for': scheduledFor.toUtc().toIso8601String(),
          'created_by': _client.auth.currentUser?.id,
        })
        .select()
        .single();
    return Announcement.fromMap(r);
  }

  /// Calls the send-announcement Edge Function which fans out push + email
  /// + in-app and sets sent_at/sent_count/failed_count.
  Future<void> sendNow(String announcementId) async {
    final res = await _client.functions.invoke(
      'send-announcement',
      body: {'announcement_id': announcementId},
    );
    final body = res.data as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw StateError(body['error']?.toString() ?? 'send failed');
    }
  }

  Future<void> markRead(String announcementId) async {
    await _client.rpc('mark_announcement_read',
        params: {'p_announcement_id': announcementId});
  }
}

final announcementsRepoProvider =
    FutureProvider<AnnouncementsRepo?>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return null;
  return AnnouncementsRepo(
    ref.watch(supabaseClientProvider),
    profile!.academyId!,
  );
});

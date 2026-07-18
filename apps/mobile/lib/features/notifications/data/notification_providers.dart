import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/notifications/data/notification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Realtime stream — drives the bell badge live.
final notificationsStreamProvider =
    StreamProvider<List<AppNotification>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  final client = ref.watch(supabaseClientProvider);
  if (userId == null) return const Stream<List<AppNotification>>.empty();
  return client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .order('created_at')
      .map((rows) {
        final list =
            rows.map(AppNotification.fromMap).toList(growable: false);
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  final async = ref.watch(notificationsStreamProvider);
  return async.maybeWhen(
    data: (list) => list.where((n) => n.isUnread).length,
    orElse: () => 0,
  );
});

final notificationPreferencesProvider =
    FutureProvider<List<NotificationPreference>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  final client = ref.watch(supabaseClientProvider);
  if (userId == null) return const [];
  final rows = await client
      .from('notification_preferences')
      .select()
      .eq('user_id', userId);
  return (rows as List)
      .map((r) => NotificationPreference.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

class NotificationsRepo {
  NotificationsRepo(this._client);
  final SupabaseClient _client;

  Future<void> markRead(String id) =>
      _client.rpc('mark_notification_read', params: {'p_id': id});

  Future<int> markAllRead() async {
    final r = await _client.rpc('mark_all_notifications_read');
    return (r as num?)?.toInt() ?? 0;
  }

  Future<void> setPreference({
    required String category,
    required String channel,
    required bool enabled,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.from('notification_preferences').upsert({
      'user_id': user.id,
      'category': category,
      'channel': channel,
      'enabled': enabled,
    }, onConflict: 'user_id,category,channel');
  }

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    String? deviceId,
    String? appVersion,
  }) =>
      _client.rpc('register_device_token', params: {
        'p_token': token,
        'p_platform': platform,
        'p_device_id': deviceId,
        'p_app_version': appVersion,
      });
}

final notificationsRepoProvider = Provider<NotificationsRepo>(
    (ref) => NotificationsRepo(ref.watch(supabaseClientProvider)));

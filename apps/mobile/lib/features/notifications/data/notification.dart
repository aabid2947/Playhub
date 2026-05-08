class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.academyId,
    required this.category,
    required this.title,
    required this.createdAt,
    this.body,
    this.deepLink,
    this.entityType,
    this.entityId,
    this.readAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        academyId: m['academy_id'] as String,
        category: m['category'] as String,
        title: m['title'] as String,
        body: m['body'] as String?,
        deepLink: m['deep_link'] as String?,
        entityType: m['entity_type'] as String?,
        entityId: m['entity_id'] as String?,
        readAt: m['read_at'] == null
            ? null
            : DateTime.parse(m['read_at'] as String).toLocal(),
        createdAt:
            DateTime.parse(m['created_at'] as String).toLocal(),
      );

  final String id;
  final String userId;
  final String academyId;
  final String category;
  final String title;
  final String? body;
  final String? deepLink;
  final String? entityType;
  final String? entityId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;
}

class NotificationPreference {
  const NotificationPreference({
    required this.id,
    required this.userId,
    required this.category,
    required this.channel,
    required this.enabled,
    this.academyId,
  });

  factory NotificationPreference.fromMap(Map<String, dynamic> m) =>
      NotificationPreference(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        academyId: m['academy_id'] as String?,
        category: m['category'] as String,
        channel: m['channel'] as String,
        enabled: m['enabled'] as bool,
      );

  final String id;
  final String userId;
  final String? academyId;
  final String category;
  final String channel;
  final bool enabled;
}

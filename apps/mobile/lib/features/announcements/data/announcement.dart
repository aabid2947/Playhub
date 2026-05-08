class Announcement {
  const Announcement({
    required this.id,
    required this.academyId,
    required this.subject,
    required this.body,
    required this.createdAt,
    this.bodyHtml,
    this.targetRoles = const [],
    this.targetBatches = const [],
    this.targetCenters = const [],
    this.viaPush = true,
    this.viaEmail = false,
    this.viaInApp = true,
    this.scheduledFor,
    this.sentAt,
    this.sentCount,
    this.failedCount,
    this.createdBy,
  });

  factory Announcement.fromMap(Map<String, dynamic> m) {
    List<String> arr(dynamic v) =>
        (v as List?)?.map((e) => e.toString()).toList() ?? const [];
    return Announcement(
      id: m['id'] as String,
      academyId: m['academy_id'] as String,
      subject: m['subject'] as String,
      body: m['body'] as String,
      bodyHtml: m['body_html'] as String?,
      targetRoles: arr(m['target_roles']),
      targetBatches: arr(m['target_batches']),
      targetCenters: arr(m['target_centers']),
      viaPush: m['via_push'] as bool? ?? true,
      viaEmail: m['via_email'] as bool? ?? false,
      viaInApp: m['via_in_app'] as bool? ?? true,
      scheduledFor: _ts(m['scheduled_for']),
      sentAt: _ts(m['sent_at']),
      sentCount: m['sent_count'] as int?,
      failedCount: m['failed_count'] as int?,
      createdBy: m['created_by'] as String?,
      createdAt: _ts(m['created_at']) ?? DateTime.now(),
    );
  }

  static DateTime? _ts(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  final String id;
  final String academyId;
  final String subject;
  final String body;
  final String? bodyHtml;
  final List<String> targetRoles;
  final List<String> targetBatches;
  final List<String> targetCenters;
  final bool viaPush;
  final bool viaEmail;
  final bool viaInApp;
  final DateTime? scheduledFor;
  final DateTime? sentAt;
  final int? sentCount;
  final int? failedCount;
  final String? createdBy;
  final DateTime createdAt;

  bool get isDraft => sentAt == null;
}

class AnnouncementRecipient {
  const AnnouncementRecipient({
    required this.id,
    required this.announcementId,
    required this.userId,
    required this.deliveredAt,
    this.readAt,
  });

  factory AnnouncementRecipient.fromMap(Map<String, dynamic> m) =>
      AnnouncementRecipient(
        id: m['id'] as String,
        announcementId: m['announcement_id'] as String,
        userId: m['user_id'] as String,
        deliveredAt:
            DateTime.parse(m['delivered_at'] as String).toLocal(),
        readAt: m['read_at'] == null
            ? null
            : DateTime.parse(m['read_at'] as String).toLocal(),
      );

  final String id;
  final String announcementId;
  final String userId;
  final DateTime deliveredAt;
  final DateTime? readAt;
}

import 'package:playhub/features/chat/data/attachment.dart';

enum ThreadKind {
  direct('direct'),
  batch('batch');

  const ThreadKind(this.dbValue);
  final String dbValue;

  static ThreadKind fromDb(String? v) =>
      v == 'batch' ? ThreadKind.batch : ThreadKind.direct;
}

class MessageThread {
  const MessageThread({
    required this.id,
    required this.academyId,
    required this.kind,
    required this.createdAt,
    this.title,
    this.directUserA,
    this.directUserB,
    this.batchId,
    this.lastMessageAt,
    this.lastMessagePreview,
  });

  factory MessageThread.fromMap(Map<String, dynamic> m) => MessageThread(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        kind: ThreadKind.fromDb(m['kind'] as String?),
        title: m['title'] as String?,
        directUserA: m['direct_user_a'] as String?,
        directUserB: m['direct_user_b'] as String?,
        batchId: m['batch_id'] as String?,
        lastMessageAt: _ts(m['last_message_at']),
        lastMessagePreview: m['last_message_preview'] as String?,
        createdAt: _ts(m['created_at']) ?? DateTime.now(),
      );

  static DateTime? _ts(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  final String id;
  final String academyId;
  final ThreadKind kind;
  final String? title;
  final String? directUserA;
  final String? directUserB;
  final String? batchId;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final DateTime createdAt;

  String? otherUserId(String me) {
    if (kind != ThreadKind.direct) return null;
    if (directUserA == me) return directUserB;
    if (directUserB == me) return directUserA;
    return null;
  }
}

class Message {
  const Message({
    required this.id,
    required this.threadId,
    required this.academyId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.attachments = const [],
    this.editedAt,
    this.deletedAt,
  });

  factory Message.fromMap(Map<String, dynamic> m) => Message(
        id: m['id'] as String,
        threadId: m['thread_id'] as String,
        academyId: m['academy_id'] as String,
        senderId: m['sender_id'] as String,
        content: m['content'] as String? ?? '',
        attachments: ((m['attachments'] as List?) ?? const [])
            .map((e) => ChatAttachment.fromAny(e as Object))
            .toList(growable: false),
        editedAt: _ts(m['edited_at']),
        deletedAt: _ts(m['deleted_at']),
        createdAt: _ts(m['created_at']) ?? DateTime.now(),
      );

  static DateTime? _ts(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  final String id;
  final String threadId;
  final String academyId;
  final String senderId;
  final String content;
  final List<ChatAttachment> attachments;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final DateTime createdAt;
}

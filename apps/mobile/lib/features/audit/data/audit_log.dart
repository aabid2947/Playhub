class AuditLog {
  const AuditLog({
    required this.id,
    required this.action,
    required this.entityType,
    required this.createdAt,
    this.academyId,
    this.userId,
    this.entityId,
    this.before,
    this.after,
    this.userFirstName,
    this.userLastName,
  });

  factory AuditLog.fromMap(Map<String, dynamic> m) => AuditLog(
        id: m['id'] as String,
        academyId: m['academy_id'] as String?,
        userId: m['user_id'] as String?,
        action: m['action'] as String,
        entityType: m['entity_type'] as String,
        entityId: m['entity_id'] as String?,
        before: m['before'] as Map<String, dynamic>?,
        after: m['after'] as Map<String, dynamic>?,
        createdAt: DateTime.parse(m['created_at'] as String),
        userFirstName: (m['users'] as Map?)?['first_name'] as String?,
        userLastName: (m['users'] as Map?)?['last_name'] as String?,
      );

  final String id;
  final String? academyId;
  final String? userId;
  final String action; // 'insert' | 'update' | 'delete'
  final String entityType;
  final String? entityId;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final DateTime createdAt;
  final String? userFirstName;
  final String? userLastName;

  String get userDisplay {
    final name = [userFirstName ?? '', userLastName ?? '']
        .where((s) => s.isNotEmpty)
        .join(' ');
    if (name.isNotEmpty) return name;
    if (userId != null) return userId!.substring(0, 8);
    return 'system';
  }

  /// Human-readable name for the entity (e.g. for students: "Aarav A").
  String? get entitySubject {
    final m = after ?? before;
    if (m == null) return null;
    final fn = m['first_name'] as String?;
    final ln = m['last_name'] as String?;
    if (fn != null) return '$fn ${ln ?? ''}'.trim();
    return m['name'] as String?;
  }

  /// For UPDATE actions, returns the keys whose values changed.
  List<String> get changedFields {
    if (action != 'update' || before == null || after == null) return const [];
    final keys = <String>{...before!.keys, ...after!.keys};
    return keys
        .where((k) => before![k]?.toString() != after![k]?.toString())
        .where((k) => k != 'updated_at') // noisy
        .toList()
      ..sort();
  }
}

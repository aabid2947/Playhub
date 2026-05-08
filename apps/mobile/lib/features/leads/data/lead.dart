enum LeadStatus {
  newLead('new', 'New'),
  contacted('contacted', 'Contacted'),
  interested('interested', 'Interested'),
  trialScheduled('trial_scheduled', 'Trial scheduled'),
  converted('converted', 'Converted'),
  lost('lost', 'Lost');

  const LeadStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static LeadStatus fromDb(String? v) {
    for (final s in values) {
      if (s.dbValue == v) return s;
    }
    return LeadStatus.newLead;
  }

  static const kanbanOrder = [
    LeadStatus.newLead,
    LeadStatus.contacted,
    LeadStatus.interested,
    LeadStatus.trialScheduled,
    LeadStatus.converted,
    LeadStatus.lost,
  ];
}

enum LeadSource {
  website('website', 'Website'),
  referral('referral', 'Referral'),
  walkIn('walk_in', 'Walk-in'),
  instagram('instagram', 'Instagram'),
  facebook('facebook', 'Facebook'),
  google('google', 'Google'),
  event('event', 'Event'),
  other('other', 'Other');

  const LeadSource(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static LeadSource fromDb(String? v) {
    for (final s in values) {
      if (s.dbValue == v) return s;
    }
    return LeadSource.other;
  }
}

class Lead {
  const Lead({
    required this.id,
    required this.academyId,
    required this.firstName,
    required this.status,
    required this.source,
    required this.createdAt,
    this.lastName,
    this.email,
    this.phone,
    this.parentName,
    this.age,
    this.sport,
    this.preferredCenterId,
    this.notes,
    this.assignedTo,
    this.nextFollowupAt,
    this.trialScheduledAt,
    this.convertedStudentId,
    this.convertedAt,
    this.lostReason,
  });

  factory Lead.fromMap(Map<String, dynamic> m) => Lead(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        firstName: m['first_name'] as String,
        lastName: m['last_name'] as String?,
        email: m['email'] as String?,
        phone: m['phone'] as String?,
        parentName: m['parent_name'] as String?,
        age: m['age'] as int?,
        sport: m['sport'] as String?,
        preferredCenterId: m['preferred_center_id'] as String?,
        notes: m['notes'] as String?,
        status: LeadStatus.fromDb(m['status'] as String?),
        source: LeadSource.fromDb(m['source'] as String?),
        assignedTo: m['assigned_to'] as String?,
        nextFollowupAt: _ts(m['next_followup_at']),
        trialScheduledAt: _ts(m['trial_scheduled_at']),
        convertedStudentId: m['converted_student_id'] as String?,
        convertedAt: _ts(m['converted_at']),
        lostReason: m['lost_reason'] as String?,
        createdAt: _ts(m['created_at']) ?? DateTime.now(),
      );

  static DateTime? _ts(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  final String id;
  final String academyId;
  final String firstName;
  final String? lastName;
  final String? email;
  final String? phone;
  final String? parentName;
  final int? age;
  final String? sport;
  final String? preferredCenterId;
  final String? notes;
  final LeadStatus status;
  final LeadSource source;
  final String? assignedTo;
  final DateTime? nextFollowupAt;
  final DateTime? trialScheduledAt;
  final String? convertedStudentId;
  final DateTime? convertedAt;
  final String? lostReason;
  final DateTime createdAt;

  String get displayName {
    final first = firstName;
    final last = lastName ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? '(no name)' : full;
  }
}

class LeadActivity {
  const LeadActivity({
    required this.id,
    required this.leadId,
    required this.kind,
    required this.createdAt,
    this.userId,
    this.content,
    this.metadata = const {},
  });

  factory LeadActivity.fromMap(Map<String, dynamic> m) => LeadActivity(
        id: m['id'] as String,
        leadId: m['lead_id'] as String,
        userId: m['user_id'] as String?,
        kind: m['kind'] as String,
        content: m['content'] as String?,
        metadata: (m['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt:
            DateTime.parse(m['created_at'] as String).toLocal(),
      );

  final String id;
  final String leadId;
  final String? userId;
  final String kind;
  final String? content;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
}

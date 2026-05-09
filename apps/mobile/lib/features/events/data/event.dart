enum EventKind {
  tournament('tournament', 'Tournament'),
  workshop('workshop', 'Workshop'),
  camp('camp', 'Camp'),
  fixture('fixture', 'Fixture'),
  social('social', 'Social');

  const EventKind(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static EventKind fromDb(String? v) {
    for (final s in values) {
      if (s.dbValue == v) return s;
    }
    return EventKind.tournament;
  }
}

enum EventStatus {
  draft('draft', 'Draft'),
  published('published', 'Published'),
  registrationClosed('registration_closed', 'Reg. closed'),
  inProgress('in_progress', 'In progress'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const EventStatus(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static EventStatus fromDb(String? v) {
    for (final s in values) {
      if (s.dbValue == v) return s;
    }
    return EventStatus.draft;
  }
}

class EventEntry {
  const EventEntry({
    required this.id,
    required this.academyId,
    required this.title,
    required this.kind,
    required this.status,
    required this.startsAt,
    required this.feeAmount,
    this.centerId,
    this.description,
    this.sport,
    this.endsAt,
    this.location,
    this.registrationOpensAt,
    this.registrationClosesAt,
    this.capacity,
    this.eligibleBatchIds = const [],
    this.certificateTemplateUrl,
    this.createdBy,
    required this.createdAt,
  });

  factory EventEntry.fromMap(Map<String, dynamic> m) => EventEntry(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        centerId: m['center_id'] as String?,
        title: m['title'] as String,
        description: m['description'] as String?,
        kind: EventKind.fromDb(m['kind'] as String?),
        status: EventStatus.fromDb(m['status'] as String?),
        sport: m['sport'] as String?,
        startsAt: DateTime.parse(m['starts_at'] as String).toLocal(),
        endsAt: _ts(m['ends_at']),
        location: m['location'] as String?,
        registrationOpensAt: _ts(m['registration_opens_at']),
        registrationClosesAt: _ts(m['registration_closes_at']),
        capacity: m['capacity'] as int?,
        feeAmount: (m['fee_amount'] as num?)?.toDouble() ?? 0.0,
        eligibleBatchIds: (m['eligible_batch_ids'] as List?)
                ?.cast<String>() ??
            const [],
        certificateTemplateUrl: m['certificate_template_url'] as String?,
        createdBy: m['created_by'] as String?,
        createdAt:
            _ts(m['created_at']) ?? DateTime.now(),
      );

  static DateTime? _ts(dynamic v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  final String id;
  final String academyId;
  final String? centerId;
  final String title;
  final String? description;
  final EventKind kind;
  final EventStatus status;
  final String? sport;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? location;
  final DateTime? registrationOpensAt;
  final DateTime? registrationClosesAt;
  final int? capacity;
  final double feeAmount;
  final List<String> eligibleBatchIds;
  final String? certificateTemplateUrl;
  final String? createdBy;
  final DateTime createdAt;

  bool get registrationOpen {
    if (status != EventStatus.published) return false;
    final now = DateTime.now();
    if (registrationOpensAt != null && registrationOpensAt!.isAfter(now)) {
      return false;
    }
    if (registrationClosesAt != null && registrationClosesAt!.isBefore(now)) {
      return false;
    }
    return true;
  }
}

class EventRegistration {
  const EventRegistration({
    required this.id,
    required this.eventId,
    required this.studentId,
    required this.status,
    required this.feePaid,
    required this.registeredAt,
    this.invoiceId,
    this.notes,
  });

  factory EventRegistration.fromMap(Map<String, dynamic> m) =>
      EventRegistration(
        id: m['id'] as String,
        eventId: m['event_id'] as String,
        studentId: m['student_id'] as String,
        status: m['status'] as String,
        feePaid: m['fee_paid'] as bool? ?? false,
        invoiceId: m['invoice_id'] as String?,
        notes: m['notes'] as String?,
        registeredAt:
            DateTime.parse(m['registered_at'] as String).toLocal(),
      );

  final String id;
  final String eventId;
  final String studentId;
  final String status;
  final bool feePaid;
  final String? invoiceId;
  final String? notes;
  final DateTime registeredAt;
}

class EventResult {
  const EventResult({
    required this.id,
    required this.eventId,
    required this.studentId,
    this.placement,
    this.score,
    this.category,
    this.remarks,
    this.certificateUrl,
    this.certificateIssuedAt,
  });

  factory EventResult.fromMap(Map<String, dynamic> m) => EventResult(
        id: m['id'] as String,
        eventId: m['event_id'] as String,
        studentId: m['student_id'] as String,
        placement: m['placement'] as int?,
        score: (m['score'] as num?)?.toDouble(),
        category: m['category'] as String?,
        remarks: m['remarks'] as String?,
        certificateUrl: m['certificate_url'] as String?,
        certificateIssuedAt: m['certificate_issued_at'] == null
            ? null
            : DateTime.parse(m['certificate_issued_at'] as String).toLocal(),
      );

  final String id;
  final String eventId;
  final String studentId;
  final int? placement;
  final double? score;
  final String? category;
  final String? remarks;
  final String? certificateUrl;
  final DateTime? certificateIssuedAt;
}

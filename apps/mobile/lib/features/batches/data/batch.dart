/// Schedule sub-document stored on the batch.
class BatchSchedule {
  const BatchSchedule({
    this.days = const [],
    this.startTime,
    this.endTime,
  });

  factory BatchSchedule.fromMap(Map<String, dynamic> m) => BatchSchedule(
        days: ((m['days'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        startTime: m['start_time'] as String?,
        endTime: m['end_time'] as String?,
      );

  final List<String> days; // 'mon','tue','wed','thu','fri','sat','sun'
  final String? startTime; // 'HH:mm'
  final String? endTime;

  Map<String, dynamic> toMap() => {
        'days': days,
        if (startTime != null) 'start_time': startTime,
        if (endTime != null) 'end_time': endTime,
      };

  String get summary {
    if (days.isEmpty) return 'No schedule';
    final dayPart = days.join(', ');
    if (startTime == null) return dayPart;
    return '$dayPart  ${startTime!}${endTime == null ? '' : '–${endTime!}'}';
  }
}

class Batch {
  const Batch({
    required this.id,
    required this.academyId,
    required this.name,
    required this.schedule,
    required this.isActive,
    this.centerId,
    this.coachId,
    this.description,
    this.sport,
    this.capacity,
    this.ageGroup,
    this.skillLevel,
    this.startDate,
    this.endDate,
    this.enrolledCount = 0,
  });

  factory Batch.fromMap(Map<String, dynamic> m) => Batch(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        centerId: m['center_id'] as String?,
        coachId: m['coach_id'] as String?,
        name: m['name'] as String,
        description: m['description'] as String?,
        sport: m['sport'] as String?,
        schedule: BatchSchedule.fromMap(
            (m['schedule'] as Map?)?.cast<String, dynamic>() ?? const {}),
        capacity: m['capacity'] as int?,
        ageGroup: m['age_group'] as String?,
        skillLevel: m['skill_level'] as String?,
        startDate: m['start_date'] == null
            ? null
            : DateTime.parse(m['start_date'] as String),
        endDate: m['end_date'] == null
            ? null
            : DateTime.parse(m['end_date'] as String),
        isActive: (m['is_active'] as bool?) ?? true,
        enrolledCount: (m['enrolled_count'] as int?) ?? 0,
      );

  final String id;
  final String academyId;
  final String? centerId;
  final String? coachId;
  final String name;
  final String? description;
  final String? sport;
  final BatchSchedule schedule;
  final int? capacity;
  final String? ageGroup;
  final String? skillLevel;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;
  final int enrolledCount;
}

class Enrollment {
  const Enrollment({
    required this.id,
    required this.batchId,
    required this.studentId,
    required this.status,
    required this.enrolledAt,
  });

  factory Enrollment.fromMap(Map<String, dynamic> m) => Enrollment(
        id: m['id'] as String,
        batchId: m['batch_id'] as String,
        studentId: m['student_id'] as String,
        status: m['enrollment_status'] as String,
        enrolledAt: DateTime.parse(m['enrolled_at'] as String),
      );

  final String id;
  final String batchId;
  final String studentId;
  final String status;
  final DateTime enrolledAt;
}

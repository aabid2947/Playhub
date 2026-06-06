/// One row in `performance_skills` — a single skill scored 1–10 against an
/// assessment.
class PerformanceSkill {
  const PerformanceSkill({
    required this.id,
    required this.assessmentId,
    required this.skillName,
    required this.score,
    this.notes,
  });

  factory PerformanceSkill.fromMap(Map<String, dynamic> m) => PerformanceSkill(
        id: m['id'] as String,
        assessmentId: m['assessment_id'] as String,
        skillName: m['skill_name'] as String,
        score: (m['score'] as num).toInt(),
        notes: m['notes'] as String?,
      );

  final String id;
  final String assessmentId;
  final String skillName;
  final int score;
  final String? notes;
}

/// One row in `performance_media` — photo/video bound to an assessment.
class PerformanceMedia {
  const PerformanceMedia({
    required this.id,
    required this.mediaType,
    required this.filePath,
    this.assessmentId,
    this.originalFilename,
    this.mimeType,
    this.sizeBytes,
  });

  factory PerformanceMedia.fromMap(Map<String, dynamic> m) => PerformanceMedia(
        id: m['id'] as String,
        // Null for "standalone" media a trainer/coach attached straight to a
        // student (no scored assessment).
        assessmentId: m['assessment_id'] as String?,
        mediaType: m['media_type'] as String,
        filePath: m['file_path'] as String,
        originalFilename: m['original_filename'] as String?,
        mimeType: m['mime_type'] as String?,
        sizeBytes: (m['size_bytes'] as num?)?.toInt(),
      );

  final String id;
  final String? assessmentId;
  final String mediaType; // 'photo' | 'video'
  final String filePath;
  final String? originalFilename;
  final String? mimeType;
  final int? sizeBytes;
}

/// Header row in `performance_assessments`. Skills + media are loaded
/// separately by the detail page.
class PerformanceAssessment {
  const PerformanceAssessment({
    required this.id,
    required this.academyId,
    required this.studentId,
    required this.assessmentDate,
    this.batchId,
    this.coachId,
    this.sportId,
    this.overallScore,
    this.qualitativeFeedback,
    this.recordedBy,
  });

  factory PerformanceAssessment.fromMap(Map<String, dynamic> m) =>
      PerformanceAssessment(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        studentId: m['student_id'] as String,
        batchId: m['batch_id'] as String?,
        coachId: m['coach_id'] as String?,
        assessmentDate: DateTime.parse(m['assessment_date'] as String),
        sportId: m['sport_id'] as String?,
        overallScore: (m['overall_score'] as num?)?.toDouble(),
        qualitativeFeedback: m['qualitative_feedback'] as String?,
        recordedBy: m['recorded_by'] as String?,
      );

  final String id;
  final String academyId;
  final String studentId;
  final String? batchId;
  final String? coachId;
  final DateTime assessmentDate;
  final String? sportId;
  final double? overallScore;
  final String? qualitativeFeedback;
  final String? recordedBy;
}

/// Generic fallback rubric used when a sport hasn't been picked yet (or
/// when the chosen sport has no skills configured). Sport-specific rubrics
/// come from `public.sport_skills` via `sportSkillsProvider`.
const List<String> genericRubric = [
  'Technique',
  'Effort',
  'Discipline',
  'Team play',
  'Improvement',
];

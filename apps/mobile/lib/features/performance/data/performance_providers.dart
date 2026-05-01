import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/performance/data/performance.dart';

/// Latest assessments for one student (newest first).
final assessmentsForStudentProvider = FutureProvider.family<
    List<PerformanceAssessment>, String>((ref, studentId) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('performance_assessments')
      .select()
      .eq('student_id', studentId)
      .order('assessment_date', ascending: false)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => PerformanceAssessment.fromMap(r as Map<String, dynamic>))
      .toList();
});

/// Skill line items for one assessment.
final skillsForAssessmentProvider = FutureProvider.family<
    List<PerformanceSkill>, String>((ref, assessmentId) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('performance_skills')
      .select()
      .eq('assessment_id', assessmentId)
      .order('created_at');
  return (rows as List)
      .map((r) => PerformanceSkill.fromMap(r as Map<String, dynamic>))
      .toList();
});

/// Media attached to one assessment.
final mediaForAssessmentProvider = FutureProvider.family<
    List<PerformanceMedia>, String>((ref, assessmentId) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('performance_media')
      .select()
      .eq('assessment_id', assessmentId)
      .order('uploaded_at', ascending: false);
  return (rows as List)
      .map((r) => PerformanceMedia.fromMap(r as Map<String, dynamic>))
      .toList();
});

/// Per-student trend row from the materialized view.
final performanceTrendProvider = FutureProvider.family<
    Map<String, dynamic>?, String>((ref, studentId) async {
  final client = ref.read(supabaseClientProvider);
  final row = await client
      .from('student_performance_trend_view')
      .select()
      .eq('student_id', studentId)
      .maybeSingle();
  return row;
});

class SkillEntry {
  SkillEntry({required this.name, this.score = 5, this.notes = ''});
  String name;
  int score;
  String notes;
}

/// Create an assessment + its skill line items in one go.
/// Returns the new assessment id so callers can attach media after.
Future<String> createAssessment(
  WidgetRef ref, {
  required String studentId,
  required List<SkillEntry> skills,
  String? batchId,
  String? sport,
  double? overallScore,
  String? qualitativeFeedback,
  DateTime? date,
}) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) {
    throw StateError('No academy linked to current user');
  }
  final ymd = (date ?? DateTime.now()).toIso8601String().substring(0, 10);

  final inserted = await client
      .from('performance_assessments')
      .insert({
        'academy_id': academyId,
        'student_id': studentId,
        if (batchId != null) 'batch_id': batchId,
        if (sport != null && sport.isNotEmpty) 'sport': sport,
        if (overallScore != null) 'overall_score': overallScore,
        if (qualitativeFeedback != null && qualitativeFeedback.isNotEmpty)
          'qualitative_feedback': qualitativeFeedback,
        'assessment_date': ymd,
        'recorded_by': profile?.id,
      })
      .select()
      .single();

  final assessmentId = inserted['id'] as String;

  final skillRows = skills
      .where((s) => s.name.trim().isNotEmpty)
      .map((s) => {
            'assessment_id': assessmentId,
            'academy_id': academyId,
            'student_id': studentId,
            'skill_name': s.name.trim(),
            'score': s.score,
            if (s.notes.trim().isNotEmpty) 'notes': s.notes.trim(),
          })
      .toList();
  if (skillRows.isNotEmpty) {
    await client.from('performance_skills').insert(skillRows);
  }

  ref
    ..invalidate(assessmentsForStudentProvider(studentId))
    ..invalidate(performanceTrendProvider(studentId));
  return assessmentId;
}

/// Insert a media row after the file is uploaded to the
/// `performance_media` bucket by StorageService.
Future<void> attachMedia(
  WidgetRef ref, {
  required String assessmentId,
  required String studentId,
  required String mediaType, // 'photo' | 'video'
  required String filePath,
  String? originalFilename,
  String? mimeType,
  int? sizeBytes,
}) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return;
  await client.from('performance_media').insert({
    'assessment_id': assessmentId,
    'academy_id': academyId,
    'student_id': studentId,
    'media_type': mediaType,
    'file_path': filePath,
    if (originalFilename != null) 'original_filename': originalFilename,
    if (mimeType != null) 'mime_type': mimeType,
    if (sizeBytes != null) 'size_bytes': sizeBytes,
    'uploaded_by': profile?.id,
  });
  ref.invalidate(mediaForAssessmentProvider(assessmentId));
}

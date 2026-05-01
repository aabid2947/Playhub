import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/students/data/student_document.dart';

final studentDocumentsProvider =
    FutureProvider.family<List<StudentDocument>, String>(
        (ref, studentId) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('student_documents')
      .select()
      .eq('student_id', studentId)
      .order('uploaded_at', ascending: false);
  return (rows as List)
      .map((r) => StudentDocument.fromMap(r as Map<String, dynamic>))
      .toList();
});

Future<void> uploadStudentDocument(
  WidgetRef ref, {
  required String studentId,
  required String type,
}) async {
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) {
    throw StateError('No academy linked to current user');
  }

  final picked = await ref
      .read(storageServiceProvider)
      .pickAndUploadStudentDocument(
        academyId: academyId,
        studentId: studentId,
      );
  if (picked == null) return; // cancelled

  final client = ref.read(supabaseClientProvider);
  await client.from('student_documents').insert({
    'academy_id': academyId,
    'student_id': studentId,
    'type': type,
    'file_path': picked.path,
    'original_filename': picked.originalFilename,
    'mime_type': picked.mimeType,
    'size_bytes': picked.sizeBytes,
    'uploaded_by': profile!.id,
  });

  ref.invalidate(studentDocumentsProvider(studentId));
}

Future<void> deleteStudentDocument(
  WidgetRef ref, {
  required StudentDocument doc,
}) async {
  final client = ref.read(supabaseClientProvider);
  await client.from('student_documents').delete().eq('id', doc.id);
  await ref.read(storageServiceProvider).deleteStudentDocument(doc.filePath);
  ref.invalidate(studentDocumentsProvider(doc.studentId));
}

Future<String> signedUrlFor(WidgetRef ref, StudentDocument doc) {
  return ref.read(storageServiceProvider).signedDocumentUrl(doc.filePath);
}

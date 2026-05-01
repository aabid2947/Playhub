import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/coaches/data/coach_document.dart';

final coachDocumentsProvider =
    FutureProvider.family<List<CoachDocument>, String>((ref, coachId) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('coach_documents')
      .select()
      .eq('coach_id', coachId)
      .order('uploaded_at', ascending: false);
  return (rows as List)
      .map((r) => CoachDocument.fromMap(r as Map<String, dynamic>))
      .toList();
});

Future<void> uploadCoachDocument(
  WidgetRef ref, {
  required String coachId,
  required String type,
}) async {
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) {
    throw StateError('No academy linked to current user');
  }

  final picked = await ref
      .read(storageServiceProvider)
      .pickAndUploadCoachDocument(
        academyId: academyId,
        coachId: coachId,
      );
  if (picked == null) return;

  final client = ref.read(supabaseClientProvider);
  await client.from('coach_documents').insert({
    'academy_id': academyId,
    'coach_id': coachId,
    'type': type,
    'file_path': picked.path,
    'original_filename': picked.originalFilename,
    'mime_type': picked.mimeType,
    'size_bytes': picked.sizeBytes,
    'uploaded_by': profile!.id,
  });

  ref.invalidate(coachDocumentsProvider(coachId));
}

Future<void> deleteCoachDocument(
  WidgetRef ref, {
  required CoachDocument doc,
}) async {
  final client = ref.read(supabaseClientProvider);
  await client.from('coach_documents').delete().eq('id', doc.id);
  await ref.read(storageServiceProvider).deleteCoachDocument(doc.filePath);
  ref.invalidate(coachDocumentsProvider(doc.coachId));
}

Future<String> coachDocumentSignedUrl(WidgetRef ref, CoachDocument doc) {
  return ref.read(storageServiceProvider).signedCoachDocumentUrl(doc.filePath);
}

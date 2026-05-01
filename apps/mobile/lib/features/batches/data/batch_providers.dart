import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch.dart';

/// Reads from the `batches_with_counts` view so each row carries
/// `enrolled_count` without an N+1 fetch.
final batchesProvider = FutureProvider<List<Batch>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return [];

  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('batches_with_counts')
      .select()
      .eq('academy_id', academyId)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => Batch.fromMap(r as Map<String, dynamic>))
      .toList();
});

final batchEnrollmentsProvider =
    FutureProvider.family<List<Enrollment>, String>((ref, batchId) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('batch_enrollments')
      .select()
      .eq('batch_id', batchId)
      .order('enrolled_at', ascending: false);
  return (rows as List)
      .map((r) => Enrollment.fromMap(r as Map<String, dynamic>))
      .toList();
});

Future<Batch> createBatch(WidgetRef ref, Map<String, dynamic> data) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) {
    throw StateError('No academy linked to current user');
  }
  final row = await client
      .from('batches')
      .insert({...data, 'academy_id': academyId})
      .select()
      .single();
  ref.invalidate(batchesProvider);
  return Batch.fromMap(row);
}

Future<Batch> updateBatch(
  WidgetRef ref,
  String batchId,
  Map<String, dynamic> patch,
) async {
  final client = ref.read(supabaseClientProvider);
  final row = await client
      .from('batches')
      .update(patch)
      .eq('id', batchId)
      .select()
      .single();
  ref.invalidate(batchesProvider);
  return Batch.fromMap(row);
}

Future<void> enrollStudent(
  WidgetRef ref, {
  required String batchId,
  required String studentId,
  String status = 'active',
}) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) {
    throw StateError('No academy linked to current user');
  }
  await client.from('batch_enrollments').insert({
    'academy_id': academyId,
    'batch_id': batchId,
    'student_id': studentId,
    'enrollment_status': status,
  });
  ref
    ..invalidate(batchEnrollmentsProvider(batchId))
    ..invalidate(batchesProvider);
}

/// Promote a waitlisted enrollment to active.
Future<void> promoteEnrollment(
  WidgetRef ref, {
  required String enrollmentId,
  required String batchId,
}) async {
  final client = ref.read(supabaseClientProvider);
  await client
      .from('batch_enrollments')
      .update({'enrollment_status': 'active'})
      .eq('id', enrollmentId);
  ref
    ..invalidate(batchEnrollmentsProvider(batchId))
    ..invalidate(batchesProvider);
}

/// Atomically move an enrollment from one batch to another via the
/// `transfer_enrollment` Postgres function.
Future<void> transferEnrollment(
  WidgetRef ref, {
  required String enrollmentId,
  required String fromBatchId,
  required String toBatchId,
}) async {
  final client = ref.read(supabaseClientProvider);
  await client.rpc<dynamic>('transfer_enrollment', params: {
    'p_enrollment_id': enrollmentId,
    'p_target_batch_id': toBatchId,
  });
  ref
    ..invalidate(batchEnrollmentsProvider(fromBatchId))
    ..invalidate(batchEnrollmentsProvider(toBatchId))
    ..invalidate(batchesProvider);
}

Future<void> withdrawEnrollment(
  WidgetRef ref, {
  required String enrollmentId,
  required String batchId,
}) async {
  final client = ref.read(supabaseClientProvider);
  await client
      .from('batch_enrollments')
      .update({'enrollment_status': 'withdrawn'})
      .eq('id', enrollmentId);
  ref
    ..invalidate(batchEnrollmentsProvider(batchId))
    ..invalidate(batchesProvider);
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/billing/data/discount.dart';

// ---- Discount structures CRUD ------------------------------------------

final discountStructuresProvider =
    FutureProvider<List<DiscountStructure>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return [];
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('discount_structures')
      .select()
      .eq('academy_id', academyId)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) => DiscountStructure.fromMap(r as Map<String, dynamic>))
      .toList();
});

Future<DiscountStructure> createDiscountStructure(
  WidgetRef ref,
  Map<String, dynamic> data,
) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) throw StateError('No academy linked');
  final row = await client
      .from('discount_structures')
      .insert({...data, 'academy_id': academyId})
      .select()
      .single();
  ref.invalidate(discountStructuresProvider);
  return DiscountStructure.fromMap(row);
}

Future<DiscountStructure> updateDiscountStructure(
  WidgetRef ref,
  String id,
  Map<String, dynamic> patch,
) async {
  final client = ref.read(supabaseClientProvider);
  final row = await client
      .from('discount_structures')
      .update(patch)
      .eq('id', id)
      .select()
      .single();
  ref.invalidate(discountStructuresProvider);
  return DiscountStructure.fromMap(row);
}

// ---- Student-level discount assignments --------------------------------

final studentDiscountAssignmentsProvider = FutureProvider.family<
    List<StudentDiscountAssignment>, String>((ref, studentId) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('student_discount_assignments')
      .select()
      .eq('student_id', studentId)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) =>
          StudentDiscountAssignment.fromMap(r as Map<String, dynamic>))
      .toList();
});

Future<void> assignDiscountToStudent(
  WidgetRef ref, {
  required String studentId,
  required String discountStructureId,
  required DateTime startDate,
  required bool stackWithBatch,
}) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) throw StateError('No academy linked');
  await client.from('student_discount_assignments').insert({
    'academy_id': academyId,
    'student_id': studentId,
    'discount_structure_id': discountStructureId,
    'start_date': startDate.toIso8601String().substring(0, 10),
    'stack_with_batch': stackWithBatch,
  });
  ref.invalidate(studentDiscountAssignmentsProvider(studentId));
}

Future<void> deactivateStudentDiscount(
  WidgetRef ref, {
  required String assignmentId,
  required String studentId,
}) async {
  final client = ref.read(supabaseClientProvider);
  await client
      .from('student_discount_assignments')
      .update({
        'is_active': false,
        'end_date': DateTime.now().toIso8601String().substring(0, 10),
      })
      .eq('id', assignmentId);
  ref.invalidate(studentDiscountAssignmentsProvider(studentId));
}

// ---- Batch-level discount assignments ----------------------------------

final batchDiscountAssignmentsProvider = FutureProvider.family<
    List<BatchDiscountAssignment>, String>((ref, batchId) async {
  final client = ref.read(supabaseClientProvider);
  final rows = await client
      .from('batch_discount_assignments')
      .select()
      .eq('batch_id', batchId)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((r) =>
          BatchDiscountAssignment.fromMap(r as Map<String, dynamic>))
      .toList();
});

Future<void> assignDiscountToBatch(
  WidgetRef ref, {
  required String batchId,
  required String discountStructureId,
  required DateTime startDate,
}) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) throw StateError('No academy linked');
  await client.from('batch_discount_assignments').insert({
    'academy_id': academyId,
    'batch_id': batchId,
    'discount_structure_id': discountStructureId,
    'start_date': startDate.toIso8601String().substring(0, 10),
  });
  ref.invalidate(batchDiscountAssignmentsProvider(batchId));
}

Future<void> deactivateBatchDiscount(
  WidgetRef ref, {
  required String assignmentId,
  required String batchId,
}) async {
  final client = ref.read(supabaseClientProvider);
  await client
      .from('batch_discount_assignments')
      .update({
        'is_active': false,
        'end_date': DateTime.now().toIso8601String().substring(0, 10),
      })
      .eq('id', assignmentId);
  ref.invalidate(batchDiscountAssignmentsProvider(batchId));
}

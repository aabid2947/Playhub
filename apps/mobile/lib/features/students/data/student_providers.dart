import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/students/data/student.dart';

class StudentsFilter {
  const StudentsFilter({this.search, this.status, this.centerId});
  final String? search;
  final String? status;
  final String? centerId;
}

final studentsFilterProvider =
    StateProvider<StudentsFilter>((_) => const StudentsFilter());

final studentsProvider = FutureProvider<List<Student>>((ref) async {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return [];

  final filter = ref.watch(studentsFilterProvider);
  final client = ref.read(supabaseClientProvider);

  var query = client.from('students').select().eq('academy_id', academyId);

  if (filter.status != null && filter.status!.isNotEmpty) {
    query = query.eq('status', filter.status!);
  }
  if (filter.centerId != null && filter.centerId!.isNotEmpty) {
    query = query.eq('center_id', filter.centerId!);
  }
  if (filter.search != null && filter.search!.trim().isNotEmpty) {
    final s = filter.search!.trim();
    query = query.or('first_name.ilike.%$s%,last_name.ilike.%$s%,parent_name.ilike.%$s%');
  }

  final rows = await query.order('created_at', ascending: false);
  return (rows as List)
      .map((r) => Student.fromMap(r as Map<String, dynamic>))
      .toList();
});

Future<Student> createStudent(WidgetRef ref, Map<String, dynamic> data) async {
  final client = ref.read(supabaseClientProvider);
  final profile = await ref.read(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) {
    throw StateError('No academy linked to current user');
  }
  final row = await client
      .from('students')
      .insert({...data, 'academy_id': academyId})
      .select()
      .single();
  ref.invalidate(studentsProvider);
  return Student.fromMap(row);
}

Future<Student> updateStudent(
  WidgetRef ref,
  String studentId,
  Map<String, dynamic> patch,
) async {
  final client = ref.read(supabaseClientProvider);
  final row = await client
      .from('students')
      .update(patch)
      .eq('id', studentId)
      .select()
      .single();
  ref.invalidate(studentsProvider);
  return Student.fromMap(row);
}

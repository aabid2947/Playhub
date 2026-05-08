import 'package:playhub/features/parent/presentation/parent_home_shell.dart';

/// The student-role shell mirrors the parent shell: students see their own
/// attendance, performance, and dues — same providers, narrowed by RLS via
/// my_linked_student_ids() (which returns the student's own id when
/// students.user_id matches the caller).
class StudentHomeShell extends ParentHomeShell {
  const StudentHomeShell({super.key});
}

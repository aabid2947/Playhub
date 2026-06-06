import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';

/// Client-side mirror of the backend role-capability matrix
/// (supabase/migrations/20260527000000_role_capabilities.sql).
///
/// This is the single source of truth the UI uses to show/hide actions, so
/// the interface never offers something RLS will reject. Scope (own center /
/// own batches) is still enforced authoritatively by RLS — these flags only
/// govern whether the *entry point* is shown at all.
class Capabilities {
  const Capabilities(this.role);
  final String role;

  bool get _isAdmin =>
      role == 'academy_owner' || role == 'academy_admin';

  // Owner-exclusive: the academy record + its subscription.
  bool get manageAcademySettings => role == 'academy_owner';
  bool get manageSubscription => role == 'academy_owner';

  // Admin tier (owner/admin). center_admin invites are scoped + handled in the
  // invite Edge Function, so the generic Team screen stays admin-only.
  bool get manageTeam => _isAdmin;

  // Admin tier + center_admin (their own center).
  bool get manageStudents => _isAdmin || role == 'center_admin';
  bool get manageCoaches => _isAdmin || role == 'center_admin';
  bool get manageLeads => _isAdmin || role == 'center_admin';
  bool get manageInventory => _isAdmin || role == 'center_admin';

  // Admin tier + center_admin + head_coach.
  bool get manageBatches =>
      _isAdmin || role == 'center_admin' || role == 'head_coach';
  bool get manageEvents =>
      _isAdmin || role == 'center_admin' || role == 'head_coach';

  // Finance: admin writes; center_admin is view-only (no write flag).
  bool get manageFinance => _isAdmin;
  bool get viewRevenue => _isAdmin || role == 'center_admin';

  // Attendance: everyone down to trainer (own batches enforced by RLS).
  bool get markAttendance =>
      _isAdmin ||
      role == 'center_admin' ||
      role == 'head_coach' ||
      role == 'coach' ||
      role == 'trainer';

  // Performance: same ladder MINUS trainer.
  bool get recordPerformance =>
      _isAdmin ||
      role == 'center_admin' ||
      role == 'head_coach' ||
      role == 'coach';

  // Media: trainers + coaches (and center/admin tiers) can attach standalone
  // photos/videos to a student — no scored assessment. Mirrors the DB helper
  // can_upload_student_media() (20260606000000_trainer_student_media.sql).
  // Trainers are included here even though they lack recordPerformance.
  bool get uploadStudentMedia =>
      _isAdmin ||
      role == 'center_admin' ||
      role == 'head_coach' ||
      role == 'coach' ||
      role == 'trainer';

  bool get isCenterScoped => role == 'center_admin';
}

final capabilitiesProvider = Provider<Capabilities>((ref) {
  final role = ref.watch(currentProfileProvider).valueOrNull?.role ?? '';
  return Capabilities(role);
});

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

  // Admin tier (owner/admin). NOTE: manageTeam is also the gate for the
  // academy-wide org surfaces (sports settings, centers CRUD) whose RLS is
  // has_admin_or_higher() — so it must stay admin-only. The invite/provision
  // entry point uses canProvisionAnyone below, not this.
  bool get manageTeam => _isAdmin;

  /// Client mirror of the DB `can_provision_role()` ladder
  /// (supabase/migrations/20260607000000_provisioning_ladder.sql): the roles
  /// this user may invite. RLS + the invite-user Edge Function are the real
  /// gate — this only filters the role picker so the UI never offers a role the
  /// backend will reject. Center scope (own-center) is enforced server-side.
  List<String> get invitableRoles {
    switch (role) {
      case 'super_admin':
      case 'academy_owner':
        return const [
          'academy_admin', 'center_admin', 'head_coach',
          'coach', 'trainer', 'parent', 'student',
        ];
      case 'academy_admin':
        return const [
          'center_admin', 'head_coach', 'coach',
          'trainer', 'parent', 'student',
        ];
      case 'center_admin':
        return const ['head_coach', 'coach', 'trainer', 'parent', 'student'];
      case 'head_coach':
        return const ['coach', 'trainer'];
      case 'coach':
        return const ['trainer'];
      default:
        return const [];
    }
  }

  bool canInvite(String targetRole) => invitableRoles.contains(targetRole);

  /// Whether to surface an "invite a team member" entry point at all.
  bool get canProvisionAnyone => invitableRoles.isNotEmpty;

  /// Center-scoped inviters (center_admin/head_coach/coach) provision only into
  /// their OWN center — the invite-user fn forces it, so the UI hides the center
  /// picker for them. Admin-tier inviters choose the center.
  bool get inviteScopedToOwnCenter =>
      role == 'center_admin' || role == 'head_coach' || role == 'coach';

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

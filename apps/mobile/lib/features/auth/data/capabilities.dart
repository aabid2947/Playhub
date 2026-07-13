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

  // Owner-exclusive: the academy's own payment-gateway credentials (Razorpay /
  // Paytm keys). RLS + the set_payment_gateway RPC are the real gate
  // (20260615000000_academy_payment_gateways.sql) — money-moving secrets, so
  // owner-only, never even academy_admin.
  bool get managePaymentGateways => role == 'academy_owner';

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
        // head_coach manages students in their center (can_manage_student), so
        // they may also mint those students' parent/student logins — mirror of
        // can_provision_role's head_coach branch (20260711000000).
        return const ['coach', 'trainer', 'parent', 'student'];
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

  // Whether to surface a students LIST/management surface at all. Admin tier +
  // center_admin + head_coach (own center), and coach — but a coach's list is
  // RLS-scoped to students in their own batches (student_assigned_to_me,
  // 20260608000200), so they view/edit only their batch students, not the
  // center. Leads/inventory stay center_admin+.
  bool get manageStudents =>
      _isAdmin ||
      role == 'center_admin' ||
      role == 'head_coach' ||
      role == 'coach';

  // Onboarding (create / bulk-import a NEW student record) is an admin-tier /
  // center_admin / head_coach task. Coaches were dropped (20260608000200): they
  // can view + edit students in their own batches but no longer create. RLS
  // (can_manage_student) is the real gate; this hides the create/import entry.
  bool get createStudents =>
      _isAdmin || role == 'center_admin' || role == 'head_coach';
  // head_coach can also create/edit coach RECORDS in their own center
  // (can_manage_coach_record, 20260607000800) so they can build a coach and
  // assign them to a batch — completing create-coach -> assign-to-batch.
  bool get manageCoaches =>
      _isAdmin || role == 'center_admin' || role == 'head_coach';
  bool get manageLeads => _isAdmin || role == 'center_admin';
  bool get manageInventory => _isAdmin || role == 'center_admin';

  // Admin tier + center_admin + head_coach.
  bool get manageBatches =>
      _isAdmin || role == 'center_admin' || role == 'head_coach';
  bool get manageEvents =>
      _isAdmin || role == 'center_admin' || role == 'head_coach';

  // Sports enablement per center (center_sports). Admin tier writes any center;
  // center_admin writes their OWN center. Mirrors can_admin_center_scope, which
  // now gates center_sports (20260607000200_head_coach_sport_scope.sql). The UI
  // must scope a center_admin to their own center (RLS rejects others).
  bool get manageSports => _isAdmin || role == 'center_admin';

  // Finance: admin tier (any center) + center_admin (their OWN center's
  // students/batches — scoped by RLS via can_manage_finance,
  // 20260607000400_center_scoped_finance.sql).
  bool get manageFinance => _isAdmin || role == 'center_admin';
  bool get viewRevenue => _isAdmin || role == 'center_admin';

  // Refunds are money-OUT — kept at academy_admin+ for separation of duties.
  // center_admin manages fees/payments but cannot refund (RLS rejects it too),
  // so the refund entry point must use this, not manageFinance.
  bool get manageRefunds => _isAdmin;

  // Attendance: everyone down to trainer (own batches enforced by RLS).
  bool get markAttendance =>
      _isAdmin ||
      role == 'center_admin' ||
      role == 'head_coach' ||
      role == 'coach' ||
      role == 'trainer';

  // Performance: full attendance ladder INCLUDING trainer. Trainers record
  // performance for students in batches they staff (scoped by RLS via
  // staff_on_batch — 20260607000300_batch_staff_trainer_scope.sql).
  bool get recordPerformance =>
      _isAdmin ||
      role == 'center_admin' ||
      role == 'head_coach' ||
      role == 'coach' ||
      role == 'trainer';

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

  // Announcements: the compose ladder. Admin tier + center_admin + head_coach +
  // coach (NOT trainer). Mirrors can_target_announcement / has_coach_or_higher
  // (20260608000000_announcement_compose_and_media.sql). The *scope* of who
  // they may target (own center / sport / batch) is enforced by RLS; this only
  // shows the compose entry point + history view.
  bool get composeAnnouncements =>
      _isAdmin ||
      role == 'center_admin' ||
      role == 'head_coach' ||
      role == 'coach';

  // Email is heavier/spammier, so only the admin tier + center_admin may
  // broadcast via email. coach/head_coach are limited to push + in-app (the
  // composer hides the email channel for them).
  bool get announcementEmailChannel => _isAdmin || role == 'center_admin';

  // Admin tier + center_admin compose by role/center/sport/batch; head_coach +
  // coach compose only against batches/sports they own — the composer adapts
  // its audience pickers to this.
  bool get announcementTargetsByRole => _isAdmin;

  bool get isCenterScoped => role == 'center_admin';
}

final capabilitiesProvider = Provider<Capabilities>((ref) {
  final role = ref.watch(currentProfileProvider).valueOrNull?.role ?? '';
  return Capabilities(role);
});

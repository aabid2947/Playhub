import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/subscription/data/subscription_providers.dart';

/// Client mirror of the free-trial usage caps enforced in RLS
/// (supabase/migrations/20260629000000_trial_quota_limits.sql). These numbers
/// only HIDE/grey create entry points early — RLS is the real gate. Keep the
/// constants in sync with the migration if either changes.
///
/// During a live trial an academy may have at most: 1 sport, 2 coach records
/// (1 head coach + 1 coach), 1 head_coach / 1 coach / 1 trainer login, and
/// 5 students. The caps lift the moment the academy goes paid (active).
class TrialLimits {
  const TrialLimits({
    required this.isTrial,
    this.studentCount = 0,
    this.coachCount = 0,
    this.sportCount = 0,
    this.batchCount = 0,
    this.headCoachCount = 0,
    this.coachLoginCount = 0,
    this.trainerCount = 0,
  });

  /// Off-trial (paid) academies have no caps.
  static const TrialLimits unlimited = TrialLimits(isTrial: false);

  static const int maxStudents = 5;
  static const int maxCoachRecords = 2; // 1 head coach + 1 coach
  static const int maxSports = 1;
  static const int maxBatches = 2;
  static const int maxPerStaffRole = 1; // head_coach / coach / trainer logins

  final bool isTrial;
  final int studentCount;
  final int coachCount;
  final int sportCount;
  final int batchCount;
  final int headCoachCount;
  final int coachLoginCount;
  final int trainerCount;

  bool get studentsReached => isTrial && studentCount >= maxStudents;
  bool get coachesReached => isTrial && coachCount >= maxCoachRecords;
  bool get sportsReached => isTrial && sportCount >= maxSports;
  bool get batchesReached => isTrial && batchCount >= maxBatches;

  /// True when the trial's per-role login cap for [role] is used up.
  bool staffRoleReached(String role) {
    if (!isTrial) return false;
    final used = switch (role) {
      'head_coach' => headCoachCount,
      'coach' => coachLoginCount,
      'trainer' => trainerCount,
      _ => 0,
    };
    return used >= maxPerStaffRole;
  }

  String get studentsMessage =>
      'Free trial limit reached — $maxStudents students. '
      'Upgrade your plan to add more.';
  String get coachesMessage =>
      'Free trial limit reached — $maxCoachRecords coaches. '
      'Upgrade your plan to add more.';
  String get sportsMessage =>
      'Free trial limit reached — $maxSports sport. '
      'Upgrade your plan to offer more sports.';
  String get batchesMessage =>
      'Free trial limit reached — $maxBatches batches. '
      'Upgrade your plan to add more.';
}

/// Resolves the academy's current trial usage. Returns [TrialLimits.unlimited]
/// for paid academies (no extra queries). Trial academies are tiny by
/// definition, so counting via id-fetches is cheap. RLS scopes every read.
final trialLimitsProvider = FutureProvider<TrialLimits>((ref) async {
  final sub = await ref.watch(mySubscriptionProvider.future);
  if (sub == null || !sub.isTrial) return TrialLimits.unlimited;

  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) return TrialLimits.unlimited;

  final students = (await client
      .from('students')
      .select('id')
      .eq('academy_id', academyId)) as List<dynamic>;
  final coaches = (await client
      .from('coaches')
      .select('id')
      .eq('academy_id', academyId)) as List<dynamic>;
  final batches = (await client
      .from('batches')
      .select('id')
      .eq('academy_id', academyId)) as List<dynamic>;
  // Distinct sports come from center_sports — the only sport-enable path the app
  // writes (academy_sports isn't written by the app and is absent on some DBs).
  final centerSports = (await client
      .from('center_sports')
      .select('sport_id')
      .eq('academy_id', academyId)) as List<dynamic>;
  final staff = (await client
      .from('users')
      .select('role')
      .eq('academy_id', academyId)
      .inFilter('role', ['head_coach', 'coach', 'trainer'])) as List<dynamic>;

  final sportIds = <String>{
    for (final r in centerSports)
      if ((r as Map)['sport_id'] != null) r['sport_id'] as String,
  };
  int byRole(String role) =>
      staff.where((r) => (r as Map)['role'] == role).length;

  return TrialLimits(
    isTrial: true,
    studentCount: students.length,
    coachCount: coaches.length,
    batchCount: batches.length,
    sportCount: sportIds.length,
    headCoachCount: byRole('head_coach'),
    coachLoginCount: byRole('coach'),
    trainerCount: byRole('trainer'),
  );
});

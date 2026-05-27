import 'package:flutter_test/flutter_test.dart';
import 'package:playhub/features/auth/data/capabilities.dart';

// Client mirror of the RLS role-capability ladder
// (supabase/migrations/20260527000000_role_capabilities.sql). If a backend
// gate changes, the matrix here must change with it — this is the contract the
// UI uses to decide which actions to show.
void main() {
  // Column order:
  // [settings, subscription, team, students, coaches, leads, inventory,
  //  batches, events, finance, viewRevenue, attendance, performance, centerScoped]
  const matrix = <String, List<bool>>{
    'academy_owner': [true, true, true, true, true, true, true, true, true, true, true, true, true, false],
    'academy_admin': [false, false, true, true, true, true, true, true, true, true, true, true, true, false],
    'center_admin': [false, false, false, true, true, true, true, true, true, false, true, true, true, true],
    'head_coach': [false, false, false, false, false, false, false, true, true, false, false, true, true, false],
    'coach': [false, false, false, false, false, false, false, false, false, false, false, true, true, false],
    'trainer': [false, false, false, false, false, false, false, false, false, false, false, true, false, false],
    'parent': [false, false, false, false, false, false, false, false, false, false, false, false, false, false],
    'student': [false, false, false, false, false, false, false, false, false, false, false, false, false, false],
    // super_admin uses a separate shell; none of the academy capabilities apply.
    'super_admin': [false, false, false, false, false, false, false, false, false, false, false, false, false, false],
    // Null/unknown profile (logged-out flash) → everything off.
    '': [false, false, false, false, false, false, false, false, false, false, false, false, false, false],
  };

  List<bool> snapshot(Capabilities c) => [
        c.manageAcademySettings,
        c.manageSubscription,
        c.manageTeam,
        c.manageStudents,
        c.manageCoaches,
        c.manageLeads,
        c.manageInventory,
        c.manageBatches,
        c.manageEvents,
        c.manageFinance,
        c.viewRevenue,
        c.markAttendance,
        c.recordPerformance,
        c.isCenterScoped,
      ];

  matrix.forEach((role, expected) {
    test('capability matrix — ${role.isEmpty ? "(none)" : role}', () {
      expect(snapshot(Capabilities(role)), expected, reason: 'role="$role"');
    });
  });

  // The two ladder distinctions most likely to regress:
  test('trainer marks attendance but cannot record performance', () {
    expect(const Capabilities('trainer').markAttendance, isTrue);
    expect(const Capabilities('trainer').recordPerformance, isFalse);
  });

  test('center_admin can view revenue but not manage finance, and is center-scoped', () {
    const ca = Capabilities('center_admin');
    expect(ca.viewRevenue, isTrue);
    expect(ca.manageFinance, isFalse);
    expect(ca.isCenterScoped, isTrue);
  });

  test('only the owner manages academy settings + subscription', () {
    expect(const Capabilities('academy_owner').manageAcademySettings, isTrue);
    expect(const Capabilities('academy_admin').manageAcademySettings, isFalse);
    expect(const Capabilities('academy_owner').manageSubscription, isTrue);
    expect(const Capabilities('academy_admin').manageSubscription, isFalse);
  });
}

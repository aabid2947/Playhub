import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InviteResult {
  const InviteResult({
    required this.userId,
    required this.resent,
    required this.hasSignedIn,
  });
  final String? userId;
  final bool resent;
  final bool hasSignedIn;
}

class InviteRepo {
  InviteRepo(this._client);
  final SupabaseClient _client;

  /// Calls the invite-user Edge Function. New users get an invite email;
  /// already-registered emails get a fresh invite link via generateLink.
  Future<InviteResult> invite({
    required String email,
    required String role,
    String? firstName,
    String? lastName,
    String? centerId,
    String? linkToStudentId,
    String? linkRelationship,
    String? linkCoachId,
    String? linkStudentLoginId,
  }) async {
    final res = await _client.functions.invoke('invite-user', body: {
      'email': email,
      'role': role,
      if (firstName != null && firstName.isNotEmpty) 'first_name': firstName,
      if (lastName != null && lastName.isNotEmpty) 'last_name': lastName,
      if (centerId != null) 'center_id': centerId,
      if (linkToStudentId != null) 'link_to_student_id': linkToStudentId,
      if (linkRelationship != null) 'link_relationship': linkRelationship,
      if (linkCoachId != null) 'link_coach_id': linkCoachId,
      if (linkStudentLoginId != null)
        'link_student_login_id': linkStudentLoginId,
    });
    final body = res.data as Map<String, dynamic>;
    if (body['ok'] != true) {
      throw StateError(body['error']?.toString() ?? 'invite failed');
    }
    return InviteResult(
      userId: body['user_id'] as String?,
      resent: body['resent'] as bool? ?? false,
      hasSignedIn: body['has_signed_in'] as bool? ?? false,
    );
  }

  /// Removes a team member's login (public.users row). The users_admin_delete
  /// RLS policy enforces the provisioning ladder (can_provision_role), so a
  /// caller can only remove a rung strictly below them in their own center;
  /// anything else deletes zero rows. We `select()` the deleted row back and
  /// throw if nothing came back, surfacing a clean "not allowed" instead of a
  /// silent no-op. Linked coach/student records survive (FK is set-null).
  Future<void> removeMember(String userId) async {
    final deleted = await _client
        .from('users')
        .delete()
        .eq('id', userId)
        .select('id');
    if ((deleted as List).isEmpty) {
      throw StateError(
        "You can't remove this member — they're outside the staff you manage.",
      );
    }
  }
}

final inviteRepoProvider = Provider<InviteRepo>(
    (ref) => InviteRepo(ref.watch(supabaseClientProvider)));

class TeamMember {
  const TeamMember({
    required this.id,
    required this.role,
    required this.email,
    this.firstName,
    this.lastName,
    this.phone,
    this.centerId,
    this.isActive = true,
  });

  factory TeamMember.fromMap(Map<String, dynamic> m) => TeamMember(
        id: m['id'] as String,
        role: m['role'] as String,
        email: (m['email'] as String?) ?? '',
        firstName: m['first_name'] as String?,
        lastName: m['last_name'] as String?,
        phone: m['phone'] as String?,
        centerId: m['center_id'] as String?,
        isActive: m['is_active'] as bool? ?? true,
      );

  final String id;
  final String role;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? centerId;
  final bool isActive;

  String get displayName {
    final f = firstName ?? '';
    final l = lastName ?? '';
    final full = '$f $l'.trim();
    return full.isEmpty ? email : full;
  }
}

/// Lists same-academy users excluding parents and students (those have
/// dedicated UIs on student/coach detail pages).
final teamMembersProvider = FutureProvider<List<TeamMember>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('users')
      .select('id, role, email, first_name, last_name, phone, '
          'center_id, is_active')
      .inFilter('role', [
    'academy_owner',
    'academy_admin',
    'center_admin',
    'head_coach',
    'coach',
    'trainer',
  ]).order('role').order('first_name');
  return (rows as List)
      .map((r) => TeamMember.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

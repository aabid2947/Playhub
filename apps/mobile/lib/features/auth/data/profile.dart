/// Lightweight typed view of a `public.users` row.
/// Avoids freezed/json_serializable codegen for Sprint 0 simplicity.
class Profile {
  const Profile({
    required this.id,
    required this.role,
    this.email,
    this.phone,
    this.firstName,
    this.lastName,
    this.academyId,
    this.centerId,
    this.mustChangePassword = false,
  });

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        role: m['role'] as String,
        email: m['email'] as String?,
        phone: m['phone'] as String?,
        firstName: m['first_name'] as String?,
        lastName: m['last_name'] as String?,
        academyId: m['academy_id'] as String?,
        centerId: m['center_id'] as String?,
        mustChangePassword: m['must_change_password'] as bool? ?? false,
      );

  final String id;
  final String role;
  final String? email;
  final String? phone;
  final String? firstName;
  final String? lastName;
  final String? academyId;
  final String? centerId;
  final bool mustChangePassword;

  bool get needsAcademySetup =>
      role == 'academy_owner' && academyId == null;

  String get displayName {
    final first = firstName ?? '';
    final last = lastName ?? '';
    final full = '$first $last'.trim();
    return full.isEmpty ? (email ?? 'there') : full;
  }
}

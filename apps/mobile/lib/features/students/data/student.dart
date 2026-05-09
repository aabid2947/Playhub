class Student {
  const Student({
    required this.id,
    required this.academyId,
    required this.firstName,
    required this.lastName,
    required this.parentName,
    required this.status,
    required this.enrollmentDate,
    this.centerId,
    this.dateOfBirth,
    this.gender,
    this.photo,
    this.email,
    this.phone,
    this.parentEmail,
    this.parentPhone,
    this.parentAlternatePhone,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.medicalNotes,
    this.injuryInfo,
    this.sportId,
    this.skillLevel,
  });

  factory Student.fromMap(Map<String, dynamic> m) => Student(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        centerId: m['center_id'] as String?,
        firstName: m['first_name'] as String,
        lastName: m['last_name'] as String,
        dateOfBirth: m['date_of_birth'] == null
            ? null
            : DateTime.parse(m['date_of_birth'] as String),
        gender: m['gender'] as String?,
        photo: m['photo'] as String?,
        email: m['email'] as String?,
        phone: m['phone'] as String?,
        parentName: m['parent_name'] as String,
        parentEmail: m['parent_email'] as String?,
        parentPhone: m['parent_phone'] as String?,
        parentAlternatePhone: m['parent_alternate_phone'] as String?,
        address: m['address'] as String?,
        city: m['city'] as String?,
        state: m['state'] as String?,
        pincode: m['pincode'] as String?,
        emergencyContactName: m['emergency_contact_name'] as String?,
        emergencyContactPhone: m['emergency_contact_phone'] as String?,
        medicalNotes: m['medical_notes'] as String?,
        injuryInfo: m['injury_info'] as String?,
        sportId: m['sport_id'] as String?,
        skillLevel: m['skill_level'] as String?,
        status: m['status'] as String,
        enrollmentDate: DateTime.parse(m['enrollment_date'] as String),
      );

  final String id;
  final String academyId;
  final String? centerId;
  final String firstName;
  final String lastName;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? photo;
  final String? email;
  final String? phone;
  final String parentName;
  final String? parentEmail;
  final String? parentPhone;
  final String? parentAlternatePhone;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? medicalNotes;
  final String? injuryInfo;
  final String? sportId;
  final String? skillLevel;
  final String status;
  final DateTime enrollmentDate;

  String get fullName => '$firstName $lastName';
}

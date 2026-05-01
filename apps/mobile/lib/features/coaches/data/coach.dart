class Coach {
  const Coach({
    required this.id,
    required this.academyId,
    required this.firstName,
    required this.lastName,
    required this.joinDate,
    required this.isActive,
    this.userId,
    this.centerId,
    this.email,
    this.phone,
    this.photo,
    this.specialization = const [],
    this.experienceYears,
    this.qualifications = const [],
    this.certifications = const [],
    this.salary,
    this.paymentType,
  });

  factory Coach.fromMap(Map<String, dynamic> m) => Coach(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        userId: m['user_id'] as String?,
        centerId: m['center_id'] as String?,
        firstName: m['first_name'] as String,
        lastName: m['last_name'] as String,
        email: m['email'] as String?,
        phone: m['phone'] as String?,
        photo: m['photo'] as String?,
        specialization: ((m['specialization'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        experienceYears: m['experience_years'] as int?,
        qualifications: ((m['qualifications'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        certifications: ((m['certifications'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        salary: (m['salary'] as num?)?.toDouble(),
        paymentType: m['payment_type'] as String?,
        joinDate: DateTime.parse(m['join_date'] as String),
        isActive: (m['is_active'] as bool?) ?? true,
      );

  final String id;
  final String academyId;
  final String? userId;
  final String? centerId;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String? photo;
  final List<String> specialization;
  final int? experienceYears;
  final List<String> qualifications;
  final List<String> certifications;
  final double? salary;
  final String? paymentType;
  final DateTime joinDate;
  final bool isActive;

  String get fullName => '$firstName $lastName';
}

class Centre {
  const Centre({
    required this.id,
    required this.academyId,
    required this.name,
    required this.isActive,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.phone,
    this.email,
    this.facilities = const [],
    this.capacity,
    this.adminId,
  });

  factory Centre.fromMap(Map<String, dynamic> m) => Centre(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        name: m['name'] as String,
        isActive: (m['is_active'] as bool?) ?? true,
        address: m['address'] as String?,
        city: m['city'] as String?,
        state: m['state'] as String?,
        pincode: m['pincode'] as String?,
        phone: m['phone'] as String?,
        email: m['email'] as String?,
        facilities: ((m['facilities'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        capacity: m['capacity'] as int?,
        adminId: m['admin_id'] as String?,
      );

  final String id;
  final String academyId;
  final String name;
  final bool isActive;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? phone;
  final String? email;
  final List<String> facilities;
  final int? capacity;
  final String? adminId;
}

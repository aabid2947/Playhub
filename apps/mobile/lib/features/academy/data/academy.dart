class Academy {
  const Academy({
    required this.id,
    required this.name,
    this.logo,
    this.email,
    this.phone,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.website,
    this.sportsOffered = const [],
  });

  factory Academy.fromMap(Map<String, dynamic> m) => Academy(
        id: m['id'] as String,
        name: m['name'] as String,
        logo: m['logo'] as String?,
        email: m['email'] as String?,
        phone: m['phone'] as String?,
        address: m['address'] as String?,
        city: m['city'] as String?,
        state: m['state'] as String?,
        pincode: m['pincode'] as String?,
        website: m['website'] as String?,
        sportsOffered: ((m['sports_offered'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  final String id;
  final String name;
  final String? logo;
  final String? email;
  final String? phone;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final String? website;
  final List<String> sportsOffered;
}

/// Sports catalog row (`public.sports`). A null [academyId] is a global catalog
/// sport; a set [academyId] is that academy's own custom sport (created in-app).
class Sport {
  const Sport({
    required this.id,
    required this.code,
    required this.name,
    required this.isActive,
    this.category,
    this.academyId,
  });

  factory Sport.fromMap(Map<String, dynamic> m) => Sport(
        id: m['id'] as String,
        code: m['code'] as String,
        name: m['name'] as String,
        category: m['category'] as String?,
        isActive: m['is_active'] as bool? ?? true,
        academyId: m['academy_id'] as String?,
      );

  final String id;
  final String code;
  final String name;
  final String? category;
  final bool isActive;
  final String? academyId;

  /// True for an academy-created custom sport (vs the global catalog).
  bool get isCustom => academyId != null;
}

class SportSkill {
  const SportSkill({
    required this.id,
    required this.sportId,
    required this.name,
    required this.sortOrder,
  });

  factory SportSkill.fromMap(Map<String, dynamic> m) => SportSkill(
        id: m['id'] as String,
        sportId: m['sport_id'] as String,
        name: m['name'] as String,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String sportId;
  final String name;
  final int sortOrder;
}

/// `center_sports` row joined with the underlying sport. The `displayName`
/// honours the per-center override.
class CenterSport {
  const CenterSport({
    required this.id,
    required this.academyId,
    required this.centerId,
    required this.sport,
    required this.isActive,
    this.customName,
  });

  factory CenterSport.fromMap(Map<String, dynamic> m) => CenterSport(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        centerId: m['center_id'] as String,
        sport: Sport.fromMap((m['sport'] as Map).cast<String, dynamic>()),
        customName: m['custom_name'] as String?,
        isActive: m['is_active'] as bool? ?? true,
      );

  final String id;
  final String academyId;
  final String centerId;
  final Sport sport;
  final String? customName;
  final bool isActive;

  String get displayName =>
      (customName != null && customName!.trim().isNotEmpty)
          ? customName!.trim()
          : sport.name;
}

class CoachSport {
  const CoachSport({
    required this.id,
    required this.coachId,
    required this.sportId,
    required this.isPrimary,
  });

  factory CoachSport.fromMap(Map<String, dynamic> m) => CoachSport(
        id: m['id'] as String,
        coachId: m['coach_id'] as String,
        sportId: m['sport_id'] as String,
        isPrimary: m['is_primary'] as bool? ?? false,
      );

  final String id;
  final String coachId;
  final String sportId;
  final bool isPrimary;
}

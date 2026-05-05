enum DiscountType {
  percentage('percentage', 'Percentage'),
  flat('flat', 'Flat');

  const DiscountType(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static DiscountType fromDb(String? v) {
    for (final t in values) {
      if (t.dbValue == v) return t;
    }
    return DiscountType.percentage;
  }
}

class DiscountStructure {
  const DiscountStructure({
    required this.id,
    required this.academyId,
    required this.name,
    required this.type,
    required this.value,
    required this.isActive,
    this.description,
  });

  factory DiscountStructure.fromMap(Map<String, dynamic> m) =>
      DiscountStructure(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        type: DiscountType.fromDb(m['type'] as String?),
        value: (m['value'] as num).toDouble(),
        isActive: (m['is_active'] as bool?) ?? true,
      );

  final String id;
  final String academyId;
  final String name;
  final String? description;
  final DiscountType type;
  final double value;
  final bool isActive;

  String get summary => type == DiscountType.percentage
      ? '${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 1)}%'
      : '₹${value.toStringAsFixed(0)}';
}

class StudentDiscountAssignment {
  const StudentDiscountAssignment({
    required this.id,
    required this.academyId,
    required this.studentId,
    required this.discountStructureId,
    required this.startDate,
    required this.stackWithBatch,
    required this.isActive,
    this.endDate,
  });

  factory StudentDiscountAssignment.fromMap(Map<String, dynamic> m) =>
      StudentDiscountAssignment(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        studentId: m['student_id'] as String,
        discountStructureId: m['discount_structure_id'] as String,
        startDate: DateTime.parse(m['start_date'] as String),
        endDate: m['end_date'] == null
            ? null
            : DateTime.parse(m['end_date'] as String),
        stackWithBatch: (m['stack_with_batch'] as bool?) ?? true,
        isActive: (m['is_active'] as bool?) ?? true,
      );

  final String id;
  final String academyId;
  final String studentId;
  final String discountStructureId;
  final DateTime startDate;
  final DateTime? endDate;
  final bool stackWithBatch;
  final bool isActive;
}

class BatchDiscountAssignment {
  const BatchDiscountAssignment({
    required this.id,
    required this.academyId,
    required this.batchId,
    required this.discountStructureId,
    required this.startDate,
    required this.isActive,
    this.endDate,
  });

  factory BatchDiscountAssignment.fromMap(Map<String, dynamic> m) =>
      BatchDiscountAssignment(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        batchId: m['batch_id'] as String,
        discountStructureId: m['discount_structure_id'] as String,
        startDate: DateTime.parse(m['start_date'] as String),
        endDate: m['end_date'] == null
            ? null
            : DateTime.parse(m['end_date'] as String),
        isActive: (m['is_active'] as bool?) ?? true,
      );

  final String id;
  final String academyId;
  final String batchId;
  final String discountStructureId;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isActive;
}

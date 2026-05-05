/// Type of fee structure — controls how the cron generates invoices.
enum FeeType {
  monthly('monthly', 'Monthly'),
  quarterly('quarterly', 'Quarterly'),
  annual('annual', 'Annual'),
  oneTime('one_time', 'One-time');

  const FeeType(this.dbValue, this.label);
  final String dbValue;
  final String label;

  static FeeType fromDb(String? v) {
    for (final t in values) {
      if (t.dbValue == v) return t;
    }
    return FeeType.monthly;
  }
}

class FeeStructure {
  const FeeStructure({
    required this.id,
    required this.academyId,
    required this.name,
    required this.type,
    required this.baseAmount,
    required this.taxPct,
    required this.lateFeeGraceDays,
    required this.lateFeePolicy,
    required this.isActive,
    this.description,
    this.sport,
    this.batchId,
    this.lateFeePct,
    this.lateFeeFlat,
  });

  factory FeeStructure.fromMap(Map<String, dynamic> m) => FeeStructure(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        type: FeeType.fromDb(m['type'] as String?),
        sport: m['sport'] as String?,
        batchId: m['batch_id'] as String?,
        baseAmount: (m['base_amount'] as num).toDouble(),
        taxPct: (m['tax_pct'] as num).toDouble(),
        lateFeePct: (m['late_fee_pct'] as num?)?.toDouble(),
        lateFeeFlat: (m['late_fee_flat'] as num?)?.toDouble(),
        lateFeeGraceDays:
            (m['late_fee_grace_days'] as num?)?.toInt() ?? 5,
        lateFeePolicy:
            (m['late_fee_policy'] as String?) ?? 'one_time',
        isActive: (m['is_active'] as bool?) ?? true,
      );

  final String id;
  final String academyId;
  final String name;
  final String? description;
  final FeeType type;
  final String? sport;
  final String? batchId;
  final double baseAmount;
  final double taxPct;
  final double? lateFeePct;
  final double? lateFeeFlat;
  final int lateFeeGraceDays;
  final String lateFeePolicy; // 'none' | 'one_time' | 'daily'
  final bool isActive;

  double get totalAmount => baseAmount + (baseAmount * taxPct / 100);
}

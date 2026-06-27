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
    this.sportId,
    this.batchId,
    this.lateFeePct,
    this.lateFeeFlat,
    this.pricePerDay,
    this.daysPerWeek,
  });

  factory FeeStructure.fromMap(Map<String, dynamic> m) => FeeStructure(
        id: m['id'] as String,
        academyId: m['academy_id'] as String,
        name: m['name'] as String,
        description: m['description'] as String?,
        type: FeeType.fromDb(m['type'] as String?),
        sportId: m['sport_id'] as String?,
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
        pricePerDay: (m['price_per_day'] as num?)?.toDouble(),
        daysPerWeek: (m['days_per_week'] as num?)?.toInt(),
      );

  final String id;
  final String academyId;
  final String name;
  final String? description;
  final FeeType type;
  final String? sportId;
  final String? batchId;
  final double baseAmount;
  final double taxPct;
  final double? lateFeePct;
  final double? lateFeeFlat;
  final int lateFeeGraceDays;
  final String lateFeePolicy; // 'none' | 'one_time' | 'daily'
  final bool isActive;
  /// Non-null when the fee was set up with per-day pricing. Informational —
  /// [baseAmount] is what gets billed.
  final double? pricePerDay;
  /// Stored alongside [pricePerDay] so the calculation can be reconstructed
  /// when editing.
  final int? daysPerWeek;

  double get totalAmount => baseAmount + (baseAmount * taxPct / 100);
}

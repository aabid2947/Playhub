import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';

/// Reads from the `analytics_revenue_by_month` view (RLS-filtered wrapper
/// over the materialized view). Order: oldest first, last 12 months.
final revenueByMonthProvider =
    FutureProvider<List<RevenueMonth>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('analytics_revenue_by_month')
      .select()
      .eq('academy_id', profile!.academyId!)
      .order('month_start', ascending: false)
      .limit(12);
  final list = (rows as List)
      .map((r) => RevenueMonth.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
  // Reverse so the chart can render left-to-right.
  return list.reversed.toList(growable: false);
});

final enrollmentByMonthProvider =
    FutureProvider<List<EnrollmentMonth>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('analytics_enrollment_by_month')
      .select()
      .eq('academy_id', profile!.academyId!)
      .order('month_start', ascending: false)
      .limit(12);
  final list = (rows as List)
      .map((r) => EnrollmentMonth.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
  return list.reversed.toList(growable: false);
});

final leadFunnelProvider = FutureProvider<List<LeadFunnelRow>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('analytics_lead_funnel_summary')
      .select()
      .eq('academy_id', profile!.academyId!);
  return (rows as List)
      .map((r) => LeadFunnelRow.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

final batchUtilizationProvider =
    FutureProvider<List<BatchUtilizationRow>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return const [];
  final rows = await client
      .from('analytics_batch_utilization')
      .select()
      .eq('academy_id', profile!.academyId!);
  return (rows as List)
      .map((r) => BatchUtilizationRow.fromMap(r as Map<String, dynamic>))
      .toList(growable: false);
});

final collectionSummaryProvider =
    FutureProvider<CollectionSummary?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final profile = await ref.watch(currentProfileProvider.future);
  if (profile?.academyId == null) return null;
  final r = await client
      .from('analytics_collection_summary')
      .select()
      .eq('academy_id', profile!.academyId!)
      .maybeSingle();
  return r == null ? null : CollectionSummary.fromMap(r);
});

class RevenueMonth {
  const RevenueMonth({
    required this.monthStart,
    required this.collected,
    required this.billed,
    required this.outstanding,
    required this.invoiceCount,
    required this.paidCount,
  });

  factory RevenueMonth.fromMap(Map<String, dynamic> m) => RevenueMonth(
        monthStart: DateTime.parse(m['month_start'] as String),
        collected: (m['collected'] as num?)?.toDouble() ?? 0,
        billed: (m['billed'] as num?)?.toDouble() ?? 0,
        outstanding: (m['outstanding'] as num?)?.toDouble() ?? 0,
        invoiceCount: (m['invoice_count'] as num?)?.toInt() ?? 0,
        paidCount: (m['paid_count'] as num?)?.toInt() ?? 0,
      );

  final DateTime monthStart;
  final double collected;
  final double billed;
  final double outstanding;
  final int invoiceCount;
  final int paidCount;
}

class EnrollmentMonth {
  const EnrollmentMonth({required this.monthStart, required this.count});

  factory EnrollmentMonth.fromMap(Map<String, dynamic> m) => EnrollmentMonth(
        monthStart: DateTime.parse(m['month_start'] as String),
        count: (m['enrollment_count'] as num?)?.toInt() ?? 0,
      );

  final DateTime monthStart;
  final int count;
}

class LeadFunnelRow {
  const LeadFunnelRow({
    required this.status,
    required this.source,
    required this.count,
  });

  factory LeadFunnelRow.fromMap(Map<String, dynamic> m) => LeadFunnelRow(
        status: m['status'] as String,
        source: m['source'] as String,
        count: (m['cnt'] as num?)?.toInt() ?? 0,
      );

  final String status;
  final String source;
  final int count;
}

class BatchUtilizationRow {
  const BatchUtilizationRow({
    required this.batchId,
    required this.name,
    required this.enrolled,
    this.capacity,
  });

  factory BatchUtilizationRow.fromMap(Map<String, dynamic> m) =>
      BatchUtilizationRow(
        batchId: m['batch_id'] as String,
        name: m['name'] as String,
        capacity: m['capacity'] as int?,
        enrolled: (m['enrolled'] as num?)?.toInt() ?? 0,
      );

  final String batchId;
  final String name;
  final int? capacity;
  final int enrolled;

  double? get utilization =>
      capacity == null || capacity == 0 ? null : enrolled / capacity!;
}

class CollectionSummary {
  const CollectionSummary({
    required this.outstandingCount,
    required this.outstandingAmount,
    required this.overdueCount,
    required this.collectedTotal,
    required this.paidCount,
  });

  factory CollectionSummary.fromMap(Map<String, dynamic> m) =>
      CollectionSummary(
        outstandingCount: (m['outstanding_count'] as num?)?.toInt() ?? 0,
        outstandingAmount:
            (m['outstanding_amount'] as num?)?.toDouble() ?? 0.0,
        overdueCount: (m['overdue_count'] as num?)?.toInt() ?? 0,
        collectedTotal: (m['collected_total'] as num?)?.toDouble() ?? 0.0,
        paidCount: (m['paid_count'] as num?)?.toInt() ?? 0,
      );

  final int outstandingCount;
  final double outstandingAmount;
  final int overdueCount;
  final double collectedTotal;
  final int paidCount;
}

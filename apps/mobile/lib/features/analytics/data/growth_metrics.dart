import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/analytics/data/analytics_providers.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/students/data/student_providers.dart';

/// A single growth metric: a previous baseline and the current value, with
/// derived delta / percent / direction. Counts are whole numbers carried as
/// doubles so revenue (rupees) and headcounts share one shape.
class GrowthStat {
  const GrowthStat({required this.previous, required this.current});

  final double previous;
  final double current;

  double get delta => current - previous;

  /// Percent change vs the baseline; null when there is no baseline to grow
  /// from (previous == 0) — the UI shows "New" / "—" instead of a bogus %.
  double? get pct => previous > 0 ? (delta / previous) * 100 : null;

  bool get isUp => delta >= 0;
}

/// Owner/admin growth overview: students, coaches, centers (live total now vs
/// the total 30 days ago, by their joined/created dates) and revenue (latest
/// month vs the month before, from the analytics revenue view).
///
/// Computed client-side from the already-loaded list providers + the monthly
/// revenue view — no extra query. Headcounts use a rolling 30-day window so the
/// figure is always live and never distorted by a partial calendar month.
/// Approximate by design: a record deleted since it was created lowers the
/// historical baseline, which is acceptable for a directional growth cue.
class GrowthMetrics {
  const GrowthMetrics({
    required this.students,
    required this.coaches,
    required this.centers,
    required this.revenue,
  });

  final GrowthStat students;
  final GrowthStat coaches;
  final GrowthStat centers;

  /// Null until at least one month of revenue exists.
  final GrowthStat? revenue;
}

GrowthStat _countStat<T>(
  List<T> items,
  DateTime? Function(T) dateOf,
  DateTime cutoff,
) {
  final current = items.length.toDouble();
  // Records whose joined/created date predates the window are the baseline;
  // a missing date counts as "already there" (no growth contribution).
  final previous = items.where((e) {
    final d = dateOf(e);
    return d == null || d.isBefore(cutoff);
  }).length.toDouble();
  return GrowthStat(previous: previous, current: current);
}

/// Returns null while the underlying lists are still loading. Revenue is
/// optional (null until a month of data exists); the other three are required.
final growthMetricsProvider = Provider<GrowthMetrics?>((ref) {
  final students = ref.watch(studentsProvider).valueOrNull;
  final coaches = ref.watch(coachesProvider).valueOrNull;
  final centers = ref.watch(centersProvider).valueOrNull;
  final revenueMonths = ref.watch(revenueByMonthProvider).valueOrNull;
  if (students == null || coaches == null || centers == null) return null;

  // 30-day rolling window. DateTime.now() is device-local, matching how the
  // rest of the app computes dates (India-first single timezone).
  final cutoff = DateTime.now().subtract(const Duration(days: 30));

  GrowthStat? revenue;
  if (revenueMonths != null && revenueMonths.isNotEmpty) {
    // revenueByMonth is oldest-first; compare the latest month to the prior.
    final current = revenueMonths.last.collected;
    final previous = revenueMonths.length >= 2
        ? revenueMonths[revenueMonths.length - 2].collected
        : 0.0;
    revenue = GrowthStat(previous: previous, current: current);
  }

  return GrowthMetrics(
    students: _countStat(students, (s) => s.enrollmentDate, cutoff),
    // coachesProvider returns coaches AND trainers; "Coaches" growth counts
    // kind='coach' only so the headcount (and its baseline) isn't inflated.
    coaches: _countStat(
      coaches.where((c) => c.isCoach).toList(),
      (c) => c.joinDate,
      cutoff,
    ),
    centers: _countStat(centers, (c) => c.createdAt, cutoff),
    revenue: revenue,
  );
});

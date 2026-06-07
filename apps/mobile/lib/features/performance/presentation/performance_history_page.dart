import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/performance/data/performance.dart';
import 'package:playhub/features/performance/data/performance_providers.dart';
import 'package:playhub/features/performance/presentation/performance_detail_page.dart';
import 'package:playhub/features/performance/presentation/performance_form_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class PerformanceHistoryPage extends ConsumerWidget {
  const PerformanceHistoryPage({required this.student, this.batchId, super.key});

  final Student student;

  /// The batch this student was opened from, if any. Threaded into the new
  /// assessment so a trainer's record (which RLS requires to be batch-scoped via
  /// staff_on_batch) carries a batch_id instead of a NULL that RLS rejects.
  final String? batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assessmentsAsync =
        ref.watch(assessmentsForStudentProvider(student.id));
    final trend = ref.watch(performanceTrendProvider(student.id)).valueOrNull;
    final canRecord = ref.watch(capabilitiesProvider).recordPerformance;

    return Scaffold(
      appBar: AppBar(title: Text('Performance · ${student.fullName}')),
      body: assessmentsAsync.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () =>
              ref.invalidate(assessmentsForStudentProvider(student.id)),
        ),
        data: (list) {
          if (list.isEmpty) {
            // Single create path lives in the FAB; the empty state only
            // explains, it does not offer a duplicate CTA.
            return const AppEmptyState(
              icon: Icons.insights_outlined,
              title: 'No assessments yet',
              subtitle:
                  "Record this student's first assessment to start tracking.",
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(assessmentsForStudentProvider(student.id)),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (trend != null) ...[
                  _TrendCard(trend: trend),
                  const SizedBox(height: AppSpacing.xl),
                ],
                AppSectionHeader(
                  title: 'Assessments',
                  trailing: Text(
                    '${list.length}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _AssessmentTile(assessment: list[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: canRecord
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      PerformanceFormPage(student: student, batchId: batchId),
                ),
              ),
              icon: const Icon(Icons.add_chart_outlined),
              label: const Text('New assessment'),
            )
          : null,
    );
  }
}

/// Header callout: the recent average is the prominent headline metric, with
/// the supporting facts (window size, latest sport, last assessed) laid out
/// as labeled rows beside it.
class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trend});
  final Map<String, dynamic> trend;

  @override
  Widget build(BuildContext context) {
    final avg = (trend['avg_recent_score'] as num?)?.toDouble();
    final n = (trend['recent_assessments'] as num?)?.toInt() ?? 0;
    final lastDate = trend['last_assessed_date'] as String?;
    final sport = trend['latest_sport'] as String?;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutedSmall = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Prominent recent-average metric.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recent average',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  avg == null ? 'No score' : avg.toStringAsFixed(2),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: avg == null ? scheme.onSurfaceVariant : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('Across last $n assessments', style: mutedSmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          // Supporting context: latest sport + last assessed date.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (sport != null && sport.isNotEmpty)
                AppBadge(text: sport, tone: AppBadgeTone.brand),
              if (lastDate != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('Last $lastDate', style: mutedSmall),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AssessmentTile extends ConsumerWidget {
  const _AssessmentTile({required this.assessment});
  final PerformanceAssessment assessment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateStr =
        assessment.assessmentDate.toIso8601String().substring(0, 10);
    final sportLabel = ref.watch(sportDisplayProvider((
      sportId: assessment.sportId,
    )));
    final feedback = assessment.qualitativeFeedback;
    final hasFeedback = feedback != null && feedback.isNotEmpty;

    return AppListTile(
      wrapLeading: false,
      isThreeLine: hasFeedback,
      leading: _ScoreChip(score: assessment.overallScore),
      title: Text(sportLabel == '—' ? 'General' : sportLabel),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dateStr, style: theme.textTheme.bodySmall),
          if (hasFeedback)
            Text(
              feedback,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PerformanceDetailPage(assessment: assessment),
        ),
      ),
    );
  }
}

/// Prominent per-row score chip. Reads as a filled brand pill so the overall
/// score is the first thing the eye lands on; an unscored row shows a clear
/// "n/a" rather than an ambiguous dash.
class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.score});
  final double? score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scored = score != null;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scored
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        scored ? score!.toStringAsFixed(1) : 'n/a',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: AppType.bold,
          color: scored ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

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
  const PerformanceHistoryPage({required this.student, super.key});

  final Student student;

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
            return AppEmptyState(
              icon: Icons.insights_outlined,
              title: 'No assessments yet',
              subtitle:
                  "Record this student's first assessment to start tracking.",
              actionLabel: canRecord ? 'New assessment' : null,
              onAction: canRecord
                  ? () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) =>
                              PerformanceFormPage(student: student),
                        ),
                      )
                  : null,
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
                  const SizedBox(height: AppSpacing.md),
                ],
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final a in list) _AssessmentTile(assessment: a),
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
                  builder: (_) => PerformanceFormPage(student: student),
                ),
              ),
              icon: const Icon(Icons.add_chart_outlined),
              label: const Text('New assessment'),
            )
          : null,
    );
  }
}

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
    final mutedSmall = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return AppCard(
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Last $n assessments', style: mutedSmall),
              Text(
                avg == null ? '—' : avg.toStringAsFixed(2),
                style: theme.textTheme.headlineMedium,
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (sport != null)
                Text(sport, style: theme.textTheme.bodyMedium),
              if (lastDate != null) Text(lastDate, style: mutedSmall),
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
    final dateStr = assessment.assessmentDate.toIso8601String().substring(0, 10);
    final sportLabel = ref.watch(sportDisplayProvider((
      sportId: assessment.sportId,
    )));
    return AppListTile(
      wrapLeading: false,
      leading: CircleAvatar(
        child: Text(
          assessment.overallScore == null
              ? '—'
              : assessment.overallScore!.toStringAsFixed(1),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(sportLabel == '—' ? 'general' : sportLabel),
      subtitle: Text(
        [
          dateStr,
          if (assessment.qualitativeFeedback != null &&
              assessment.qualitativeFeedback!.isNotEmpty)
            assessment.qualitativeFeedback!,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PerformanceDetailPage(assessment: assessment),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/performance/data/performance.dart';
import 'package:playhub/features/performance/data/performance_providers.dart';
import 'package:playhub/features/performance/presentation/performance_detail_page.dart';
import 'package:playhub/features/performance/presentation/performance_form_page.dart';
import 'package:playhub/features/students/data/student.dart';

class PerformanceHistoryPage extends ConsumerWidget {
  const PerformanceHistoryPage({required this.student, super.key});

  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assessmentsAsync =
        ref.watch(assessmentsForStudentProvider(student.id));
    final trend = ref.watch(performanceTrendProvider(student.id)).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text('Performance · ${student.fullName}')),
      body: assessmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () async => ref
                .invalidate(assessmentsForStudentProvider(student.id)),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (trend != null) _TrendCard(trend: trend),
                const SizedBox(height: 8),
                Card(
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => PerformanceFormPage(student: student),
          ),
        ),
        icon: const Icon(Icons.add_chart_outlined),
        label: const Text('New assessment'),
      ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Last $n assessments',
                    style: Theme.of(context).textTheme.bodySmall),
                Text(
                  avg == null ? '—' : avg.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (sport != null) Text(sport),
                if (lastDate != null)
                  Text(lastDate,
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile({required this.assessment});
  final PerformanceAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final dateStr = assessment.assessmentDate.toIso8601String().substring(0, 10);
    return ListTile(
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
      title: Text(assessment.sport ?? 'general'),
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
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PerformanceDetailPage(assessment: assessment),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insights_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'No assessments yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap "New assessment" to record this student\'s first.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

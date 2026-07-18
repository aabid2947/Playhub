import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/insights/data/ai_insights.dart';
import 'package:playhub/features/insights/data/ai_insights_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Dedicated AI-insights screen for one student: an AI-written summary of
/// attendance consistency, performance trend, and focus areas. Reached from the
/// coach's student page and the parent/student dashboard. The model only ever
/// sees de-identified metrics (see the `ai-insights` edge function); the name
/// shown here stays on-device.
class StudentInsightsPage extends ConsumerWidget {
  const StudentInsightsPage({
    required this.studentId,
    required this.studentName,
    super.key,
  });

  final String studentId;
  final String studentName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentInsightProvider(studentId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI insights'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Regenerate',
            onPressed: async.isLoading
                ? null
                : () => ref.invalidate(studentInsightProvider(studentId)),
          ),
        ],
      ),
      body: async.when(
        loading: () => _GeneratingState(name: studentName),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(studentInsightProvider(studentId)),
        ),
        data: (insight) => _InsightView(name: studentName, insight: insight),
      ),
    );
  }
}

/// Loading state framed as "analysing", so the wait reads as deliberate work
/// rather than a generic spinner.
class _GeneratingState extends StatelessWidget {
  const _GeneratingState({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLoading(),
            const SizedBox(height: AppSpacing.md),
            Text(
              "Analysing $name's progress…",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightView extends StatelessWidget {
  const _InsightView({required this.name, required this.insight});
  final String name;
  final StudentInsight insight;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _Header(name: name),
        const SizedBox(height: AppSpacing.lg),
        if (insight.summary.isNotEmpty)
          _InsightCard(
            icon: Icons.summarize_outlined,
            title: 'Summary',
            body: insight.summary,
          ),
        if (insight.attendance.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _InsightCard(
            icon: Icons.event_available_outlined,
            title: 'Attendance',
            body: insight.attendance,
          ),
        ],
        if (insight.performance.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _InsightCard(
            icon: Icons.insights_outlined,
            title: 'Performance',
            body: insight.performance,
          ),
        ],
        if (insight.focus.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _FocusCard(items: insight.focus),
        ],
        const SizedBox(height: AppSpacing.lg),
        const _AiDisclaimer(),
      ],
    );
  }
}

/// Brand-tinted lockup that frames the screen as AI-generated, for [name].
class _Header extends StatelessWidget {
  const _Header({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.auto_awesome, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Insights for $name', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Based on the last 90 days of attendance and assessments.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One titled insight section (icon + heading + paragraph).
class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: AppType.semibold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// "Things to work on" — each item as a checked-bullet row.
class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Focus areas',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: AppType.semibold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.arrow_right_alt,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Footer note — sets expectations that this is AI-generated.
class _AiDisclaimer extends StatelessWidget {
  const _AiDisclaimer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.auto_awesome,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Generated by AI from attendance and assessment data. '
            'It can be imperfect — use your judgement.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

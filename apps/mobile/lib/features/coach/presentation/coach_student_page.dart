import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/chat/presentation/message_parent_button.dart';
import 'package:playhub/features/parent/data/parent_providers.dart';
import 'package:playhub/features/performance/presentation/performance_history_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Read-only student summary page for the coach context. Avoids the
/// admin-only sections of StudentFormPage (fees, discounts, documents).
/// Coaches see basic profile, attendance summary, and a path into
/// performance history (where they can record new assessments).
class CoachStudentPage extends ConsumerWidget {
  const CoachStudentPage({required this.student, super.key});
  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendance = ref.watch(studentAttendanceProvider(student.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(student.fullName),
        actions: [MessageParentButton(studentId: student.id)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.fullName,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                Builder(builder: (_) {
                  final sportLabel = ref.watch(sportDisplayProvider((
                    sportId: student.sportId,
                  )));
                  return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (sportLabel != '—') AppBadge(text: sportLabel),
                      if (student.skillLevel != null)
                        AppBadge(
                          text: student.skillLevel!,
                          tone: AppBadgeTone.info,
                        ),
                    ],
                  );
                }),
                if (student.parentName.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('Parent: ${student.parentName}',
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
                if (student.parentPhone != null)
                  Text('Phone: ${student.parentPhone}',
                      style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Attendance — last 60 days',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                attendance.when(
                  loading: () => const AppSkeleton(width: 180),
                  error: (e, _) => Text(
                    friendlyError(e),
                    style:
                        TextStyle(color: AppSemanticColors.of(context).danger),
                  ),
                  data: (days) {
                    if (days.isEmpty) {
                      return Text(
                        'No records yet',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      );
                    }
                    final present =
                        days.where((d) => d.status == 'present').length;
                    final pct =
                        (present * 100 / days.length).toStringAsFixed(0);
                    return Text('$present / ${days.length} present ($pct%)');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: EdgeInsets.zero,
            child: AppListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Performance assessments'),
              subtitle:
                  const Text('View history or record a new assessment'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => PerformanceHistoryPage(student: student),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

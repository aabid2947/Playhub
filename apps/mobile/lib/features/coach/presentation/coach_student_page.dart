import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/chat/presentation/message_parent_button.dart';
import 'package:playhub/features/parent/data/parent_providers.dart';
import 'package:playhub/features/performance/presentation/performance_history_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/students/data/student.dart';

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
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(student.fullName,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Builder(builder: (_) {
                    final sportLabel = ref.watch(sportDisplayProvider((
                      sportId: student.sportId,
                    )));
                    return Wrap(spacing: 8, children: [
                      if (sportLabel != '—') Chip(label: Text(sportLabel)),
                      if (student.skillLevel != null)
                        Chip(label: Text(student.skillLevel!)),
                    ]);
                  }),
                  if (student.parentName.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Parent: ${student.parentName}',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  if (student.parentPhone != null)
                    Text('Phone: ${student.parentPhone}',
                        style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Attendance — last 60 days',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  attendance.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Error: $e'),
                    data: (days) {
                      if (days.isEmpty) {
                        return const Text('No records yet');
                      }
                      final present =
                          days.where((d) => d.status == 'present').length;
                      final pct = (present * 100 / days.length)
                          .toStringAsFixed(0);
                      return Text(
                          '$present / ${days.length} present ($pct%)');
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('Performance assessments'),
              subtitle:
                  const Text('View history or record a new assessment'),
              trailing: const Icon(Icons.chevron_right),
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

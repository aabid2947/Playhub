import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/batches/presentation/batch_form_page.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';

class BatchDetailPage extends ConsumerWidget {
  const BatchDetailPage({required this.batch, super.key});

  final Batch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enrollmentsAsync = ref.watch(batchEnrollmentsProvider(batch.id));
    final studentsAsync = ref.watch(studentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(batch.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit batch',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => BatchFormPage(existing: batch),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    batch.schedule.summary,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (batch.sport != null) batch.sport!,
                      if (batch.ageGroup != null) batch.ageGroup!,
                      if (batch.skillLevel != null) batch.skillLevel!,
                      if (batch.capacity != null)
                        '${batch.enrolledCount}/${batch.capacity} enrolled'
                      else
                        '${batch.enrolledCount} enrolled',
                      if (batch.fees != null) '₹${batch.fees!.toStringAsFixed(0)}',
                    ].join(' • '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Enrolled students',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Enroll'),
                onPressed: () async {
                  final students = studentsAsync.valueOrNull ?? const [];
                  final enrolled =
                      enrollmentsAsync.valueOrNull ?? const [];
                  final enrolledIds =
                      enrolled.map((e) => e.studentId).toSet();
                  final candidates = students
                      .where((s) => !enrolledIds.contains(s.id))
                      .toList();
                  await _showEnrollSheet(context, ref, candidates);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          enrollmentsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (enrollments) {
              if (enrollments.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No students enrolled yet.')),
                );
              }
              final byId = {
                for (final s in (studentsAsync.valueOrNull ?? const <Student>[]))
                  s.id: s,
              };
              return Card(
                child: Column(
                  children: [
                    for (final e in enrollments)
                      _EnrollmentTile(
                        enrollment: e,
                        student: byId[e.studentId],
                        onWithdraw: () async {
                          await withdrawEnrollment(
                            ref,
                            enrollmentId: e.id,
                            batchId: batch.id,
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showEnrollSheet(
    BuildContext context,
    WidgetRef ref,
    List<Student> candidates,
  ) async {
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All your students are already enrolled.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: candidates.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = candidates[i];
            return ListTile(
              title: Text(s.fullName),
              subtitle: Text(s.parentName),
              trailing: const Icon(Icons.add),
              onTap: () async {
                await enrollStudent(
                  ref,
                  batchId: batch.id,
                  studentId: s.id,
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            );
          },
        ),
      ),
    );
  }
}

class _EnrollmentTile extends StatelessWidget {
  const _EnrollmentTile({
    required this.enrollment,
    required this.student,
    required this.onWithdraw,
  });

  final Enrollment enrollment;
  final Student? student;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final name = student?.fullName ?? '(unknown student)';
    return ListTile(
      leading: const Icon(Icons.person_outline),
      title: Text(name),
      subtitle: Text(enrollment.status),
      trailing: enrollment.status == 'withdrawn'
          ? null
          : IconButton(
              tooltip: 'Withdraw',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: onWithdraw,
            ),
    );
  }
}

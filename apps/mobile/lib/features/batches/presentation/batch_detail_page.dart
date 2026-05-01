import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/attendance/presentation/attendance_marking_page.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/batches/presentation/batch_form_page.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';

class BatchDetailPage extends ConsumerWidget {
  const BatchDetailPage({required this.batch, super.key});

  final Batch batch;

  bool _atCapacity() {
    final cap = batch.capacity;
    if (cap == null) return false;
    return batch.enrolledCount >= cap;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enrollmentsAsync = ref.watch(batchEnrollmentsProvider(batch.id));
    final studentsAsync = ref.watch(studentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(batch.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Mark attendance',
            onPressed: () {
              final today = DateTime.now();
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => AttendanceMarkingPage(
                    batch: batch,
                    date: DateTime(today.year, today.month, today.day),
                  ),
                ),
              );
            },
          ),
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
                      if (batch.fees != null)
                        '₹${batch.fees!.toStringAsFixed(0)}',
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
                _atCapacity() ? 'At capacity' : 'Enrolled students',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                icon: Icon(
                  _atCapacity()
                      ? Icons.queue_outlined
                      : Icons.person_add_outlined,
                  size: 18,
                ),
                label: Text(_atCapacity() ? 'Add to waitlist' : 'Enroll'),
                onPressed: () async {
                  final students = studentsAsync.valueOrNull ?? const [];
                  final enrolled =
                      enrollmentsAsync.valueOrNull ?? const [];
                  final activeIds = enrolled
                      .where((e) => e.status != 'withdrawn')
                      .map((e) => e.studentId)
                      .toSet();
                  final candidates = students
                      .where((s) => !activeIds.contains(s.id))
                      .toList();
                  await _showEnrollSheet(
                    context,
                    ref,
                    candidates,
                    waitlist: _atCapacity(),
                  );
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
                for (final s
                    in (studentsAsync.valueOrNull ?? const <Student>[]))
                  s.id: s,
              };
              final active =
                  enrollments.where((e) => e.status == 'active').toList();
              final waitlisted = enrollments
                  .where((e) => e.status == 'waitlisted')
                  .toList();
              final withdrawn = enrollments
                  .where((e) => e.status == 'withdrawn')
                  .toList();

              return Column(
                children: [
                  if (active.isNotEmpty)
                    _EnrollmentSection(
                      title: 'Active',
                      enrollments: active,
                      byStudent: byId,
                      onWithdraw: (e) async {
                        await withdrawEnrollment(
                          ref,
                          enrollmentId: e.id,
                          batchId: batch.id,
                        );
                      },
                      onTransfer: (e) =>
                          _showTransferSheet(context, ref, e),
                    ),
                  if (waitlisted.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _EnrollmentSection(
                      title: 'Waitlist (${waitlisted.length})',
                      enrollments: waitlisted,
                      byStudent: byId,
                      onWithdraw: (e) async {
                        await withdrawEnrollment(
                          ref,
                          enrollmentId: e.id,
                          batchId: batch.id,
                        );
                      },
                      onPromote: _atCapacity()
                          ? null
                          : (e) async {
                              await promoteEnrollment(
                                ref,
                                enrollmentId: e.id,
                                batchId: batch.id,
                              );
                            },
                    ),
                  ],
                  if (withdrawn.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _EnrollmentSection(
                      title: 'Withdrawn (${withdrawn.length})',
                      enrollments: withdrawn,
                      byStudent: byId,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showTransferSheet(
    BuildContext context,
    WidgetRef ref,
    Enrollment enrollment,
  ) async {
    final batches = ref.read(batchesProvider).valueOrNull ?? const <Batch>[];
    final targets = batches.where((b) => b.id != batch.id).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other batches to transfer to.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<Batch>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: targets.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            if (i == 0) {
              return const ListTile(
                dense: true,
                title: Text('Transfer to which batch?'),
              );
            }
            final b = targets[i - 1];
            final cap = b.capacity;
            final atCap = cap != null && b.enrolledCount >= cap;
            return ListTile(
              title: Text(b.name),
              subtitle: Text(
                '${b.schedule.summary}'
                '${atCap ? '  •  at capacity (will go on waitlist)' : ''}',
              ),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () => Navigator.of(ctx).pop(b),
            );
          },
        ),
      ),
    );
    if (picked == null) return;
    try {
      await transferEnrollment(
        ref,
        enrollmentId: enrollment.id,
        fromBatchId: batch.id,
        toBatchId: picked.id,
      );
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer failed: $e')),
        );
      }
    }
  }

  Future<void> _showEnrollSheet(
    BuildContext context,
    WidgetRef ref,
    List<Student> candidates, {
    required bool waitlist,
  }) async {
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All your students are already enrolled.'),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: candidates.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            if (i == 0) {
              return ListTile(
                dense: true,
                title: Text(
                  waitlist
                      ? 'Batch is at capacity — students will be added to the waitlist.'
                      : 'Pick a student to enroll',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
              );
            }
            final s = candidates[i - 1];
            return ListTile(
              title: Text(s.fullName),
              subtitle: Text(s.parentName),
              trailing: Icon(waitlist ? Icons.queue_outlined : Icons.add),
              onTap: () async {
                await enrollStudent(
                  ref,
                  batchId: batch.id,
                  studentId: s.id,
                  status: waitlist ? 'waitlisted' : 'active',
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

class _EnrollmentSection extends StatelessWidget {
  const _EnrollmentSection({
    required this.title,
    required this.enrollments,
    required this.byStudent,
    this.onWithdraw,
    this.onPromote,
    this.onTransfer,
  });

  final String title;
  final List<Enrollment> enrollments;
  final Map<String, Student> byStudent;
  final Future<void> Function(Enrollment)? onWithdraw;
  final Future<void> Function(Enrollment)? onPromote;
  final Future<void> Function(Enrollment)? onTransfer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Card(
          child: Column(
            children: [
              for (final e in enrollments)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(byStudent[e.studentId]?.fullName ??
                      '(unknown student)'),
                  subtitle: Text(e.status),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onPromote != null)
                        IconButton(
                          tooltip: 'Promote to active',
                          icon: const Icon(Icons.upgrade),
                          onPressed: () => onPromote!(e),
                        ),
                      if (onTransfer != null)
                        IconButton(
                          tooltip: 'Transfer to another batch',
                          icon: const Icon(Icons.swap_horiz),
                          onPressed: () => onTransfer!(e),
                        ),
                      if (onWithdraw != null)
                        IconButton(
                          tooltip: 'Withdraw',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => onWithdraw!(e),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

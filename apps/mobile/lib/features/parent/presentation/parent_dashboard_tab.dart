import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/academy/data/academy_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/billing/data/razorpay_checkout.dart';
import 'package:playhub/features/events/presentation/events_page.dart';
import 'package:playhub/features/parent/data/parent_providers.dart';
import 'package:playhub/features/students/data/student.dart';

/// Parent / student dashboard. Shows linked-students switcher, attendance
/// calendar (last 60 days), performance line, and outstanding dues.
/// Razorpay checkout for outstanding invoices is triggered from this view.
class ParentDashboardTab extends ConsumerStatefulWidget {
  const ParentDashboardTab({super.key});

  @override
  ConsumerState<ParentDashboardTab> createState() =>
      _ParentDashboardTabState();
}

class _ParentDashboardTabState extends ConsumerState<ParentDashboardTab> {
  String? _selectedStudentId;

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(myLinkedStudentsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(supabaseClientProvider).auth.signOut(),
          ),
        ],
      ),
      body: studentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (students) {
          if (students.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No students linked to your account yet. Ask the academy '
                  'admin to link you.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          _selectedStudentId ??= students.first.id;
          final selected = students.firstWhere(
            (s) => s.id == _selectedStudentId,
            orElse: () => students.first,
          );
          return RefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(myLinkedStudentIdsProvider)
                ..invalidate(myLinkedStudentsProvider)
                ..invalidate(studentAttendanceProvider(selected.id))
                ..invalidate(studentPerformanceProvider(selected.id))
                ..invalidate(studentOutstandingDuesProvider(selected.id))
                ..invalidate(myLinkedStudentBatchesProvider(selected.id));
            },
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (students.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SegmentedButton<String>(
                      segments: [
                        for (final s in students)
                          ButtonSegment<String>(
                              value: s.id,
                              label: Text(s.firstName)),
                      ],
                      selected: {selected.id},
                      onSelectionChanged: (sel) =>
                          setState(() => _selectedStudentId = sel.first),
                    ),
                  ),
                _StudentHeader(student: selected),
                const SizedBox(height: 12),
                _BatchesCard(studentId: selected.id),
                const SizedBox(height: 12),
                _AttendanceCard(studentId: selected.id),
                const SizedBox(height: 12),
                _PerformanceCard(studentId: selected.id),
                const SizedBox(height: 12),
                _OutstandingCard(studentId: selected.id),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.emoji_events_outlined),
                    title: const Text('Events'),
                    subtitle: const Text('Browse + register for tournaments'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(builder: (_) => const EventsPage()),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StudentHeader extends StatelessWidget {
  const _StudentHeader({required this.student});
  final Student student;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              child: Text(
                student.firstName.isEmpty ? '?' : student.firstName[0],
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${student.firstName} ${student.lastName}',
                      style: Theme.of(context).textTheme.titleLarge),
                  if (student.sport != null)
                    Text(student.sport!,
                        style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchesCard extends ConsumerWidget {
  const _BatchesCard({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myLinkedStudentBatchesProvider(studentId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Batches',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
              error: (e, _) => Text('Error: $e'),
              data: (rows) {
                if (rows.isEmpty) return const Text('No active batches');
                return Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in rows)
                      Chip(
                        avatar: const Icon(Icons.schedule, size: 16),
                        label: Text(r.batchName +
                            (r.sport != null ? ' • ${r.sport}' : '')),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceCard extends ConsumerWidget {
  const _AttendanceCard({required this.studentId});
  final String studentId;

  Color _color(BuildContext c, String status) {
    switch (status) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Theme.of(c).colorScheme.error;
      case 'late':
        return Colors.orange;
      case 'excused':
        return Colors.blueGrey;
    }
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentAttendanceProvider(studentId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Attendance — last 60 days',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            async.when(
              loading: () =>
                  const Padding(
                      padding: EdgeInsets.all(8),
                      child: LinearProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (days) {
                if (days.isEmpty) return const Text('No records yet');
                final total = days.length;
                final present =
                    days.where((d) => d.status == 'present').length;
                final pct = (present * 100 / total).toStringAsFixed(0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final d in days)
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: _color(context, d.status),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('$present / $total present ($pct%)'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PerformanceCard extends ConsumerWidget {
  const _PerformanceCard({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentPerformanceProvider(studentId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Performance trend',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            async.when(
              loading: () => const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (pts) {
                if (pts.isEmpty) {
                  return const Text('No assessments yet');
                }
                return SizedBox(
                  height: 80,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _SparkPainter(
                      points: pts.map((p) => p.score).toList(),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.points, required this.color});
  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2;
      canvas.drawCircle(
          Offset(size.width / 2, size.height / 2), 3, paint);
      return;
    }
    final maxY = 10.0; // overall_score is 0..10
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = size.width * (i / (points.length - 1));
      final y = size.height - (points[i] / maxY) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.points != points;
}

class _OutstandingCard extends ConsumerWidget {
  const _OutstandingCard({required this.studentId});
  final String studentId;

  Future<void> _payInvoice(
      BuildContext context, WidgetRef ref, String invoiceId) async {
    final client = ref.read(supabaseClientProvider);
    final profile = ref.read(currentProfileProvider).valueOrNull;
    final academy = ref.read(myAcademyProvider).valueOrNull;
    final checkout = RazorpayCheckout(client);
    try {
      final result = await checkout.payInvoice(
        invoiceId: invoiceId,
        academyName: academy?.name ?? 'PlayHub',
        prefillEmail: profile?.email,
        prefillContact: profile?.phone,
      );
      if (!context.mounted) return;
      switch (result) {
        case CheckoutSuccess():
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Payment received')),
          );
          // Webhook will update the invoice; refresh the dues list so the
          // row drops out without waiting for the user to pull-to-refresh.
          ref.invalidate(studentOutstandingDuesProvider(studentId));
        case CheckoutExternalWallet(:final walletName):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Continuing in $walletName…')),
          );
        case CheckoutFailure(:final message):
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment failed: $message')),
          );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentOutstandingDuesProvider(studentId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Outstanding dues',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            async.when(
              loading: () => const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (rows) {
                if (rows.isEmpty) {
                  return const Text('Nothing due 🎉');
                }
                return Column(
                  children: [
                    for (final r in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(r.invoiceNumber),
                        subtitle: Text(
                            'Due ${r.dueDate.year}-'
                            '${r.dueDate.month.toString().padLeft(2, '0')}-'
                            '${r.dueDate.day.toString().padLeft(2, '0')}'
                            '  •  ${r.status}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('₹${r.balance.toStringAsFixed(0)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium),
                            FilledButton.tonal(
                              onPressed: () =>
                                  _payInvoice(context, ref, r.invoiceId),
                              child: const Text('Pay'),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

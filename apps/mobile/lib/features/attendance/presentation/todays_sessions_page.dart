import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/attendance/data/attendance_providers.dart';
import 'package:playhub/features/attendance/presentation/attendance_marking_page.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';

/// Coach (and admin) entry point for daily attendance — chronological list
/// of today's batches. Tap → AttendanceMarkingPage.
class TodaysSessionsPage extends ConsumerWidget {
  const TodaysSessionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batchesAsync = ref.watch(todaysBatchesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Today's sessions")),
      body: batchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (batches) {
          if (batches.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(batchesProvider)
                ..invalidate(todaysBatchesProvider);
            },
            child: ListView.separated(
              itemCount: batches.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) =>
                  _SessionTile(batch: batches[i]),
            ),
          );
        },
      ),
    );
  }
}

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.batch});
  final Batch batch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final ymd = DateTime(today.year, today.month, today.day);
    final attendanceAsync = ref.watch(attendanceForBatchProvider(
      AttendanceKey(batchId: batch.id, date: ymd),
    ));

    final markedCount = attendanceAsync.valueOrNull?.length ?? 0;
    final total = batch.enrolledCount;
    final allMarked = markedCount > 0 && markedCount >= total && total > 0;
    final sportLabel = ref.watch(sportDisplayProvider((
      sportId: batch.sportId,
    )));

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: allMarked
            ? Colors.green.withValues(alpha: 0.15)
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Icon(
          allMarked ? Icons.check : Icons.schedule_outlined,
          color: allMarked ? Colors.green : null,
        ),
      ),
      title: Text(batch.name),
      subtitle: Text(
        [
          batch.schedule.summary,
          if (sportLabel != '—') sportLabel,
        ].join(' • '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$markedCount/$total',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'marked',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AttendanceMarkingPage(batch: batch, date: ymd),
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
            const Icon(Icons.event_available_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'No sessions scheduled for today',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Active batches whose schedule includes today appear here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

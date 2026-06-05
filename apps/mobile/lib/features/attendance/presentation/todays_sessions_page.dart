import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/attendance/data/attendance_providers.dart';
import 'package:playhub/features/attendance/presentation/attendance_marking_page.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(todaysBatchesProvider),
        ),
        data: (batches) {
          if (batches.isEmpty) {
            return const AppEmptyState(
              icon: Icons.event_available_outlined,
              title: 'No sessions scheduled for today',
              subtitle:
                  'Active batches whose schedule includes today appear here.',
            );
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
              itemBuilder: (context, i) => _SessionTile(batch: batches[i]),
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
    final scheme = Theme.of(context).colorScheme;
    final semantics = AppSemanticColors.of(context);
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

    return AppListTile(
      wrapLeading: false,
      leading: CircleAvatar(
        backgroundColor:
            allMarked ? semantics.successContainer : scheme.surfaceContainerHigh,
        child: Icon(
          allMarked ? Icons.check : Icons.schedule_outlined,
          color: allMarked ? semantics.success : scheme.onSurfaceVariant,
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

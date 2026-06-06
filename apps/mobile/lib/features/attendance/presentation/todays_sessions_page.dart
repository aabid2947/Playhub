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
                  'Active batches whose schedule includes today appear here, '
                  'ready for you to mark attendance.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(batchesProvider)
                ..invalidate(todaysBatchesProvider);
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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
    final today = DateTime.now();
    final ymd = DateTime(today.year, today.month, today.day);
    final attendanceAsync = ref.watch(
      attendanceForBatchProvider(AttendanceKey(batchId: batch.id, date: ymd)),
    );

    final markedCount = attendanceAsync.valueOrNull?.length ?? 0;
    final total = batch.enrolledCount;
    final isLoadingMarks =
        attendanceAsync.isLoading && !attendanceAsync.hasValue;

    final sportLabel = ref.watch(
      sportDisplayProvider((sportId: batch.sportId)),
    );

    final progress = _SessionProgress.resolve(
      marked: markedCount,
      total: total,
      isLoading: isLoadingMarks,
    );

    return AppListTile(
      wrapLeading: false,
      leading: _ProgressIndicatorLeading(progress: progress),
      title: Text(batch.name),
      subtitle: Text(
        [
          batch.schedule.summary,
          if (sportLabel != '—') sportLabel,
        ].join(' • '),
      ),
      trailing: _SessionStatus(progress: progress),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AttendanceMarkingPage(batch: batch, date: ymd),
        ),
      ),
    );
  }
}

/// The marking state of one session for today, with an unambiguous label and
/// tone that never relies on color alone. Disambiguates the two cases that the
/// old "0/0" conflated: a batch with **no students enrolled** vs. one that's
/// simply **not started** yet.
enum _SessionState { loading, noStudents, notStarted, inProgress, done }

class _SessionProgress {
  const _SessionProgress({
    required this.state,
    required this.marked,
    required this.total,
  });

  factory _SessionProgress.resolve({
    required int marked,
    required int total,
    required bool isLoading,
  }) {
    if (isLoading) {
      return _SessionProgress(
        state: _SessionState.loading,
        marked: marked,
        total: total,
      );
    }
    if (total == 0) {
      return _SessionProgress(
        state: _SessionState.noStudents,
        marked: marked,
        total: total,
      );
    }
    if (marked == 0) {
      return _SessionProgress(
        state: _SessionState.notStarted,
        marked: marked,
        total: total,
      );
    }
    if (marked >= total) {
      return _SessionProgress(
        state: _SessionState.done,
        marked: marked,
        total: total,
      );
    }
    return _SessionProgress(
      state: _SessionState.inProgress,
      marked: marked,
      total: total,
    );
  }

  final _SessionState state;
  final int marked;
  final int total;

  /// Determinate fraction for the ring; `null` when there's nothing to plot
  /// (loading, or no students enrolled).
  double? get fraction {
    if (state == _SessionState.loading || state == _SessionState.noStudents) {
      return null;
    }
    if (total == 0) return null;
    return (marked / total).clamp(0.0, 1.0);
  }

  /// Short, scannable badge label paired with the ring so the signal never
  /// rests on color alone.
  String get badgeLabel {
    switch (state) {
      case _SessionState.loading:
        return '…';
      case _SessionState.noStudents:
        return 'No students';
      case _SessionState.notStarted:
        return 'Not started';
      case _SessionState.inProgress:
        return 'In progress';
      case _SessionState.done:
        return 'Done';
    }
  }

  AppBadgeTone get badgeTone {
    switch (state) {
      case _SessionState.loading:
        return AppBadgeTone.neutral;
      case _SessionState.noStudents:
        return AppBadgeTone.neutral;
      case _SessionState.notStarted:
        return AppBadgeTone.warning;
      case _SessionState.inProgress:
        return AppBadgeTone.info;
      case _SessionState.done:
        return AppBadgeTone.success;
    }
  }
}

/// A determinate progress ring with a glanceable centre glyph — a neutral
/// brand cue, never the success-green dot that the old design used (which read
/// as a "present" status rather than "all marked").
class _ProgressIndicatorLeading extends StatelessWidget {
  const _ProgressIndicatorLeading({required this.progress});
  final _SessionProgress progress;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantics = AppSemanticColors.of(context);

    final Color ringColor;
    final Widget center;
    switch (progress.state) {
      case _SessionState.loading:
        ringColor = scheme.outlineVariant;
        center = SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: scheme.onSurfaceVariant,
          ),
        );
      case _SessionState.noStudents:
        ringColor = scheme.outlineVariant;
        center = Icon(
          Icons.person_off_outlined,
          size: 20,
          color: scheme.onSurfaceVariant,
        );
      case _SessionState.notStarted:
        ringColor = scheme.outlineVariant;
        center = Icon(
          Icons.schedule_outlined,
          size: 20,
          color: scheme.onSurfaceVariant,
        );
      case _SessionState.inProgress:
        ringColor = semantics.info;
        center = Text(
          '${progress.marked}',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurface,
                fontWeight: AppType.bold,
              ),
        );
      case _SessionState.done:
        ringColor = semantics.success;
        center = Icon(
          Icons.check_rounded,
          size: 22,
          color: semantics.success,
        );
    }

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Track + determinate arc. A null fraction draws an empty track only.
          SizedBox(
            width: _size,
            height: _size,
            child: CircularProgressIndicator(
              value: progress.fraction ?? 0,
              strokeWidth: 3,
              backgroundColor: scheme.surfaceContainerHighest,
              color: ringColor,
            ),
          ),
          center,
        ],
      ),
    );
  }
}

/// Trailing block: the marked/total ratio plus an unambiguous state badge.
class _SessionStatus extends StatelessWidget {
  const _SessionStatus({required this.progress});
  final _SessionProgress progress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (progress.state == _SessionState.noStudents)
          Text(
            'No roster',
            style: textTheme.titleMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          Text(
            '${progress.marked}/${progress.total} marked',
            style: textTheme.titleMedium,
          ),
        const SizedBox(height: AppSpacing.xs),
        AppBadge(text: progress.badgeLabel, tone: progress.badgeTone),
      ],
    );
  }
}

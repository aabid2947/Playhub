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
/// of today's batches under a v1 "Sports-Light" roster hero. Tap a session →
/// AttendanceMarkingPage.
class TodaysSessionsPage extends ConsumerWidget {
  const TodaysSessionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batchesAsync = ref.watch(todaysBatchesProvider);

    return Scaffold(
      body: batchesAsync.when(
        loading: () => const _SessionsScaffold(
          sessionCount: 0,
          studentCount: 0,
          markedCount: 0,
          child: AppSkeletonList(),
        ),
        error: (e, _) => _SessionsScaffold(
          sessionCount: 0,
          studentCount: 0,
          markedCount: 0,
          child: AppErrorView(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(todaysBatchesProvider),
          ),
        ),
        data: (batches) {
          final totalStudents =
              batches.fold<int>(0, (sum, b) => sum + b.enrolledCount);
          final fullyMarked = _fullyMarkedToday(ref, batches);

          final body = batches.isEmpty
              ? const AppEmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'No sessions scheduled for today',
                  subtitle:
                      'Active batches whose schedule includes today appear '
                      'here, ready for you to mark attendance.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSectionHeader(
                      title: 'Sessions',
                      icon: Icons.fact_check_outlined,
                      trailing: AppBadge(
                        text: '${batches.length}',
                        tone: AppBadgeTone.brand,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    for (final batch in batches) ...[
                      _SessionTile(batch: batch),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                  ],
                );

          return _SessionsScaffold(
            sessionCount: batches.length,
            studentCount: totalStudents,
            markedCount: fullyMarked,
            onRefresh: () async {
              ref
                ..invalidate(batchesProvider)
                ..invalidate(todaysBatchesProvider);
            },
            child: body,
          );
        },
      ),
    );
  }
}

/// Counts how many of today's sessions are **fully marked** by watching each
/// batch's attendance family from the page's build — so the hero summary stays
/// in sync as the user marks a session and returns. A session with no roster
/// (`enrolledCount == 0`) is never counted as complete.
int _fullyMarkedToday(WidgetRef ref, List<Batch> batches) {
  final today = DateTime.now();
  final ymd = DateTime(today.year, today.month, today.day);
  var done = 0;
  for (final batch in batches) {
    final total = batch.enrolledCount;
    if (total == 0) continue;
    final marked = ref
            .watch(
              attendanceForBatchProvider(
                AttendanceKey(batchId: batch.id, date: ymd),
              ),
            )
            .valueOrNull
            ?.length ??
        0;
    if (marked >= total) done++;
  }
  return done;
}

/// Shared chrome for every state: a brand roster hero (back button + date +
/// summary strip) with the body overlapping the band upward, v1-style.
class _SessionsScaffold extends StatelessWidget {
  const _SessionsScaffold({
    required this.sessionCount,
    required this.studentCount,
    required this.markedCount,
    required this.child,
    this.onRefresh,
  });

  final int sessionCount;
  final int studentCount;
  final int markedCount;
  final Widget child;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();

    final list = ListView(
      padding: EdgeInsets.zero,
      children: [
        AppGradientHeader(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppCircleIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Today's sessions",
                          style: theme.textTheme.titleLarge
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _prettyDate(today),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppHeroStatRow(
                stats: [
                  ('$sessionCount', 'Sessions'),
                  ('$markedCount/$sessionCount', 'Marked'),
                  ('$studentCount', 'Students'),
                ],
              ),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -AppSpacing.lg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: child,
          ),
        ),
      ],
    );

    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }

  static String _prettyDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const weekdays = [
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    ];
    return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }
}

/// One session as a soft-shadow [AppCard]: a progress ring → batch name +
/// schedule/sport subtitle → trailing "N/M marked" with an unambiguous state
/// badge. Tap → mark attendance.
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

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AttendanceMarkingPage(batch: batch, date: ymd),
        ),
      ),
      child: Row(
        children: [
          _ProgressIndicatorLeading(progress: progress),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  batch.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: AppType.bold,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    batch.schedule.summary,
                    if (sportLabel != '—') sportLabel,
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _SessionStatus(progress: progress),
        ],
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

  /// An optional glyph that reinforces the badge state without relying on color.
  IconData? get badgeIcon {
    switch (state) {
      case _SessionState.notStarted:
        return Icons.schedule_outlined;
      case _SessionState.inProgress:
        return Icons.timelapse_rounded;
      case _SessionState.done:
        return Icons.check_rounded;
      case _SessionState.loading:
      case _SessionState.noStudents:
        return null;
    }
  }
}

/// A determinate progress ring with a glanceable centre glyph — a neutral
/// brand cue, never the success-green dot that the old design used (which read
/// as a "present" status rather than "all marked").
class _ProgressIndicatorLeading extends StatelessWidget {
  const _ProgressIndicatorLeading({required this.progress});
  final _SessionProgress progress;

  static const double _size = 46;

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
            style: textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          Text(
            '${progress.marked}/${progress.total} marked',
            style: textTheme.titleSmall?.copyWith(fontWeight: AppType.bold),
          ),
        const SizedBox(height: AppSpacing.xs),
        AppBadge(
          text: progress.badgeLabel,
          tone: progress.badgeTone,
          icon: progress.badgeIcon,
        ),
      ],
    );
  }
}

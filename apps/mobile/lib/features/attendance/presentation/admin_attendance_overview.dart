import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/attendance/data/attendance.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/students/data/student.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How many activity rows are shown before the "load more" cue. Each tap on
/// the cue reveals another page of this size.
const _activityPageSize = 40;

/// Live attendance feed for admins. Subscribes to inserts/updates on
/// `attendance_records` for the current academy, today only, and surfaces
/// the latest changes as they land.
final _todaysAttendanceStreamProvider =
    StreamProvider.autoDispose<List<AttendanceRecord>>((ref) async* {
  final profile = await ref.watch(currentProfileProvider.future);
  final academyId = profile?.academyId;
  if (academyId == null) {
    yield const [];
    return;
  }
  final client = ref.read(supabaseClientProvider);
  final today = DateTime.now();
  final ymd = '${today.year.toString().padLeft(4, '0')}-'
      '${today.month.toString().padLeft(2, '0')}-'
      '${today.day.toString().padLeft(2, '0')}';

  // Initial snapshot
  final initial = await client
      .from('attendance_records')
      .select()
      .eq('academy_id', academyId)
      .eq('date', ymd)
      .order('updated_at', ascending: false);
  final state = <String, AttendanceRecord>{
    for (final r in (initial as List))
      (r as Map<String, dynamic>)['id'] as String:
          AttendanceRecord.fromMap(r),
  };
  yield state.values.toList()
    ..sort((a, b) =>
        (b.checkInTime ?? b.date).compareTo(a.checkInTime ?? a.date));

  // Realtime stream — Supabase realtime delivers row payloads on every
  // insert/update; we filter on academy + date client-side.
  final controller = StreamController<List<AttendanceRecord>>();
  final channel = client.channel('attendance-overview-$academyId');
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'attendance_records',
        callback: (payload) {
          final raw = payload.newRecord;
          if (raw.isEmpty) return;
          if (raw['academy_id'] != academyId) return;
          if (raw['date'] != ymd) return;
          if (payload.eventType == PostgresChangeEvent.delete) {
            state.remove(raw['id']);
          } else {
            state[raw['id'] as String] =
                AttendanceRecord.fromMap(raw);
          }
          if (!controller.isClosed) {
            controller.add(state.values.toList()
              ..sort((a, b) => (b.checkInTime ?? b.date)
                  .compareTo(a.checkInTime ?? a.date)));
          }
        },
      )
      .subscribe();

  ref.onDispose(() {
    controller.close();
    client.removeChannel(channel);
  });

  yield* controller.stream;
});

/// Admin live overview: total marked today, present/absent split, recent
/// activity feed, all updating in real-time as coaches mark attendance.
class AdminAttendanceOverview extends ConsumerStatefulWidget {
  const AdminAttendanceOverview({super.key});

  @override
  ConsumerState<AdminAttendanceOverview> createState() =>
      _AdminAttendanceOverviewState();
}

class _AdminAttendanceOverviewState
    extends ConsumerState<AdminAttendanceOverview> {
  /// Number of activity rows currently revealed. Grows on "load more".
  int _visibleCount = _activityPageSize;

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(_todaysAttendanceStreamProvider);
    final batches = ref.watch(batchesProvider).valueOrNull ?? const <Batch>[];
    final students =
        ref.watch(studentsProvider).valueOrNull ?? const <Student>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Live attendance')),
      body: feedAsync.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(_todaysAttendanceStreamProvider),
        ),
        data: (records) {
          final present = records
              .where((r) =>
                  r.status == AttendanceStatus.present ||
                  r.status == AttendanceStatus.late)
              .length;
          final absent = records
              .where((r) => r.status == AttendanceStatus.absent)
              .length;
          final excused = records
              .where((r) => r.status == AttendanceStatus.excused)
              .length;

          final semantics = AppSemanticColors.of(context);
          final visible = records.take(_visibleCount).toList();
          final hasMore = records.length > visible.length;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // KPI tiles — 2-up via Rows of Expanded so each tile sizes to its
              // content (a fixed GridView aspect ratio clips the value/label at
              // larger text scales). Theme-aware status accents (§3.4).
              Row(
                children: [
                  Expanded(
                    child: AppStatTile(
                      icon: Icons.fact_check_outlined,
                      label: 'Marked',
                      value: '${records.length}',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppStatTile(
                      icon: Icons.check_circle_outline,
                      label: 'Present',
                      value: '$present',
                      color: semantics.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: AppStatTile(
                      icon: Icons.cancel_outlined,
                      label: 'Absent',
                      value: '$absent',
                      color: semantics.danger,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppStatTile(
                      icon: Icons.event_busy_outlined,
                      label: 'Excused',
                      value: '$excused',
                      color: semantics.warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const AppSectionHeader(title: 'Activity'),
              if (records.isEmpty)
                const AppEmptyState(
                  icon: Icons.timeline_outlined,
                  title: 'No attendance yet',
                  subtitle:
                      'Marks appear here in real time as coaches take '
                      'attendance today.',
                )
              else ...[
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final r in visible)
                        AppListTile(
                          wrapLeading: false,
                          leading: _StatusDot(status: r.status),
                          title: Text(_studentName(r.studentId, students)),
                          subtitle: Text(
                            _subtitle(r, batches),
                          ),
                          trailing: AppBadge(
                            text: r.status.label,
                            tone: _toneFor(r.status),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _LoadMoreFooter(
                  shown: visible.length,
                  total: records.length,
                  hasMore: hasMore,
                  onLoadMore: () => setState(
                    () => _visibleCount += _activityPageSize,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _studentName(String id, List<Student> students) {
    for (final s in students) {
      if (s.id == id) return s.fullName;
    }
    return '(unknown student)';
  }

  String _batchName(String id, List<Batch> batches) {
    for (final b in batches) {
      if (b.id == id) return b.name;
    }
    return '(unknown batch)';
  }

  /// Batch name plus a check-in time when one was recorded, e.g.
  /// "Evening squad · 5:04 PM".
  String _subtitle(AttendanceRecord r, List<Batch> batches) {
    final batch = _batchName(r.batchId, batches);
    final time = r.checkInTime;
    if (time == null) return batch;
    return '$batch · ${_formatTime(time)}';
  }
}

/// 12-hour clock formatting without pulling in `intl` for one label.
String _formatTime(DateTime dt) {
  final local = dt.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

AppBadgeTone _toneFor(AttendanceStatus status) => switch (status) {
      AttendanceStatus.present => AppBadgeTone.success,
      AttendanceStatus.late => AppBadgeTone.warning,
      AttendanceStatus.absent => AppBadgeTone.danger,
      AttendanceStatus.excused => AppBadgeTone.info,
    };

/// Bottom-of-list cap cue: "Showing N of M" + an explicit Load more action,
/// so the silent cap reads as deliberate (§3.6).
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.shown,
    required this.total,
    required this.hasMore,
    required this.onLoadMore,
  });

  final int shown;
  final int total;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          'Showing $shown of $total',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (hasMore) ...[
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: onLoadMore,
            child: const Text('Load more'),
          ),
        ],
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final semantics = AppSemanticColors.of(context);
    final (color, bg, icon) = switch (status) {
      AttendanceStatus.present => (
          semantics.success,
          semantics.successContainer,
          Icons.check,
        ),
      AttendanceStatus.late => (
          semantics.warning,
          semantics.warningContainer,
          Icons.access_time,
        ),
      AttendanceStatus.absent => (
          semantics.danger,
          semantics.dangerContainer,
          Icons.close,
        ),
      AttendanceStatus.excused => (
          semantics.info,
          semantics.infoContainer,
          Icons.event_busy,
        ),
    };
    return CircleAvatar(
      radius: 16,
      backgroundColor: bg,
      child: Icon(icon, size: 16, color: color),
    );
  }
}

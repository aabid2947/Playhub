import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/attendance/presentation/attendance_marking_page.dart';
import 'package:playhub/features/attendance/presentation/todays_sessions_page.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/coach/data/coach_home_providers.dart';
import 'package:playhub/features/coaches/presentation/coaches_tab.dart';
import 'package:playhub/features/students/presentation/students_tab.dart';
import 'package:playhub/features/users/presentation/invite_user_sheet.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Home tab for the coach / head_coach / trainer shell.
///
/// Follows the §3.4 dashboard anatomy: a brand-gradient greeting hero, an
/// always-present KPI stat row (My batches / Students / Today) that survives the
/// not-yet-linked state without collapsing, a labeled attendance-trend section,
/// and an explicit empty state for "no sessions today".
///
/// The AppBar + account entry point live in the coach home shell; this tab
/// renders only the scrollable body.
class CoachHomeTab extends ConsumerWidget {
  const CoachHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final myCoach = ref.watch(myCoachRecordProvider);
    final stats = ref.watch(myCoachStatsProvider);
    final todays = ref.watch(myTodaysBatchesProvider);
    final caps = ref.watch(capabilitiesProvider);
    final isHeadCoach = profile?.role == 'head_coach';

    // Head coaches get academy-wide oversight via myBatchesProvider and don't
    // need a coaches.user_id link, so they never see the not-linked notice.
    final notLinked = !isHeadCoach && myCoach.valueOrNull == null;

    // "Manage" tiles, capability-gated (RLS is the real gate). head_coach gets
    // Students + Coaches + Invite; plain coach gets Invite (trainers); trainer
    // gets none → the whole section hides.
    final manageTiles = <Widget>[
      if (caps.manageStudents)
        AppListTile(
          leading: const Icon(Icons.group_add_outlined),
          title: const Text('Students'),
          subtitle: const Text('Add or edit students'),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Students')),
                body: const StudentsTab(),
              ),
            ),
          ),
        ),
      if (caps.manageCoaches)
        AppListTile(
          leading: const Icon(Icons.sports_outlined),
          title: const Text('Coaches'),
          subtitle: const Text('Add or edit coaches'),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Coaches')),
                body: const CoachesTab(),
              ),
            ),
          ),
        ),
      if (caps.canProvisionAnyone)
        AppListTile(
          leading: const Icon(Icons.person_add_alt_1_outlined),
          title: const Text('Invite staff'),
          subtitle: const Text('Coaches and trainers you manage'),
          onTap: () => showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const InviteUserSheet(),
          ),
        ),
    ];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
        ref
          ..invalidate(myCoachRecordProvider)
          ..invalidate(myBatchesProvider)
          ..invalidate(myTodaysBatchesProvider)
          ..invalidate(myCoachStatsProvider)
          ..invalidate(coachAttendanceTrendProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _GreetingHero(
            name: profile?.displayName ?? '...',
            role: profile?.role ?? '',
          ),
          const SizedBox(height: AppSpacing.lg),
          // KPI row is always present — even before a coach record is linked —
          // so the layout never collapses.
          _StatsRow(stats: stats),
          if (notLinked) ...[
            const SizedBox(height: AppSpacing.md),
            const _NotLinkedNotice(),
          ],
          if (manageTiles.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const AppSectionHeader(title: 'Manage'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < manageTiles.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    manageTiles[i],
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const AppSectionHeader(title: 'Daily ops'),
          AppCard(
            padding: EdgeInsets.zero,
            child: AppListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: const Text("Today's sessions"),
              subtitle: todays.when(
                loading: () => const Text('Loading…'),
                error: (e, _) => Text(friendlyError(e)),
                data: (list) => Text(
                  list.isEmpty
                      ? 'No batches scheduled for you today'
                      : '${list.length} ${list.length == 1 ? 'batch' : 'batches'} to mark',
                ),
              ),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const TodaysSessionsPage()),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const AppSectionHeader(title: 'Attendance trend'),
          const _AttendanceTrendCard(),
          const SizedBox(height: AppSpacing.lg),
          const AppSectionHeader(title: 'Today'),
          todays.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: AppLoading(),
            ),
            error: (e, _) => AppErrorView(
              message: friendlyError(e),
              onRetry: () => ref.invalidate(myTodaysBatchesProvider),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'No sessions today',
                  subtitle:
                      'You have no batches scheduled for today. Enjoy the '
                      'break or check tomorrow.',
                );
              }
              return Column(
                children: [
                  for (final b in list) ...[
                    _BatchRow(batch: b),
                    if (b != list.last)
                      const SizedBox(height: AppSpacing.md),
                  ],
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

/// Violet→magenta gradient greeting card. White-on-gradient text per §3.4.
class _GreetingHero extends StatelessWidget {
  const _GreetingHero({required this.name, required this.role});

  final String name;
  final String role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: const LinearGradient(
          colors: AppPalette.brandGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          const AppUserAvatar(size: 48, onGradient: true),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, $name',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                if (role.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    role.replaceAll('_', ' '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onPrimary.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Always-present KPI row: My batches / Students / Today. Loading and error
/// states render the same three tiles with placeholder values so the row keeps
/// its footprint and the dashboard below never jumps.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});
  final AsyncValue<CoachStats> stats;

  @override
  Widget build(BuildContext context) {
    // On loading/error, show a dash so the tiles never collapse the layout.
    final s = stats.valueOrNull;
    final batches = s == null ? '—' : '${s.batchCount}';
    final students = s == null ? '—' : '${s.studentCount}';
    final today = s == null ? '—' : '${s.todaysCount}';

    return Row(
      children: [
        Expanded(
          child: AppStatTile(
            icon: Icons.schedule,
            label: 'My batches',
            value: batches,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: AppStatTile(
            icon: Icons.group,
            label: 'Students',
            value: students,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: AppStatTile(
            icon: Icons.today,
            label: 'Today',
            value: today,
          ),
        ),
      ],
    );
  }
}

/// Shown to coach/trainer roles with no linked `coaches.user_id` record yet.
/// Sits below the KPI row so the stat tiles stay visible (just zeroed).
class _NotLinkedNotice extends StatelessWidget {
  const _NotLinkedNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantics = AppSemanticColors.of(context);
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.link_off_outlined, color: semantics.info),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Not linked to a coach profile yet',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Ask your academy admin to link your account to a coach '
                  'profile so your batches and students show up here.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceTrendCard extends ConsumerWidget {
  const _AttendanceTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(coachAttendanceTrendProvider);
    return AppCard(
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: LinearProgressIndicator(),
        ),
        error: (e, _) => Text(friendlyError(e)),
        data: (weeks) {
          if (weeks.isEmpty || weeks.every((w) => w.total == 0)) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attendance % · last 4 weeks',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Not enough data yet. Once you start marking attendance, '
                  'weekly trends appear here.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          }
          final primary = theme.colorScheme.primary;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Attendance % · last 4 weeks',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Share of present/late marks, by week.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 160,
                child: BarChart(
                  BarChartData(
                    maxY: 100,
                    minY: 0,
                    alignment: BarChartAlignment.spaceAround,
                    barGroups: [
                      for (var i = 0; i < weeks.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: weeks[i].pct,
                              color: primary,
                              width: 18,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(AppRadius.sm),
                              ),
                            ),
                          ],
                        ),
                    ],
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 25,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: theme.colorScheme.outlineVariant,
                        strokeWidth: 0.5,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          interval: 25,
                          getTitlesWidget: (v, _) => Text(
                            '${v.toInt()}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 18,
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i < 0 || i >= weeks.length) {
                              return const SizedBox.shrink();
                            }
                            final ws = weeks[i].weekStart;
                            return Padding(
                              padding: const EdgeInsets.only(top: AppSpacing.xs),
                              child: Text(
                                '${ws.day}/${ws.month}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, _, __, ___) {
                          final w = weeks[group.x];
                          return BarTooltipItem(
                            'Week of ${w.weekStart.day}/${w.weekStart.month}\n'
                            '${w.present}/${w.total}'
                            ' (${w.pct.toStringAsFixed(0)}%)',
                            theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onInverseSurface,
                                ) ??
                                TextStyle(
                                  color: theme.colorScheme.onInverseSurface,
                                ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.batch});
  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    return AppCard(
      padding: EdgeInsets.zero,
      child: AppListTile(
        leading: const Icon(Icons.group_work_outlined),
        title: Text(batch.name),
        subtitle: Text(batch.schedule.summary),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => AttendanceMarkingPage(batch: batch, date: today0),
          ),
        ),
      ),
    );
  }
}

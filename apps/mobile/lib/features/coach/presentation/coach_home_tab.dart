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

/// Home tab for the coach / head_coach / trainer shell — v1 "Sports-Light".
///
/// Follows the dashboard archetype: a brand-gradient greeting hero with an
/// always-present hero stat row (Today / Batches / Students) that survives the
/// not-yet-linked state without collapsing, a "Daily ops" quick-action grid, a
/// labeled attendance-trend section (fl_chart, recolored via colorScheme), and
/// today's batches under their own section.
///
/// The AppBar + account entry point live in the coach home shell; this tab
/// renders only the scrollable, app-bar-less body — the gradient hero is the
/// first scrollable element and the body overlaps it upward.
class CoachHomeTab extends ConsumerWidget {
  const CoachHomeTab({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  }

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

    final firstName =
        (profile?.displayName ?? '').split(' ').firstOrNull ?? 'there';
    final roleLabel = (profile?.role ?? '').replaceAll('_', ' ');

    // Hero headline metrics derived from the data the dashboard already loads
    // (CoachStats). A dash keeps the strip's footprint before data arrives.
    final s = stats.valueOrNull;
    final todayCount = s == null ? '—' : '${s.todaysCount}';
    final batchCount = s == null ? '—' : '${s.batchCount}';
    final studentCount = s == null ? '—' : '${s.studentCount}';

    // "Manage" destinations, capability-gated (RLS is the real gate). head_coach
    // gets Students + Coaches + Invite; plain coach gets Invite (trainers);
    // trainer gets none → the whole section hides.
    final manageRows = <Widget>[
      if (caps.manageStudents)
        _ManageTile(
          icon: Icons.group_add_outlined,
          tint: AppPalette.brandPrimary,
          title: 'Students',
          subtitle: 'Add or edit students',
          onTap: () => _push(
            context,
            Scaffold(
              appBar: AppBar(title: const Text('Students')),
              body: const StudentsTab(),
            ),
          ),
        ),
      if (caps.manageCoaches)
        _ManageTile(
          icon: Icons.sports_outlined,
          tint: AppPalette.accent,
          title: 'Coaches',
          subtitle: 'Add or edit coaches',
          onTap: () => _push(
            context,
            Scaffold(
              appBar: AppBar(title: const Text('Coaches')),
              body: const CoachesTab(),
            ),
          ),
        ),
      if (caps.canProvisionAnyone)
        _ManageTile(
          icon: Icons.person_add_alt_1_outlined,
          tint: AppPalette.categorySwatch[3],
          title: 'Invite staff',
          subtitle: 'Coaches and trainers you manage',
          onTap: () => showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const InviteUserSheet(),
          ),
        ),
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(myCoachRecordProvider)
          ..invalidate(myBatchesProvider)
          ..invalidate(myTodaysBatchesProvider)
          ..invalidate(myCoachStatsProvider)
          ..invalidate(coachAttendanceTrendProvider);
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Greeting hero with a role sub-line and an always-present stat strip.
          AppGradientHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hello, $firstName 👋',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: Colors.white),
                          ),
                          if (roleLabel.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.sports_handball_outlined,
                                  size: 15,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    roleLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.white
                                              .withValues(alpha: 0.85),
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const AppUserAvatar(size: 44, onGradient: true),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppHeroStatRow(
                  stats: [
                    (todayCount, 'Today'),
                    (batchCount, 'My batches'),
                    (studentCount, 'Students'),
                  ],
                ),
              ],
            ),
          ),
          // Body overlaps the hero band upward, v1-style.
          Transform.translate(
            offset: const Offset(0, -AppSpacing.lg),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (notLinked) ...[
                    const _NotLinkedNotice(),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  const AppSectionHeader(
                    title: 'Daily ops',
                    icon: Icons.event_available_outlined,
                  ),
                  todays.when(
                    loading: () => _TodaysSessionsCard(
                      subtitle: 'Loading…',
                      onTap: () =>
                          _push(context, const TodaysSessionsPage()),
                    ),
                    error: (e, _) => _TodaysSessionsCard(
                      subtitle: friendlyError(e),
                      onTap: () =>
                          _push(context, const TodaysSessionsPage()),
                    ),
                    data: (list) => _TodaysSessionsCard(
                      subtitle: list.isEmpty
                          ? 'Nothing scheduled today'
                          : '${list.length} '
                              '${list.length == 1 ? 'batch' : 'batches'} to mark',
                      badge: list.isEmpty ? null : '${list.length}',
                      onTap: () =>
                          _push(context, const TodaysSessionsPage()),
                    ),
                  ),
                  if (manageRows.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const AppSectionHeader(
                      title: 'Manage',
                      icon: Icons.tune_rounded,
                    ),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < manageRows.length; i++) ...[
                            manageRows[i],
                            if (i != manageRows.length - 1)
                              const Divider(height: 1),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  const AppSectionHeader(
                    title: 'Attendance trend',
                    icon: Icons.show_chart_rounded,
                  ),
                  const _AttendanceTrendCard(),
                  const SizedBox(height: AppSpacing.lg),
                  const AppSectionHeader(
                    title: 'Today',
                    icon: Icons.today_outlined,
                  ),
                  todays.when(
                    loading: () => const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      child: AppLoading(),
                    ),
                    error: (e, _) => AppErrorView(
                      message: friendlyError(e),
                      onRetry: () =>
                          ref.invalidate(myTodaysBatchesProvider),
                    ),
                    data: (list) {
                      if (list.isEmpty) {
                        return const AppEmptyState(
                          icon: Icons.event_busy_outlined,
                          title: 'No sessions today',
                          subtitle:
                              'You have no batches scheduled for today. '
                              'Enjoy the break or check tomorrow.',
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
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Today's sessions" quick-action — the primary attendance entry point. A
/// full-width [AppFeatureCard] so it reads as the day's headline task.
class _TodaysSessionsCard extends StatelessWidget {
  const _TodaysSessionsCard({
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return AppFeatureCard(
      title: "Today's sessions",
      subtitle: subtitle,
      icon: Icons.fact_check_rounded,
      tint: AppPalette.brandPrimary,
      badge: badge,
      onTap: onTap,
    );
  }
}

/// A grouped "Manage" destination row: a tinted leading icon, a title +
/// one-line subtitle, and a chevron. Renders a real [AppListTile].
class _ManageTile extends StatelessWidget {
  const _ManageTile({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      wrapLeading: false,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: tint, size: 20),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

/// Shown to coach/trainer roles with no linked `coaches.user_id` record yet.
/// Sits above "Daily ops" so the dashboard still reads while unlinked.
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
    final tint = colorFromName(batch.name);
    return AppCard(
      padding: EdgeInsets.zero,
      child: AppListTile(
        wrapLeading: false,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(Icons.group_work_outlined, color: tint, size: 20),
        ),
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

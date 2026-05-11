import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/attendance/presentation/attendance_marking_page.dart';
import 'package:playhub/features/attendance/presentation/todays_sessions_page.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/auth/presentation/profile_page.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/coach/data/coach_home_providers.dart';

class CoachHomeTab extends ConsumerWidget {
  const CoachHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final myCoach = ref.watch(myCoachRecordProvider);
    final stats = ref.watch(myCoachStatsProvider);
    final todays = ref.watch(myTodaysBatchesProvider);
    final isHeadCoach = profile?.role == 'head_coach';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ref.read(supabaseClientProvider).auth.signOut(),
          ),
        ],
      ),
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
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hello, ${profile?.displayName ?? '...'}',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(profile?.role ?? '',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Head coaches don't need a coaches.user_id link — they get
            // academy-wide oversight via myBatchesProvider.
            if (isHeadCoach)
              _StatsRow(stats: stats)
            else
              myCoach.when(
                loading: () =>
                    const Card(child: ListTile(title: Text('Loading…'))),
                error: (e, _) =>
                    Card(child: ListTile(title: Text('Error: $e'))),
                data: (coach) {
                  if (coach == null) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No coach record is linked to your account yet. '
                          'Ask the academy admin to link you to a coach '
                          'profile so you can see your batches.',
                        ),
                      ),
                    );
                  }
                  return _StatsRow(stats: stats);
                },
              ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_available_outlined),
                title: const Text("Today's sessions"),
                subtitle: todays.when(
                  loading: () => const Text('Loading…'),
                  error: (e, _) => Text('Error: $e'),
                  data: (list) => Text(list.isEmpty
                      ? 'No batches scheduled for you today'
                      : '${list.length} ${list.length == 1 ? 'batch' : 'batches'} to mark'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                      builder: (_) => const TodaysSessionsPage()),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _AttendanceTrendCard(),
            const SizedBox(height: 12),
            todays.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (list) {
                if (list.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6),
                      child: Text('Today',
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    for (final b in list) _BatchRow(batch: b),
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

class _AttendanceTrendCard extends ConsumerWidget {
  const _AttendanceTrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(coachAttendanceTrendProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Text('Error: $e'),
          data: (weeks) {
            if (weeks.isEmpty || weeks.every((w) => w.total == 0)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Attendance trend',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Not enough data yet'),
                ],
              );
            }
            final primary = Theme.of(context).colorScheme.primary;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Attendance % (last 4 weeks)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
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
                                    top: Radius.circular(4)),
                              ),
                            ],
                          ),
                      ],
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 25,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: Theme.of(context).dividerColor,
                          strokeWidth: 0.5,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: 25,
                            getTitlesWidget: (v, _) => Text(
                              '${v.toInt()}%',
                              style:
                                  Theme.of(context).textTheme.labelSmall,
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
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${ws.day}/${ws.month}',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, _, __, ___) {
                            final w = weeks[group.x];
                            return BarTooltipItem(
                              'Week of ${w.weekStart.day}/${w.weekStart.month}\n'
                              '${w.present}/${w.total}'
                              ' (${w.pct.toStringAsFixed(0)}%)',
                              const TextStyle(color: Colors.white),
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
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});
  final AsyncValue<CoachStats> stats;

  @override
  Widget build(BuildContext context) {
    return stats.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
      ),
      error: (e, _) => Card(child: ListTile(title: Text('Error: $e'))),
      data: (s) => Row(
        children: [
          Expanded(
              child: _StatTile(
                  icon: Icons.schedule,
                  label: 'My batches',
                  value: '${s.batchCount}')),
          const SizedBox(width: 12),
          Expanded(
              child: _StatTile(
                  icon: Icons.group,
                  label: 'Students',
                  value: '${s.studentCount}')),
          const SizedBox(width: 12),
          Expanded(
              child: _StatTile(
                  icon: Icons.today,
                  label: 'Today',
                  value: '${s.todaysCount}')),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
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
    return Card(
      child: ListTile(
        leading: const Icon(Icons.group_work_outlined),
        title: Text(batch.name),
        subtitle: Text(batch.schedule.summary),
        trailing: const Icon(Icons.check_circle_outline),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                AttendanceMarkingPage(batch: batch, date: today0),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/attendance/presentation/todays_sessions_page.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch.dart';
import 'package:playhub/features/batches/presentation/batch_detail_page.dart';
import 'package:playhub/features/coach/data/coach_home_providers.dart';

class CoachHomeTab extends ConsumerWidget {
  const CoachHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final myCoach = ref.watch(myCoachRecordProvider);
    final stats = ref.watch(myCoachStatsProvider);
    final todays = ref.watch(myTodaysBatchesProvider);

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
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(myCoachRecordProvider)
            ..invalidate(myBatchesProvider)
            ..invalidate(myTodaysBatchesProvider)
            ..invalidate(myCoachStatsProvider);
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
            myCoach.when(
              loading: () =>
                  const Card(child: ListTile(title: Text('Loading…'))),
              error: (e, _) => Card(child: ListTile(title: Text('Error: $e'))),
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
    return Card(
      child: ListTile(
        leading: const Icon(Icons.group_work_outlined),
        title: Text(batch.name),
        subtitle: Text(batch.schedule.summary),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => BatchDetailPage(batch: batch)),
        ),
      ),
    );
  }
}

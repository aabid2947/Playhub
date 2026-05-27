import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/attendance/data/attendance_providers.dart';
import 'package:playhub/features/attendance/presentation/admin_attendance_overview.dart';
import 'package:playhub/features/attendance/presentation/todays_sessions_page.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/events/presentation/events_page.dart';
import 'package:playhub/features/inventory/presentation/inventory_page.dart';
import 'package:playhub/features/leads/presentation/leads_kanban_page.dart';
import 'package:playhub/features/students/data/student_providers.dart';

/// Center-scoped home dashboard for the `center_admin` role.
///
/// Reads are already narrowed to the admin's own center by RLS
/// (center_admin_sees_*), so student/batch counts here reflect just their
/// center. Revenue is view-only for center admins, so this surface links to
/// operational tools but omits subscription/KPI-revenue management.
class CenterAdminHomeTab extends ConsumerWidget {
  const CenterAdminHomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final centers = ref.watch(centersProvider).valueOrNull ?? [];
    final students = ref.watch(studentsProvider).valueOrNull ?? [];
    final batches = ref.watch(batchesProvider).valueOrNull ?? [];
    final todays = ref.watch(todaysBatchesProvider).valueOrNull ?? [];

    final centerName = centers
        .where((c) => c.id == profile?.centerId)
        .map((c) => c.name)
        .firstOrNull;

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(studentsProvider)
          ..invalidate(batchesProvider)
          ..invalidate(todaysBatchesProvider)
          ..invalidate(centersProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
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
                  Text(
                    centerName == null
                        ? 'Center admin'
                        : 'Center admin · $centerName',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.group_outlined,
                  label: 'Students',
                  value: '${students.length}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: Icons.schedule_outlined,
                  label: 'Batches',
                  value: '${batches.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text("Today's sessions"),
                  subtitle: Text(todays.isEmpty
                      ? 'No batches scheduled today'
                      : '${todays.length} ${todays.length == 1 ? 'batch' : 'batches'} to mark'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                        builder: (_) => const TodaysSessionsPage()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: const Text('Live attendance overview'),
                  subtitle: const Text('Realtime view across your center'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                        builder: (_) => const AdminAttendanceOverview()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_search_outlined),
                  title: const Text('Leads'),
                  subtitle: const Text('Funnel for your center'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const LeadsKanbanPage()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.emoji_events_outlined),
                  title: const Text('Events'),
                  subtitle: const Text('Tournaments, workshops'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const EventsPage()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Inventory'),
                  subtitle: const Text('Equipment for your center'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const InventoryPage()),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

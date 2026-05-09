import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/academy/data/academy_providers.dart';
import 'package:playhub/features/attendance/data/attendance_providers.dart';
import 'package:playhub/features/attendance/presentation/admin_attendance_overview.dart';
import 'package:playhub/features/attendance/presentation/todays_sessions_page.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/announcements/presentation/announcements_page.dart';
import 'package:playhub/features/billing/presentation/billing_dashboard_page.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/chat/presentation/threads_page.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/analytics/presentation/kpi_dashboard_page.dart';
import 'package:playhub/features/events/presentation/events_page.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/features/inventory/presentation/inventory_page.dart';
import 'package:playhub/features/leads/presentation/leads_kanban_page.dart';
import 'package:playhub/features/reports/presentation/report_builder_page.dart';
import 'package:playhub/features/notifications/presentation/notification_center_page.dart';
import 'package:playhub/features/students/data/student_providers.dart';

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final academy = ref.watch(myAcademyProvider).valueOrNull;
    final centers = ref.watch(centersProvider).valueOrNull ?? [];
    final students = ref.watch(studentsProvider).valueOrNull ?? [];
    final coaches = ref.watch(coachesProvider).valueOrNull ?? [];
    final batches = ref.watch(batchesProvider).valueOrNull ?? [];
    final todays = ref.watch(todaysBatchesProvider).valueOrNull ?? [];

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(currentProfileProvider)
          ..invalidate(myAcademyProvider)
          ..invalidate(todaysBatchesProvider)
          ..invalidate(centersProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, ${profile?.displayName ?? '...'}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile?.role ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (academy != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      academy.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (academy.city != null || academy.address != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [academy.address, academy.city]
                            .whereType<String>()
                            .where((s) => s.isNotEmpty)
                            .join(', '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          _ActionsCard(todaysCount: todays.length),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.location_on_outlined,
                  label: 'Centers',
                  value: '${centers.length}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: Icons.group_outlined,
                  label: 'Students',
                  value: '${students.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.sports_outlined,
                  label: 'Coaches',
                  value: '${coaches.length}',
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
        ],
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.todaysCount});
  final int todaysCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.event_available_outlined),
            title: const Text("Today's sessions"),
            subtitle: Text(
              todaysCount == 0
                  ? 'No batches scheduled today'
                  : '$todaysCount ${todaysCount == 1 ? 'batch' : 'batches'} to mark',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const TodaysSessionsPage()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.dashboard_outlined),
            title: const Text('Live attendance overview'),
            subtitle: const Text('Realtime view across all batches'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => const AdminAttendanceOverview(),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Billing'),
            subtitle: const Text('Invoices, fees, payments, reports'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => const BillingDashboardPage(),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.person_search_outlined),
            title: const Text('Leads'),
            subtitle: const Text('Funnel kanban + new lead intake'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const LeadsKanbanPage()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.emoji_events_outlined),
            title: const Text('Events'),
            subtitle: const Text('Tournaments, workshops, certificates'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const EventsPage()),
            ),
          ),
          const Divider(height: 1),
          Consumer(
            builder: (_, ref, __) {
              final low = ref.watch(lowStockItemsProvider).length;
              return ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Inventory'),
                subtitle: Text(low == 0
                    ? 'Equipment + low-stock alerts'
                    : '$low item${low == 1 ? '' : 's'} below threshold'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const InventoryPage()),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('KPI dashboard'),
            subtitle: const Text('Revenue, enrollment, batch utilization'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const KpiDashboardPage()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Custom report'),
            subtitle: const Text('Pick fields, filters, group by'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ReportBuilderPage()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('Announcements'),
            subtitle: const Text('Compose + send to roles, batches, centers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const AnnouncementsPage()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.chat_outlined),
            title: const Text('Messages'),
            subtitle: const Text('1:1 + batch group chat'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ThreadsPage()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text('In-app feed'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => const NotificationCenterPage(),
              ),
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

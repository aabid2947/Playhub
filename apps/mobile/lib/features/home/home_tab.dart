import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/academy/data/academy_providers.dart';
import 'package:playhub/features/analytics/presentation/kpi_dashboard_page.dart';
import 'package:playhub/features/announcements/presentation/announcements_page.dart';
import 'package:playhub/features/attendance/data/attendance_providers.dart';
import 'package:playhub/features/attendance/presentation/admin_attendance_overview.dart';
import 'package:playhub/features/attendance/presentation/todays_sessions_page.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/billing/presentation/billing_dashboard_page.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/chat/presentation/threads_page.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/events/presentation/events_page.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/features/inventory/presentation/inventory_page.dart';
import 'package:playhub/features/leads/presentation/leads_kanban_page.dart';
import 'package:playhub/features/notifications/presentation/notification_center_page.dart';
import 'package:playhub/features/reports/presentation/report_builder_page.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Owner-shell Home-tab body. App-bar-less by contract: [OwnerHomeShell]
/// provides the single persistent AppBar (brand wordmark + account menu), so
/// this returns a scrolling body only — adding a Scaffold/AppBar here would
/// double the shell bar.
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
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: <Widget>[
          _HeroCard(
            greeting: profile?.displayName ?? '...',
            role: profile?.role ?? '',
            academyName: academy?.name,
            academyLocation: academy == null
                ? null
                : [academy.address, academy.city]
                    .whereType<String>()
                    .where((s) => s.isNotEmpty)
                    .join(', '),
          ),
          const SizedBox(height: AppSpacing.lg),

          // KPIs — students / coaches / batches / centers together.
          Row(
            children: [
              Expanded(
                child: AppStatTile(
                  icon: Icons.group_outlined,
                  label: 'Students',
                  value: '${students.length}',
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppStatTile(
                  icon: Icons.sports_outlined,
                  label: 'Coaches',
                  value: '${coaches.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppStatTile(
                  icon: Icons.schedule_outlined,
                  label: 'Batches',
                  value: '${batches.length}',
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppStatTile(
                  icon: Icons.location_on_outlined,
                  label: 'Centers',
                  value: '${centers.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Daily ops — the things touched every day, primary above tertiary.
          const AppSectionHeader(title: 'Daily ops'),
          _ActionGroup(
            children: [
              _ActionTile(
                icon: Icons.event_available_outlined,
                title: "Today's sessions",
                subtitle: todays.isEmpty
                    ? 'No batches scheduled today'
                    : '${todays.length} '
                        '${todays.length == 1 ? 'batch' : 'batches'} to mark',
                builder: (_) => const TodaysSessionsPage(),
              ),
              const _ActionTile(
                icon: Icons.dashboard_outlined,
                title: 'Live attendance overview',
                subtitle: 'Realtime view across all batches',
                builder: _buildAttendanceOverview,
              ),
              const _InventoryActionTile(),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Money — billing, reporting, financial insight.
          const AppSectionHeader(title: 'Money'),
          const _ActionGroup(
            children: [
              _ActionTile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Billing',
                subtitle: 'Invoices, fees, payments, reports',
                builder: _buildBilling,
              ),
              _ActionTile(
                icon: Icons.insights_outlined,
                title: 'KPI dashboard',
                subtitle: 'Revenue, enrollment, batch utilization',
                builder: _buildKpiDashboard,
              ),
              _ActionTile(
                icon: Icons.table_chart_outlined,
                title: 'Custom report',
                subtitle: 'Pick fields, filters, group by',
                builder: _buildReportBuilder,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Growth — pipeline and events.
          const AppSectionHeader(title: 'Growth'),
          const _ActionGroup(
            children: [
              _ActionTile(
                icon: Icons.person_search_outlined,
                title: 'Leads',
                subtitle: 'Funnel kanban + new lead intake',
                builder: _buildLeads,
              ),
              _ActionTile(
                icon: Icons.emoji_events_outlined,
                title: 'Events',
                subtitle: 'Tournaments, workshops, certificates',
                builder: _buildEvents,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Comms — outbound + inbound messaging.
          const AppSectionHeader(title: 'Comms'),
          const _ActionGroup(
            children: [
              _ActionTile(
                icon: Icons.campaign_outlined,
                title: 'Announcements',
                subtitle: 'Compose + send to roles, batches, centers',
                builder: _buildAnnouncements,
              ),
              _ActionTile(
                icon: Icons.chat_outlined,
                title: 'Messages',
                subtitle: '1:1 + batch group chat',
                builder: _buildMessages,
              ),
              _ActionTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: 'In-app feed',
                builder: _buildNotifications,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Greeting hero that folds the user identity and the academy context into a
/// single card (they used to be two stacked cards).
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.greeting,
    required this.role,
    required this.academyName,
    required this.academyLocation,
  });

  final String greeting;
  final String role;
  final String? academyName;
  final String? academyLocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppUserAvatar(size: 48),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, $greeting',
                      style: theme.textTheme.titleLarge,
                    ),
                    if (role.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        role,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (academyName != null) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.business_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        academyName!,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (academyLocation != null &&
                          academyLocation!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          academyLocation!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Groups action tiles into one divider-separated card. Each child is an
/// [_ActionTile] (static destination) or the reactive [_InventoryActionTile].
class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1));
      rows.add(children[i]);
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: rows),
    );
  }
}

/// One navigation action: a tinted-icon list tile that pushes [builder].
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: builder),
      ),
    );
  }
}

// Top-level page builders so the action tiles above can be `const`.
Widget _buildAttendanceOverview(BuildContext _) =>
    const AdminAttendanceOverview();
Widget _buildBilling(BuildContext _) => const BillingDashboardPage();
Widget _buildKpiDashboard(BuildContext _) => const KpiDashboardPage();
Widget _buildReportBuilder(BuildContext _) => const ReportBuilderPage();
Widget _buildLeads(BuildContext _) => const LeadsKanbanPage();
Widget _buildEvents(BuildContext _) => const EventsPage();
Widget _buildAnnouncements(BuildContext _) => const AnnouncementsPage();
Widget _buildMessages(BuildContext _) => const ThreadsPage();
Widget _buildNotifications(BuildContext _) => const NotificationCenterPage();

/// Inventory action tile with a reactive low-stock subtitle.
class _InventoryActionTile extends ConsumerWidget {
  const _InventoryActionTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final low = ref.watch(lowStockItemsProvider).length;
    return AppListTile(
      leading: const Icon(Icons.inventory_2_outlined),
      title: const Text('Inventory'),
      subtitle: Text(
        low == 0
            ? 'Equipment + low-stock alerts'
            : '$low item${low == 1 ? '' : 's'} below threshold',
      ),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const InventoryPage()),
      ),
    );
  }
}

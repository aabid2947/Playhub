import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/academy/data/academy_providers.dart';
import 'package:playhub/features/analytics/presentation/kpi_dashboard_page.dart';
import 'package:playhub/features/announcements/presentation/announcements_page.dart';
import 'package:playhub/features/attendance/data/attendance_providers.dart';
import 'package:playhub/features/attendance/presentation/admin_attendance_overview.dart';
import 'package:playhub/features/attendance/presentation/todays_sessions_page.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
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

/// Owner-shell Home-tab body — v1 "Sports-Light" dashboard (archetype A).
///
/// App-bar-less by contract: [OwnerHomeShell] provides the single persistent
/// AppBar (brand wordmark + account menu), so this returns a scrolling body
/// only — adding a Scaffold/AppBar here would double the shell bar.
///
/// Management entry points stay gated by the capability mirror even though the
/// owner holds them all (defensive + RLS is the real gate); a coat of paint
/// never widens access.
class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final caps = ref.watch(capabilitiesProvider);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final academy = ref.watch(myAcademyProvider).valueOrNull;
    final centers = ref.watch(centersProvider).valueOrNull ?? const [];
    final students = ref.watch(studentsProvider).valueOrNull ?? const [];
    final coaches = ref.watch(coachesProvider).valueOrNull ?? const [];
    final batches = ref.watch(batchesProvider).valueOrNull ?? const [];
    final todays = ref.watch(todaysBatchesProvider).valueOrNull ?? const [];
    final lowStock = ref.watch(lowStockItemsProvider).length;

    final firstName =
        (profile?.displayName ?? '').split(' ').firstOrNull ?? 'there';
    final academyName = academy?.name;

    // High-traffic quick actions — colorful feature cards, each gated. The
    // navigation targets and capability gates mirror the action rows below;
    // RLS is the authoritative gate (these flags only hide the entry point).
    final quickActions = <Widget>[
      if (caps.markAttendance)
        AppFeatureCard(
          title: "Today's sessions",
          subtitle: todays.isEmpty
              ? 'Nothing scheduled today'
              : '${todays.length} to mark',
          icon: Icons.fact_check_rounded,
          tint: AppPalette.brandPrimary,
          badge: todays.isEmpty ? null : '${todays.length}',
          onTap: () => _push(context, const TodaysSessionsPage()),
        ),
      if (caps.markAttendance)
        AppFeatureCard(
          title: 'Live attendance',
          subtitle: 'Realtime across all batches',
          icon: Icons.dashboard_rounded,
          tint: AppPalette.accent,
          onTap: () => _push(context, const AdminAttendanceOverview()),
        ),
      if (caps.manageFinance)
        AppFeatureCard(
          title: 'Billing',
          subtitle: 'Invoices, fees, payments',
          icon: Icons.account_balance_wallet_rounded,
          tint: AppPalette.success,
          onTap: () => _push(context, const BillingDashboardPage()),
        ),
      if (caps.viewRevenue)
        AppFeatureCard(
          title: 'KPI dashboard',
          subtitle: 'Revenue, enrollment, utilization',
          icon: Icons.insights_rounded,
          tint: AppPalette.categorySwatch[3],
          onTap: () => _push(context, const KpiDashboardPage()),
        ),
      if (caps.composeAnnouncements)
        AppFeatureCard(
          title: 'Announcements',
          subtitle: 'Compose + send to families',
          icon: Icons.campaign_rounded,
          tint: AppPalette.categorySwatch[5],
          onTap: () => _push(context, const AnnouncementsPage()),
        ),
      if (caps.manageLeads)
        AppFeatureCard(
          title: 'Leads',
          subtitle: 'Funnel kanban + intake',
          icon: Icons.person_search_rounded,
          tint: AppPalette.categorySwatch[1],
          onTap: () => _push(context, const LeadsKanbanPage()),
        ),
    ];

    // Secondary destinations — grouped list rows, each gated. Money / Growth /
    // Comms groups preserve the original menu's remaining targets.
    final moneyRows = <Widget>[
      if (caps.viewRevenue)
        _ActionTile(
          icon: Icons.table_chart_outlined,
          tint: AppPalette.categorySwatch[3],
          title: 'Custom report',
          subtitle: 'Pick fields, filters, group by',
          onTap: () => _push(context, const ReportBuilderPage()),
        ),
    ];

    final growthRows = <Widget>[
      if (caps.manageEvents)
        _ActionTile(
          icon: Icons.emoji_events_outlined,
          tint: AppPalette.categorySwatch[4],
          title: 'Events',
          subtitle: 'Tournaments, workshops, certificates',
          onTap: () => _push(context, const EventsPage()),
        ),
      if (caps.manageInventory)
        _ActionTile(
          icon: Icons.inventory_2_outlined,
          tint: AppPalette.categorySwatch[5],
          title: 'Inventory',
          subtitle: lowStock == 0
              ? 'Equipment + low-stock alerts'
              : '$lowStock item${lowStock == 1 ? '' : 's'} below threshold',
          onTap: () => _push(context, const InventoryPage()),
        ),
    ];

    // Comms — messaging is participant-scoped and notifications are personal,
    // so these stay ungated (available to every owner/admin reaching this body).
    final commsRows = <Widget>[
      _ActionTile(
        icon: Icons.chat_outlined,
        tint: AppPalette.accent,
        title: 'Messages',
        subtitle: '1:1 + batch group chat',
        onTap: () => _push(context, const ThreadsPage()),
      ),
      _ActionTile(
        icon: Icons.notifications_outlined,
        tint: AppPalette.brandPrimary,
        title: 'Notifications',
        subtitle: 'In-app feed',
        onTap: () => _push(context, const NotificationCenterPage()),
      ),
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(currentProfileProvider)
          ..invalidate(myAcademyProvider)
          ..invalidate(todaysBatchesProvider)
          ..invalidate(centersProvider);
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Greeting hero: identity + academy context + headline stat strip.
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
                            style: theme.textTheme.titleLarge
                                ?.copyWith(color: Colors.white),
                          ),
                          if (academyName != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.business_rounded,
                                  size: 15,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    academyName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.bodyMedium?.copyWith(
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
                    ('${students.length}', 'Students'),
                    ('${coaches.length}', 'Coaches'),
                    ('${batches.length}', 'Batches'),
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
                  // KPI grid — students / coaches / batches / centers.
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

                  // Quick actions — colorful gated feature cards.
                  if (quickActions.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const AppSectionHeader(
                      title: 'Quick actions',
                      icon: Icons.bolt_rounded,
                    ),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      childAspectRatio: 1.5,
                      children: quickActions,
                    ),
                  ],

                  if (moneyRows.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const AppSectionHeader(
                      title: 'Money',
                      icon: Icons.payments_outlined,
                    ),
                    _ActionGroup(children: moneyRows),
                  ],

                  if (growthRows.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const AppSectionHeader(
                      title: 'Growth',
                      icon: Icons.trending_up_rounded,
                    ),
                    _ActionGroup(children: growthRows),
                  ],

                  const SizedBox(height: AppSpacing.lg),
                  const AppSectionHeader(
                    title: 'Comms',
                    icon: Icons.forum_outlined,
                  ),
                  _ActionGroup(children: commsRows),

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

/// Groups action tiles into one divider-separated [AppCard].
class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

/// One navigation action: a tinted-icon list tile that pushes [onTap].
/// Renders a real [AppListTile] so widget-type finders resolve.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
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

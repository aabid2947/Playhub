import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/academy/data/academy_providers.dart';
import 'package:playhub/features/analytics/data/analytics_providers.dart';
import 'package:playhub/features/analytics/presentation/kpi_dashboard_page.dart';
import 'package:playhub/features/announcements/presentation/announcements_page.dart';
import 'package:playhub/features/attendance/data/attendance_providers.dart';
import 'package:playhub/features/attendance/presentation/admin_attendance_overview.dart';
import 'package:playhub/features/attendance/presentation/todays_sessions_page.dart';
import 'package:playhub/features/audit/data/audit_log.dart';
import 'package:playhub/features/audit/data/audit_log_providers.dart';
import 'package:playhub/features/audit/presentation/audit_log_page.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/billing/data/billing_providers.dart';
import 'package:playhub/features/billing/presentation/billing_dashboard_page.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/chat/presentation/threads_page.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:playhub/features/events/data/event_providers.dart';
import 'package:playhub/features/events/presentation/events_page.dart';
import 'package:playhub/features/inventory/data/inventory_providers.dart';
import 'package:playhub/features/inventory/presentation/inventory_page.dart';
import 'package:playhub/features/leads/presentation/leads_kanban_page.dart';
import 'package:playhub/features/notifications/presentation/notification_center_page.dart';
import 'package:playhub/features/reports/presentation/report_builder_page.dart';
import 'package:playhub/features/students/data/student.dart';
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
          ..invalidate(centersProvider)
          ..invalidate(collectionSummaryProvider)
          ..invalidate(todaysCollectedProvider)
          ..invalidate(eventsListProvider)
          ..invalidate(auditLogsProvider);
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
                  // Today's snapshot — new joins, money in, classes, dues.
                  _TodaysOverviewCard(
                    newStudentsToday: _joinedToday(students),
                    activeClassesToday: todays.length,
                    showFinance: caps.viewRevenue,
                  ),

                  // Multi-center overview — academy-wide totals incl. revenue.
                  const SizedBox(height: AppSpacing.lg),
                  const AppSectionHeader(
                    title: 'Multi-center overview',
                    icon: Icons.apartment_rounded,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: AppStatTile(
                          icon: Icons.location_on_outlined,
                          label: 'Centers',
                          value: '${centers.length}',
                          color: AppPalette.categorySwatch[4],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: AppStatTile(
                          icon: Icons.group_outlined,
                          label: 'Students',
                          value: '${students.length}',
                          color: AppPalette.brandPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: AppStatTile(
                          icon: Icons.sports_outlined,
                          label: 'Coaches',
                          value: '${coaches.length}',
                          color: AppPalette.accent,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: caps.viewRevenue
                            ? const _RevenueTotalTile()
                            : AppStatTile(
                                icon: Icons.schedule_outlined,
                                label: 'Batches',
                                value: '${batches.length}',
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

                  // Upcoming events — surfaced from the events feature.
                  const SizedBox(height: AppSpacing.lg),
                  _UpcomingEventsCard(
                    onViewAll: () => _push(context, const EventsPage()),
                  ),

                  // Activity feed — recent audit-log entries.
                  const SizedBox(height: AppSpacing.lg),
                  _ActivityFeedCard(
                    onViewAll: () => _push(context, const AuditLogPage()),
                  ),

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

// ===========================================================================
// Today's overview + multi-center overview + events + activity
// ===========================================================================

/// Number of students whose enrollment date is today.
int _joinedToday(List<Student> students) {
  final now = DateTime.now();
  return students.where((s) {
    final d = s.enrollmentDate;
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }).length;
}

/// Short relative-time label for the activity feed ("just now", "3h ago").
String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return DateFormat.MMMd().format(t);
}

/// "Today, 4:00 PM" / "Tomorrow, 9:00 AM" / "Jun 20, 2:00 PM".
String _eventWhen(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  final time = DateFormat.jm().format(t);
  if (diff == 0) return 'Today, $time';
  if (diff == 1) return 'Tomorrow, $time';
  return '${DateFormat.MMMd().format(t)}, $time';
}

IconData _eventIcon(EventKind k) {
  switch (k) {
    case EventKind.tournament:
      return Icons.emoji_events_outlined;
    case EventKind.workshop:
      return Icons.school_outlined;
    case EventKind.camp:
      return Icons.cabin_outlined;
    case EventKind.fixture:
      return Icons.sports_outlined;
    case EventKind.social:
      return Icons.celebration_outlined;
  }
}

String _auditVerb(String action) {
  switch (action) {
    case 'insert':
      return 'added';
    case 'update':
      return 'updated';
    case 'delete':
      return 'removed';
    default:
      return action;
  }
}

/// "Today" snapshot card — new joins, money in, classes running, dues. Finance
/// cells (revenue / pending) only render when [showFinance] is true.
class _TodaysOverviewCard extends ConsumerWidget {
  const _TodaysOverviewCard({
    required this.newStudentsToday,
    required this.activeClassesToday,
    required this.showFinance,
  });

  final int newStudentsToday;
  final int activeClassesToday;
  final bool showFinance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final money = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹');
    final collectedToday =
        showFinance ? ref.watch(todaysCollectedProvider).valueOrNull : null;
    final pending = showFinance
        ? ref.watch(collectionSummaryProvider).valueOrNull?.overdueCount
        : null;

    final cells = <Widget>[
      _TodayStat(
        icon: Icons.person_add_alt_1_rounded,
        value: '$newStudentsToday',
        label: 'New students',
        tint: AppPalette.brandPrimary,
      ),
      if (showFinance)
        _TodayStat(
          icon: Icons.currency_rupee_rounded,
          value: collectedToday == null ? '—' : money.format(collectedToday),
          label: 'Revenue',
          tint: AppPalette.success,
        ),
      _TodayStat(
        icon: Icons.sports_rounded,
        value: '$activeClassesToday',
        label: 'Classes',
        tint: AppPalette.accent,
      ),
      if (showFinance)
        _TodayStat(
          icon: Icons.pending_actions_rounded,
          value: pending == null ? '—' : '$pending',
          label: 'Pending',
          tint: AppPalette.categorySwatch[2],
        ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.today_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                "Today's overview",
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: AppType.bold),
              ),
              const Spacer(),
              Text(
                DateFormat.MMMd().format(DateTime.now()),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                Expanded(child: cells[i]),
                if (i != cells.length - 1)
                  Container(
                    width: 1,
                    height: 40,
                    color: theme.dividerColor,
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One vertical stat in [_TodaysOverviewCard].
class _TodayStat extends StatelessWidget {
  const _TodayStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.tint,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: tint),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: AppType.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Academy-wide lifetime collected, as a KPI tile for the multi-center grid.
class _RevenueTotalTile extends ConsumerWidget {
  const _RevenueTotalTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(collectionSummaryProvider).valueOrNull;
    final money = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹');
    return AppStatTile(
      icon: Icons.payments_outlined,
      label: 'Revenue',
      value: summary == null ? '—' : money.format(summary.collectedTotal),
      color: AppPalette.success,
    );
  }
}

/// Surfaces the next few published/upcoming events on the home dashboard.
/// Hidden entirely while loading or when nothing is upcoming.
class _UpcomingEventsCard extends ConsumerWidget {
  const _UpcomingEventsCard({required this.onViewAll});

  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsListProvider).valueOrNull;
    if (events == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final upcoming = events.where((e) => e.startsAt.isAfter(now)).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final shown = upcoming.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: 'Upcoming events',
          icon: Icons.event_rounded,
          actionLabel: 'View all',
          onAction: onViewAll,
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                _EventRow(event: shown[i]),
                if (i != shown.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final EventEntry event;

  @override
  Widget build(BuildContext context) {
    final tint = colorFromName(event.title);
    final loc = event.location;
    final subtitle = [
      _eventWhen(event.startsAt),
      if (loc != null && loc.isNotEmpty) loc,
    ].join(' · ');
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
        child: Icon(_eventIcon(event.kind), color: tint, size: 20),
      ),
      title: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Recent cross-entity changes from the audit log. RLS scopes the rows to what
/// the viewer may see; hidden while loading or when there's no activity.
class _ActivityFeedCard extends ConsumerWidget {
  const _ActivityFeedCard({required this.onViewAll});

  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(auditLogsProvider).valueOrNull;
    if (logs == null || logs.isEmpty) return const SizedBox.shrink();
    final shown = logs.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: 'Activity',
          icon: Icons.timeline_rounded,
          actionLabel: 'View all',
          onAction: onViewAll,
        ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                _ActivityRow(log: shown[i]),
                if (i != shown.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.log});

  final AuditLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantics = AppSemanticColors.of(context);
    final (IconData icon, Color tint) = switch (log.action) {
      'insert' => (Icons.add_rounded, semantics.success),
      'update' => (Icons.edit_outlined, AppPalette.accent),
      'delete' => (Icons.delete_outline_rounded, semantics.danger),
      _ => (Icons.bolt_rounded, AppPalette.brandPrimary),
    };
    final entity = log.entityType.replaceAll('_', ' ');
    final subject = log.entitySubject;
    final title = '${log.userDisplay} ${_auditVerb(log.action)} $entity'
        '${subject != null ? ' · $subject' : ''}';
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
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        _timeAgo(log.createdAt),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

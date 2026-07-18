import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/attendance/data/attendance_providers.dart';
import 'package:playhub/features/attendance/presentation/admin_attendance_overview.dart';
import 'package:playhub/features/attendance/presentation/todays_sessions_page.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/batches/data/batch_providers.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/events/presentation/events_page.dart';
import 'package:playhub/features/inventory/presentation/inventory_page.dart';
import 'package:playhub/features/leads/presentation/leads_kanban_page.dart';
import 'package:playhub/features/students/data/student_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Center-scoped home dashboard for the `center_admin` role — v1 "Sports-Light".
///
/// Reads are narrowed to the admin's own center by RLS (center_admin_sees_*),
/// so the counts here reflect just their center. Revenue is view-only for
/// center admins, so this surface links to operational tools but omits
/// subscription / KPI-revenue management. Management entry points stay gated by
/// the capability mirror even though center_admin holds them (defensive +
/// RLS is the real gate).
class CenterAdminHomeTab extends ConsumerWidget {
  const CenterAdminHomeTab({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final caps = ref.watch(capabilitiesProvider);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final centers = ref.watch(centersProvider).valueOrNull ?? const [];
    final students = ref.watch(studentsProvider).valueOrNull ?? const [];
    final batches = ref.watch(batchesProvider).valueOrNull ?? const [];
    final todays = ref.watch(todaysBatchesProvider).valueOrNull ?? const [];

    // A center_admin may manage several centers (user_centers). Label the
    // greeting with all of them ("Andheri · Bandra"); falls back to the primary
    // while the grant set loads.
    final myCenters = ref.watch(myCenterIdsProvider).valueOrNull ??
        {if (profile?.centerId != null) profile!.centerId!};
    final centerNames = centers
        .where((c) => myCenters.contains(c.id))
        .map((c) => c.name)
        .toList(growable: false);
    final centerName = centerNames.isNotEmpty ? centerNames.join(' · ') : null;
    final firstName =
        (profile?.displayName ?? '').split(' ').firstOrNull ?? 'there';

    // Secondary "Manage" destinations, each gated. Rendered as grouped rows.
    final manageRows = <Widget>[
      if (caps.manageLeads)
        _ManageTile(
          icon: Icons.person_search_outlined,
          tint: AppPalette.success,
          title: 'Leads',
          subtitle: 'Funnel for your center',
          onTap: () => _push(context, const LeadsKanbanPage()),
        ),
      if (caps.manageEvents)
        _ManageTile(
          icon: Icons.emoji_events_outlined,
          tint: AppPalette.categorySwatch[3],
          title: 'Events',
          subtitle: 'Tournaments, workshops',
          onTap: () => _push(context, const EventsPage()),
        ),
      if (caps.manageInventory)
        _ManageTile(
          icon: Icons.inventory_2_outlined,
          tint: AppPalette.categorySwatch[5],
          title: 'Inventory',
          subtitle: 'Equipment for your center',
          onTap: () => _push(context, const InventoryPage()),
        ),
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(studentsProvider)
          ..invalidate(batchesProvider)
          ..invalidate(todaysBatchesProvider)
          ..invalidate(centersProvider);
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Greeting hero with a center sub-line and a quick-glance stat row.
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
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 15,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  centerName ?? 'No center assigned',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color:
                                        Colors.white.withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
                    ('${batches.length}', 'Batches'),
                    ('${todays.length}', 'Today'),
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
                  const AppSectionHeader(
                    title: 'Daily ops',
                    icon: Icons.event_available_outlined,
                  ),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 1.5,
                    children: [
                      AppFeatureCard(
                        title: "Today's sessions",
                        subtitle: todays.isEmpty
                            ? 'Nothing scheduled today'
                            : '${todays.length} to mark',
                        icon: Icons.fact_check_rounded,
                        tint: AppPalette.brandPrimary,
                        badge: todays.isEmpty ? null : '${todays.length}',
                        onTap: () =>
                            _push(context, const TodaysSessionsPage()),
                      ),
                      AppFeatureCard(
                        title: 'Live attendance',
                        subtitle: 'Realtime across your center',
                        icon: Icons.dashboard_rounded,
                        tint: AppPalette.accent,
                        onTap: () =>
                            _push(context, const AdminAttendanceOverview()),
                      ),
                    ],
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

/// A grouped "Manage" destination row: a sport-color-tinted leading icon, a
/// title + one-line subtitle, and a chevron. Renders a real [AppListTile].
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

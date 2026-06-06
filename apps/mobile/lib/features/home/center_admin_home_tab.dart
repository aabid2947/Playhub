import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
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
import 'package:playhub/shared/widgets/widgets.dart';

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
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _GreetingCard(
            name: profile?.displayName ?? '...',
            centerName: centerName,
          ),
          const SizedBox(height: AppSpacing.md),
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
                  icon: Icons.schedule_outlined,
                  label: 'Batches',
                  value: '${batches.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const AppSectionHeader(title: 'Daily ops'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                AppListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text("Today's sessions"),
                  subtitle: Text(
                    todays.isEmpty
                        ? 'No batches scheduled today'
                        : '${todays.length} ${todays.length == 1 ? 'batch' : 'batches'} to mark',
                  ),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const TodaysSessionsPage(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                AppListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: const Text('Live attendance overview'),
                  subtitle: const Text('Realtime view across your center'),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const AdminAttendanceOverview(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const AppSectionHeader(title: 'Growth'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                AppListTile(
                  leading: const Icon(Icons.person_search_outlined),
                  title: const Text('Leads'),
                  subtitle: const Text('Funnel for your center'),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const LeadsKanbanPage()),
                  ),
                ),
                const Divider(height: 1),
                AppListTile(
                  leading: const Icon(Icons.emoji_events_outlined),
                  title: const Text('Events'),
                  subtitle: const Text('Tournaments, workshops'),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const EventsPage()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const AppSectionHeader(title: 'Operations'),
          AppCard(
            padding: EdgeInsets.zero,
            child: AppListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Inventory'),
              subtitle: const Text('Equipment for your center'),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const InventoryPage()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Greeting hero for the center admin: who they are, plus a prominent
/// identity row surfacing **which center** they run (or a clear fallback when
/// no center is linked yet) instead of burying it in the role text.
class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.name, required this.centerName});

  final String name;
  final String? centerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasCenter = centerName != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello, $name',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Center admin',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 20,
                color: hasCenter ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  hasCenter ? centerName! : 'No center assigned',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: hasCenter ? null : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/academy/presentation/academy_settings_page.dart';
import 'package:playhub/features/audit/presentation/audit_log_page.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/centers/presentation/centers_page.dart';
import 'package:playhub/features/sports/presentation/sports_settings_page.dart';
import 'package:playhub/features/subscription/presentation/subscription_page.dart';
import 'package:playhub/features/support/presentation/support_page.dart';
import 'package:playhub/features/users/presentation/team_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final role = ref.watch(currentProfileProvider).valueOrNull?.role ?? '';
    final isOwner = role == 'academy_owner';
    final isOwnerOrAdmin = role == 'academy_owner' || role == 'academy_admin';

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // Academy — the academy record (name/branding) is owner-only at the
        // RLS layer, so only owners get that entry point; centers/sports
        // configuration is visible to all roles.
        const AppSectionHeader(title: 'Academy'),
        const SizedBox(height: AppSpacing.sm),
        _SettingsGroup(
          tiles: [
            if (isOwner)
              _SettingsDestination(
                icon: Icons.business_outlined,
                title: 'Academy settings',
                subtitle: 'Name, contact, address, branding',
                builder: (_) => const AcademySettingsPage(),
              ),
            const _SettingsDestination(
              icon: Icons.location_on_outlined,
              title: 'Centers',
              subtitle: 'Physical locations of your academy',
              builder: _centersPageBuilder,
            ),
            const _SettingsDestination(
              icon: Icons.sports_outlined,
              title: 'Sports',
              subtitle: 'Which sports your academy offers',
              builder: _sportsPageBuilder,
            ),
          ],
        ),

        // Team & billing — managing people and the subscription is gated to
        // owners/admins (RLS rejects these writes for everyone else).
        if (isOwnerOrAdmin) ...[
          const SizedBox(height: AppSpacing.xl),
          const AppSectionHeader(title: 'Team & billing'),
          const SizedBox(height: AppSpacing.sm),
          const _SettingsGroup(
            tiles: [
              _SettingsDestination(
                icon: Icons.group_outlined,
                title: 'Team',
                subtitle: 'Invite admins, coaches, and trainers',
                builder: _teamPageBuilder,
              ),
              _SettingsDestination(
                icon: Icons.workspace_premium_outlined,
                title: 'Subscription',
                subtitle: 'Plan, billing cycle, past invoices',
                builder: _subscriptionPageBuilder,
              ),
              _SettingsDestination(
                icon: Icons.support_agent_outlined,
                title: 'Support',
                subtitle: 'Tickets to PlayHub support',
                builder: _supportPageBuilder,
              ),
            ],
          ),
        ],

        // Activity — visible to all roles.
        const SizedBox(height: AppSpacing.xl),
        const AppSectionHeader(title: 'Activity'),
        const SizedBox(height: AppSpacing.sm),
        const _SettingsGroup(
          tiles: [
            _SettingsDestination(
              icon: Icons.history_outlined,
              title: 'Activity log',
              subtitle: 'Who changed what, recently',
              builder: _auditLogPageBuilder,
            ),
          ],
        ),

        // Account — Sign out lives on its own so it isn't lost in the list.
        const SizedBox(height: AppSpacing.xl),
        const AppSectionHeader(title: 'Account'),
        const SizedBox(height: AppSpacing.sm),
        _SettingsGroup(
          tiles: [
            AppListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              trailing: const SizedBox.shrink(),
              onTap: () async {
                try {
                  await client.auth.signOut();
                } on Object catch (e) {
                  if (context.mounted) {
                    AppSnackbar.error(context, friendlyError(e));
                  }
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

// Page builders kept as top-level consts so destination tiles can be `const`.
Widget _centersPageBuilder(BuildContext _) => const CentersPage();
Widget _sportsPageBuilder(BuildContext _) => const SportsSettingsPage();
Widget _teamPageBuilder(BuildContext _) => const TeamPage();
Widget _subscriptionPageBuilder(BuildContext _) => const SubscriptionPage();
Widget _supportPageBuilder(BuildContext _) => const SupportPage();
Widget _auditLogPageBuilder(BuildContext _) => const AuditLogPage();

/// A card that hosts a group of related destination tiles, separated by
/// hairline dividers. Empty groups render nothing.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            tiles[i],
          ],
        ],
      ),
    );
  }
}

/// A single navigable settings row.
class _SettingsDestination extends StatelessWidget {
  const _SettingsDestination({
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

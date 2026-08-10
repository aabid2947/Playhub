import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/academy/presentation/academy_settings_page.dart';
import 'package:playhub/features/audit/presentation/audit_log_page.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/centers/presentation/centers_page.dart';
import 'package:playhub/features/payment_gateways/presentation/payment_gateways_page.dart';
import 'package:playhub/features/sports/presentation/sports_settings_page.dart';
import 'package:playhub/features/subscription/presentation/subscription_page.dart';
import 'package:playhub/features/support/presentation/support_page.dart';
import 'package:playhub/features/users/presentation/team_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Settings body tab (mounted app-bar-less inside `owner_home_shell`) —
/// v1 "Sports-Light", archetype H.
///
/// A navy profile hero anchors the top, then grouped setting rows with tinted
/// leading icons under [AppSectionHeader]s. Every entry point keeps its exact
/// role gate (RLS is the real gate; these flags only hide the entry):
/// * Academy settings → owner only.
/// * Team / Support → owner + admin; Plans & subscription → owner only
///   (`manageSubscription`), since only an owner can complete a checkout.
/// * Centers / Sports / Activity log → all three (visible to every role).
///
/// Sign out lives in the shell's account sheet, so this surface holds settings
/// destinations only.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final caps = ref.watch(capabilitiesProvider);
    final role = profile?.role ?? '';
    final isOwner = role == 'academy_owner';
    final isOwnerOrAdmin = role == 'academy_owner' || role == 'academy_admin';

    final name = profile?.displayName.trim().isNotEmpty ?? false
        ? profile!.displayName
        : 'Your account';

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Navy profile hero — identity + role badge.
        AppGradientHeader(
          colors: AppPalette.navyGradient,
          child: Row(
            children: [
              const AppUserAvatar(size: 56, onGradient: true),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: AppType.heavy,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (role.isNotEmpty)
                      AppGlassChip(
                        _roleLabel(role),
                        icon: Icons.badge_outlined,
                      ),
                  ],
                ),
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
                // Academy — the academy record (name/branding) is owner-only at
                // the RLS layer, so only owners get that entry point;
                // centers/sports configuration is visible to all roles.
                const AppSectionHeader(
                  title: 'Academy',
                  icon: Icons.business_outlined,
                ),
                _SettingsGroup(
                  tiles: [
                    if (isOwner) ...[
                      const _SettingsDestination(
                        icon: Icons.business_outlined,
                        tint: AppPalette.brandPrimary,
                        title: 'Academy settings',
                        subtitle: 'Name, contact, address, branding',
                        builder: _academySettingsPageBuilder,
                      ),
                      const _SettingsDestination(
                        icon: Icons.account_balance_wallet_outlined,
                        tint: AppPalette.brandSecondary,
                        title: 'Payment gateways',
                        subtitle: 'Your Razorpay / Paytm keys for fee payments',
                        builder: _paymentGatewaysPageBuilder,
                      ),
                    ],
                    const _SettingsDestination(
                      icon: Icons.location_on_outlined,
                      tint: AppPalette.accent,
                      title: 'Centers',
                      subtitle: 'Physical locations of your academy',
                      builder: _centersPageBuilder,
                    ),
                    const _SettingsDestination(
                      icon: Icons.sports_outlined,
                      tint: AppPalette.success,
                      title: 'Sports',
                      subtitle: 'Which sports your academy offers',
                      builder: _sportsPageBuilder,
                    ),
                  ],
                ),

                // Team & billing — managing people and the subscription is
                // gated to owners/admins (RLS rejects these writes otherwise).
                if (isOwnerOrAdmin) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const AppSectionHeader(
                    title: 'Team & billing',
                    icon: Icons.group_outlined,
                  ),
                  // The SaaS plan is owner-managed self-serve: the owner can
                  // compare plans, upgrade (platform Razorpay checkout) and see
                  // past SaaS invoices. Per-student fees/invoices are separate
                  // and live under Billing on the home dashboard.
                  _SettingsGroup(
                    tiles: [
                      const _SettingsDestination(
                        icon: Icons.group_outlined,
                        tint: AppPalette.accent,
                        title: 'Team',
                        subtitle: 'Invite admins, coaches, and trainers',
                        builder: _teamPageBuilder,
                      ),
                      if (caps.manageSubscription)
                        const _SettingsDestination(
                          icon: Icons.workspace_premium_outlined,
                          tint: AppPalette.brandPrimary,
                          title: 'Plans & subscription',
                          subtitle: 'Compare plans, upgrade, past invoices',
                          builder: _subscriptionPageBuilder,
                        ),
                      _SettingsDestination(
                        icon: Icons.support_agent_outlined,
                        tint: AppPalette.categorySwatch[3],
                        title: 'Support',
                        subtitle: 'Tickets to PlayHub support',
                        builder: _supportPageBuilder,
                      ),
                    ],
                  ),
                ],

                // Team — non-admin provisioners (center_admin) can invite the
                // rungs below them, scoped to their center by RLS + the
                // invite-user fn. Owners/admins get Team inside "Team & billing"
                // above instead.
                if (caps.canProvisionAnyone && !isOwnerOrAdmin) ...[
                  const SizedBox(height: AppSpacing.lg),
                  const AppSectionHeader(
                    title: 'Team',
                    icon: Icons.group_outlined,
                  ),
                  const _SettingsGroup(
                    tiles: [
                      _SettingsDestination(
                        icon: Icons.group_outlined,
                        tint: AppPalette.accent,
                        title: 'Team',
                        subtitle: 'Invite the staff you manage',
                        builder: _teamPageBuilder,
                      ),
                    ],
                  ),
                ],

                // Support — center_admin gets their own in-app channel to raise
                // issues to the academy's owner/admin (who can mark them
                // resolved). Owners/admins reach Support inside "Team & billing".
                if (role == 'center_admin') ...[
                  const SizedBox(height: AppSpacing.lg),
                  const AppSectionHeader(
                    title: 'Support',
                    icon: Icons.support_agent_outlined,
                  ),
                  _SettingsGroup(
                    tiles: [
                      _SettingsDestination(
                        icon: Icons.support_agent_outlined,
                        tint: AppPalette.categorySwatch[3],
                        title: 'Support',
                        subtitle: 'Raise an issue to your admin',
                        builder: _supportPageBuilder,
                      ),
                    ],
                  ),
                ],

                // Activity — visible to all roles.
                const SizedBox(height: AppSpacing.lg),
                const AppSectionHeader(
                  title: 'Activity',
                  icon: Icons.history_outlined,
                ),
                _SettingsGroup(
                  tiles: [
                    _SettingsDestination(
                      icon: Icons.history_outlined,
                      tint: AppPalette.categorySwatch[5],
                      title: 'Activity log',
                      subtitle: 'Who changed what, recently',
                      builder: _auditLogPageBuilder,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Title-cases a `user_role` enum value for display (e.g. `center_admin` →
/// `Center admin`).
String _roleLabel(String role) {
  if (role.isEmpty) return role;
  final spaced = role.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

// Page builders kept as top-level consts so destination tiles can be `const`.
Widget _academySettingsPageBuilder(BuildContext _) => const AcademySettingsPage();
Widget _paymentGatewaysPageBuilder(BuildContext _) => const PaymentGatewaysPage();
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

/// A single navigable settings row with a tinted leading icon chip.
class _SettingsDestination extends StatelessWidget {
  const _SettingsDestination({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

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
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: builder),
      ),
    );
  }
}

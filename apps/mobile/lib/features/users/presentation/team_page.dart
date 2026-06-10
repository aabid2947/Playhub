import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/users/data/invite_repo.dart';
import 'package:playhub/features/users/presentation/invite_user_sheet.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Team roster — v1 "Sports-Light", archetype B (list, pushed page).
///
/// An in-body header (title + member-count [AppBadge]) and a pinned search sit
/// above role-grouped sections: each [AppSectionHeader] names a role + its
/// count, then a tight run of member [AppCard] tiles ([AppAvatar] + name + role
/// [AppBadge]). The Invite FAB is gated on [Capabilities.canProvisionAnyone];
/// per-member removal is gated on [Capabilities.canInvite] for that rung. RLS
/// (`can_provision_role` / `users_admin_delete`) is the real gate — these gates
/// only hide entry points roles can't act on.
class TeamPage extends ConsumerStatefulWidget {
  const TeamPage({super.key});

  @override
  ConsumerState<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends ConsumerState<TeamPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value.trim().toLowerCase());
  }

  Future<void> _openInvite() async {
    final invited = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const InviteUserSheet(),
    );
    if (invited ?? false) ref.invalidate(teamMembersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(teamMembersProvider);
    final canInviteAnyone = ref.watch(capabilitiesProvider).canProvisionAnyone;

    return Scaffold(
      // Pushed/standalone page — keeps its own AppBar (not a shell body tab).
      appBar: AppBar(
        title: const Text('Team'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(teamMembersProvider),
          ),
        ],
      ),
      floatingActionButton: canInviteAnyone
          ? FloatingActionButton.extended(
              heroTag: 'fab-team',
              icon: const Icon(Icons.person_add),
              label: const Text('Invite'),
              onPressed: _openInvite,
            )
          : null,
      body: async.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(teamMembersProvider),
        ),
        data: (members) {
          if (members.isEmpty) {
            return const AppEmptyState(
              icon: Icons.groups_outlined,
              title: 'No team members yet',
              subtitle: 'Invite admins, coaches, and staff to your academy.',
            );
          }

          final filtered = _query.isEmpty
              ? members
              : members.where((m) => _matches(m, _query)).toList();
          final groups = _groupByRole(filtered);

          return Column(
            children: [
              _SearchBar(
                controller: _search,
                onChanged: _onSearchChanged,
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(teamMembersProvider),
                  child: filtered.isEmpty
                      ? ListView(
                          // Keep pull-to-refresh reachable even with no matches.
                          children: const [
                            SizedBox(height: AppSpacing.xxxl),
                            AppEmptyState(
                              icon: Icons.search_off_outlined,
                              title: 'No matches',
                              subtitle: 'Try a different name or email.',
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.sm,
                            AppSpacing.lg,
                            // Leave room so the last tile clears the FAB.
                            AppSpacing.xxl + AppSpacing.xl,
                          ),
                          itemCount: groups.length + 1,
                          itemBuilder: (context, i) {
                            if (i == 0) {
                              return _ResultHeader(count: filtered.length);
                            }
                            final g = groups[i - 1];
                            return _RoleSection(
                              role: g.role,
                              label: g.label,
                              members: g.members,
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static bool _matches(TeamMember m, String query) {
    return m.displayName.toLowerCase().contains(query) ||
        m.email.toLowerCase().contains(query);
  }

  /// Buckets members into role groups in a fixed seniority order, dropping
  /// empty groups. The provider already orders by role then first name, so
  /// within each group the order is preserved.
  static List<_RoleGroup> _groupByRole(List<TeamMember> members) {
    return _roleOrder
        .map(
          (role) => _RoleGroup(
            role: role,
            label: _groupLabels[role]!,
            members: members.where((m) => m.role == role).toList(),
          ),
        )
        .where((g) => g.members.isNotEmpty)
        .toList();
  }

  static const _roleOrder = <String>[
    'academy_owner',
    'academy_admin',
    'center_admin',
    'head_coach',
    'coach',
    'trainer',
  ];

  static const _groupLabels = <String, String>{
    'academy_owner': 'Owners',
    'academy_admin': 'Admins',
    'center_admin': 'Center admins',
    'head_coach': 'Head coaches',
    'coach': 'Coaches',
    'trainer': 'Trainers',
  };
}

/// Singular, human role label for a member's badge.
String _roleLabel(String role) {
  switch (role) {
    case 'academy_owner':
      return 'Owner';
    case 'academy_admin':
      return 'Admin';
    case 'center_admin':
      return 'Center admin';
    case 'head_coach':
      return 'Head coach';
    case 'coach':
      return 'Coach';
    case 'trainer':
      return 'Trainer';
    default:
      return role;
  }
}

/// A leading glyph per role for the section header.
IconData _roleIcon(String role) {
  switch (role) {
    case 'academy_owner':
      return Icons.workspace_premium_outlined;
    case 'academy_admin':
      return Icons.admin_panel_settings_outlined;
    case 'center_admin':
      return Icons.business_outlined;
    case 'head_coach':
      return Icons.sports_outlined;
    case 'coach':
      return Icons.sports_handball_outlined;
    case 'trainer':
      return Icons.fitness_center_outlined;
    default:
      return Icons.person_outline;
  }
}

class _RoleGroup {
  const _RoleGroup({
    required this.role,
    required this.label,
    required this.members,
  });
  final String role;
  final String label;
  final List<TeamMember> members;
}

/// In-body archetype-B header: a section title with the total member count as a
/// brand [AppBadge].
class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Team members',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: AppType.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          AppBadge(text: '$count', tone: AppBadgeTone.brand),
        ],
      ),
    );
  }
}

/// Pinned client-side search over name + email. Stays a real [TextField] so
/// widget-type finders keep resolving.
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xs,
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: 'Search name or email…',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// One role group: an [AppSectionHeader] (role icon + label + count) above a
/// tight run of member tiles.
class _RoleSection extends StatelessWidget {
  const _RoleSection({
    required this.role,
    required this.label,
    required this.members,
  });

  final String role;
  final String label;
  final List<TeamMember> members;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: label,
          icon: _roleIcon(role),
          trailing: AppBadge(text: '${members.length}'),
        ),
        for (final m in members) ...[
          _MemberTile(member: m),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member});

  final TeamMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The ⋮ actions (reset password, remove) mirror the provisioning ladder:
    // you can only act on a rung you could have invited (canInvite →
    // can_provision_role), and never yourself. RLS (users_admin_delete) is the
    // real gate for removal and also enforces center scope.
    final canManage = member.id != ref.watch(currentUserIdProvider) &&
        ref.watch(capabilitiesProvider).canInvite(member.role);

    return AppCard(
      padding: EdgeInsets.zero,
      child: AppListTile(
        wrapLeading: false,
        leading: AppAvatar(member.displayName, size: 40),
        title: Text(
          member.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          member.email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!member.isActive) ...[
              const AppBadge(text: 'Inactive'),
              const SizedBox(width: AppSpacing.xs),
            ],
            AppBadge(text: _roleLabel(member.role), tone: AppBadgeTone.brand),
            if (canManage)
              PopupMenuButton<String>(
                tooltip: 'Member actions',
                onSelected: (v) {
                  if (v == 'reset') _confirmReset(context, ref);
                  if (v == 'remove') _confirmRemove(context, ref);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem<String>(
                    value: 'reset',
                    child: Text('Send password reset link'),
                  ),
                  PopupMenuItem<String>(
                    value: 'remove',
                    child: Text('Remove from academy'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    if (member.email.isEmpty) {
      AppSnackbar.error(context, 'No email on file for this member.');
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Send password reset link?',
      message:
          'A password-reset email will be sent to ${member.email}. They can '
          'use the link to set a new password and sign in.',
      confirmLabel: 'Send link',
    );
    if (!ok) return;
    try {
      await ref.read(inviteRepoProvider).sendPasswordReset(member.email);
      if (context.mounted) {
        AppSnackbar.success(
          context,
          'Password reset link sent to ${member.email}.',
        );
      }
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: 'Remove ${member.displayName}?',
      message:
          'This deletes their login and revokes their access to this academy. '
          'Any coach or student record they were linked to is kept (just '
          'unlinked). This cannot be undone.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(inviteRepoProvider).removeMember(member.id);
      ref.invalidate(teamMembersProvider);
      if (context.mounted) AppSnackbar.success(context, 'Member removed.');
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }
}

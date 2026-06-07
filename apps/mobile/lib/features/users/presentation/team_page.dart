import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/users/data/invite_repo.dart';
import 'package:playhub/features/users/presentation/invite_user_sheet.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-team',
        icon: const Icon(Icons.person_add),
        label: const Text('Invite'),
        onPressed: _openInvite,
      ),
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
                          padding: const EdgeInsets.only(
                            bottom: AppSpacing.xxxl,
                          ),
                          itemCount: groups.length,
                          itemBuilder: (context, i) => _RoleSection(
                            label: groups[i].label,
                            members: groups[i].members,
                          ),
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

class _RoleGroup {
  const _RoleGroup({required this.label, required this.members});
  final String label;
  final List<TeamMember> members;
}

/// Pinned client-side search over name + email.
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
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: 'Search name or email…',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
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

/// One role group: an [AppSectionHeader] with a member count, then a tight
/// run of member tiles.
class _RoleSection extends StatelessWidget {
  const _RoleSection({required this.label, required this.members});

  final String label;
  final List<TeamMember> members;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: AppSectionHeader(title: '$label · ${members.length}'),
        ),
        for (final m in members) _MemberTile(member: m),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});

  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      wrapLeading: false,
      leading: CircleAvatar(child: Text(_initials(member.displayName))),
      title: Text(member.displayName),
      subtitle: Text(
        member.email,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: AppBadge(
        text: member.isActive ? 'Active' : 'Inactive',
        tone: member.isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }
}

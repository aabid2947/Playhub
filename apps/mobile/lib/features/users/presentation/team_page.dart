import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/users/data/invite_repo.dart';
import 'package:playhub/features/users/presentation/invite_user_sheet.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class TeamPage extends ConsumerWidget {
  const TeamPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(teamMembersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Invite'),
        onPressed: () async {
          final invited = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const InviteUserSheet(),
          );
          if (invited ?? false) ref.invalidate(teamMembersProvider);
        },
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
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(teamMembersProvider),
            child: ListView.separated(
              itemCount: members.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = members[i];
                return AppListTile(
                  wrapLeading: false,
                  leading: CircleAvatar(
                    child: Text(_initials(m.displayName)),
                  ),
                  title: Text(m.displayName),
                  subtitle: Text('${m.email}  •  ${_roleLabel(m.role)}'),
                  trailing:
                      m.isActive ? null : const AppBadge(text: 'Inactive'),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }

  String _roleLabel(String r) =>
      const {
        'academy_owner': 'Owner',
        'academy_admin': 'Admin',
        'center_admin': 'Center admin',
        'head_coach': 'Head coach',
        'coach': 'Coach',
        'trainer': 'Trainer',
        'parent': 'Parent',
        'student': 'Student',
      }[r] ??
      r;
}

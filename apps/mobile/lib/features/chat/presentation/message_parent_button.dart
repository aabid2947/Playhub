import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/chat/data/chat_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// IconButton that opens (or creates) a 1:1 thread with a linked parent
/// of the given student. Hidden when no parent_links exist for the student
/// (so it never offers a dead tap); shown busy while the lookup resolves.
/// When multiple parents are linked, a titled picker sheet asks which.
///
/// Usable from coach + admin contexts — both roles can call
/// ensure_direct_thread RPC.
class MessageParentButton extends ConsumerWidget {
  const MessageParentButton({required this.studentId, super.key});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parents = ref.watch(_studentParentsProvider(studentId));
    return parents.when(
      data: (list) {
        // No linked parent → hide entirely rather than show a dead button.
        if (list.isEmpty) return const SizedBox.shrink();
        return IconButton(
          tooltip: list.length == 1
              ? 'Message ${list.first.displayName}'
              : 'Message a parent',
          // No explicit color: inherits IconTheme so it reads correctly in an
          // app bar or on a colored hero.
          icon: const Icon(Icons.chat_rounded),
          onPressed: () => _start(context, ref, list),
        );
      },
      // While the lookup resolves, show a disabled busy spinner in the button's
      // footprint so the app-bar layout doesn't jump. The spinner adopts the
      // ambient IconTheme color so it stays visible on a colored hero.
      loading: () => IconButton(
        tooltip: 'Loading…',
        icon: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: IconTheme.of(context).color,
          ),
        ),
        onPressed: null,
      ),
      // On error, hide rather than offer a button that can't act.
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    List<_LinkedParent> parents,
  ) async {
    _LinkedParent? chosen;
    if (parents.length == 1) {
      chosen = parents.first;
    } else {
      chosen = await showModalBottomSheet<_LinkedParent>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _ParentPickerSheet(studentId: studentId),
      );
    }
    if (chosen == null) return;
    try {
      final repo = await ref.read(chatRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      final threadId = await repo.ensureDirectThread(chosen.parentUserId);
      if (context.mounted) context.push('/threads/$threadId');
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }
}

/// Titled, scrollable picker for choosing which linked parent to message.
/// Re-watches the linked-parents provider so it owns a real loading/error
/// state rather than assuming the list was prefetched. Pops the chosen
/// [_LinkedParent].
class _ParentPickerSheet extends ConsumerWidget {
  const _ParentPickerSheet({required this.studentId});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final parents = ref.watch(_studentParentsProvider(studentId));

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title row — mixed-case navy heading, v1-style.
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: AppSectionHeader(
                title: 'Message which parent?',
                icon: Icons.chat_rounded,
              ),
            ),
            Flexible(
              child: parents.when(
                data: (list) {
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: AppEmptyState(
                        icon: Icons.people_outline,
                        title: 'No parent linked',
                        subtitle: 'There are no parents linked to this '
                            'student yet.',
                      ),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    children: [
                      for (final p in list)
                        AppListTile(
                          wrapLeading: false,
                          leading: AppAvatar(p.displayName, size: 40),
                          title: Text(p.displayName),
                          subtitle: Text(
                            p.relationship,
                            style: theme.textTheme.bodySmall,
                          ),
                          onTap: () => Navigator.of(context).pop(p),
                        ),
                    ],
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: AppLoading(label: 'Loading parents…'),
                ),
                error: (_, __) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: AppErrorView(
                    message: 'Could not load linked parents.',
                    onRetry: () =>
                        ref.invalidate(_studentParentsProvider(studentId)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkedParent {
  const _LinkedParent({
    required this.parentUserId,
    required this.displayName,
    required this.relationship,
  });
  final String parentUserId;
  final String displayName;
  final String relationship;
}

final _studentParentsProvider =
    FutureProvider.family<List<_LinkedParent>, String>((ref, studentId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('parent_links')
      .select(
          'parent_user_id, relationship, '
          'users:parent_user_id(first_name, last_name, email)')
      .eq('student_id', studentId);
  return (rows as List).map((r) {
    final m = r as Map<String, dynamic>;
    final u = (m['users'] as Map?)?.cast<String, dynamic>();
    final f = (u?['first_name'] as String?) ?? '';
    final l = (u?['last_name'] as String?) ?? '';
    final full = '$f $l'.trim();
    return _LinkedParent(
      parentUserId: m['parent_user_id'] as String,
      displayName: full.isEmpty
          ? ((u?['email'] as String?) ?? '(unknown)')
          : full,
      relationship: (m['relationship'] as String?) ?? 'parent',
    );
  }).toList(growable: false);
});

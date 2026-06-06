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
          icon: const Icon(Icons.chat_outlined),
          onPressed: () => _start(context, ref, list),
        );
      },
      // While the lookup resolves, show a disabled busy spinner in the
      // button's footprint so the app bar layout doesn't jump.
      loading: () => const IconButton(
        tooltip: 'Loading…',
        icon: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
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
    final scheme = theme.colorScheme;
    final parents = ref.watch(_studentParentsProvider(studentId));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.md),
            // Drag handle — anchors the sheet and signals it's dismissible.
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Title row.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  Icon(Icons.chat_outlined, color: scheme.primary),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Message which parent?',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
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
                          leading: const Icon(Icons.person_outline),
                          title: Text(p.displayName),
                          subtitle: Text(p.relationship),
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

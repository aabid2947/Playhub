import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/chat/data/chat_providers.dart';

/// IconButton that opens (or creates) a 1:1 thread with a linked parent
/// of the given student. Disabled when no parent_links exist for the
/// student. When multiple parents are linked, a picker sheet asks which.
///
/// Usable from coach + admin contexts — both roles can call
/// ensure_direct_thread RPC.
class MessageParentButton extends ConsumerWidget {
  const MessageParentButton({required this.studentId, super.key});
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parents = ref.watch(_studentParentsProvider(studentId));
    return parents.maybeWhen(
      data: (list) => IconButton(
        tooltip: list.isEmpty
            ? 'No parent linked yet'
            : list.length == 1
                ? 'Message ${list.first.displayName}'
                : 'Message a parent',
        icon: const Icon(Icons.chat_outlined),
        onPressed: list.isEmpty
            ? null
            : () => _start(context, ref, list),
      ),
      orElse: () => const IconButton(
        icon: Icon(Icons.chat_outlined),
        onPressed: null,
      ),
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
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Message which parent?'),
              ),
              for (final p in parents)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(p.displayName),
                  subtitle: Text(p.relationship),
                  onTap: () => Navigator.of(context).pop(p),
                ),
            ],
          ),
        ),
      );
    }
    if (chosen == null) return;
    try {
      final repo = await ref.read(chatRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      final threadId = await repo.ensureDirectThread(chosen.parentUserId);
      if (context.mounted) context.push('/threads/$threadId');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
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

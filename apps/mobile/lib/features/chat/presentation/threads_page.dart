import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/chat/data/chat.dart';
import 'package:playhub/features/chat/data/chat_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Inbox of message threads the user can see. Direct threads resolve the other
/// participant's name via [userDisplayNameProvider]; batch threads use their
/// title. Tapping a row opens the thread at `/threads/:id`.
class ThreadsPage extends ConsumerWidget {
  const ThreadsPage({super.key, this.embedded = false});

  /// When embedded in a shell that already provides an AppBar, suppress this
  /// page's own AppBar (its refresh falls back to pull-to-refresh) to avoid a
  /// second bar.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myThreadsProvider);
    final me = ref.watch(supabaseClientProvider).auth.currentUser?.id ?? '';
    return Scaffold(
      appBar: embedded
          ? null
          : AppBar(
              title: const Text('Messages'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: () => ref.invalidate(myThreadsProvider),
                ),
              ],
            ),
      body: async.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(myThreadsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const AppEmptyState(
              icon: Icons.forum_outlined,
              title: 'No conversations yet',
              subtitle: 'Messages from coaches and parents appear here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myThreadsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => _ThreadTile(thread: list[i], me: me),
            ),
          );
        },
      ),
    );
  }
}

/// A single inbox row: a tinted kind avatar → the thread name → the last
/// message preview → the relative time of the last activity.
class _ThreadTile extends ConsumerWidget {
  const _ThreadTile({required this.thread, required this.me});

  final MessageThread thread;
  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBatch = thread.kind == ThreadKind.batch;
    final otherId = isBatch ? null : thread.otherUserId(me);

    // Batch threads carry a title; direct threads resolve the counterpart's
    // name asynchronously. Resolution is cached per-user by the family
    // provider, so once a name lands it stays put and the row stops flickering.
    final String name;
    if (isBatch) {
      name = thread.title ?? 'Batch chat';
    } else if (otherId == null) {
      name = 'Conversation';
    } else {
      final nameAsync = ref.watch(userDisplayNameProvider(otherId));
      // Keep the last resolved value while a refresh is in flight instead of
      // dropping back to a placeholder — avoids the name flicker on rebuild.
      name = nameAsync.valueOrNull ?? 'Loading…';
    }

    return _ThreadRow(thread: thread, name: name, isBatch: isBatch);
  }
}

/// Pure presentation for a thread row, given the already-resolved [name]. Split
/// out so the async name lookup doesn't rebuild the row's structure.
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.name,
    required this.isBatch,
  });

  final MessageThread thread;
  final String name;
  final bool isBatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final preview = thread.lastMessagePreview;
    final hasPreview = preview != null && preview.trim().isNotEmpty;
    final subtitle = Text(
      hasPreview ? preview : 'No messages yet',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        fontStyle: hasPreview ? FontStyle.normal : FontStyle.italic,
      ),
    );

    final lastAt = thread.lastMessageAt;
    final trailing = lastAt == null
        ? null
        : Text(
            _relativeTime(lastAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          );

    return AppListTile(
      wrapLeading: false,
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Icon(
          isBatch ? Icons.groups_outlined : Icons.person_outline,
          color: scheme.onPrimaryContainer,
        ),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle,
      trailing: trailing,
      onTap: () => context.push('/threads/${thread.id}'),
    );
  }

  /// Compact relative age of the last message ("now", "5m", "3h", "2d").
  static String _relativeTime(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }
}

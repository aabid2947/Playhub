import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/chat/data/chat.dart';
import 'package:playhub/features/chat/data/chat_providers.dart';

class ThreadsPage extends ConsumerWidget {
  const ThreadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myThreadsProvider);
    final me = ref.watch(supabaseClientProvider).auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(myThreadsProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
                child: Text('No conversations yet'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) =>
                _Tile(t: list[i], me: me ?? ''),
          );
        },
      ),
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.t, required this.me});
  final MessageThread t;
  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = t.kind == ThreadKind.batch
        ? (t.title ?? 'Batch chat')
        : t.otherUserId(me) == null
            ? '(unknown)'
            : null;
    final subtitle = t.lastMessagePreview ?? '—';
    final trailing = t.lastMessageAt == null
        ? const SizedBox.shrink()
        : Text(_short(t.lastMessageAt!));

    Widget tileTitle(String resolved) => ListTile(
          leading: CircleAvatar(
            child: Icon(t.kind == ThreadKind.batch
                ? Icons.groups
                : Icons.person),
          ),
          title: Text(resolved),
          subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: trailing,
          onTap: () => context.push('/threads/${t.id}'),
        );

    if (title != null) return tileTitle(title);

    final otherId = t.otherUserId(me);
    if (otherId == null) return tileTitle('(unknown)');
    final nameAsync = ref.watch(userDisplayNameProvider(otherId));
    return nameAsync.maybeWhen(
      data: tileTitle,
      orElse: () => tileTitle('…'),
    );
  }

  static String _short(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }
}

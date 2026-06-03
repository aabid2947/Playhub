import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/features/notifications/data/notification.dart';
import 'package:playhub/features/notifications/data/notification_providers.dart';
import 'package:playhub/core/error_messages.dart';

class NotificationCenterPage extends ConsumerWidget {
  const NotificationCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsStreamProvider);
    final repo = ref.watch(notificationsRepoProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Mark all read',
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              await repo.markAllRead();
            },
          ),
          IconButton(
            tooltip: 'Preferences',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/settings/notifications'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('You\'re all caught up'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) =>
                _Tile(n: list[i]),
          );
        },
      ),
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.n});
  final AppNotification n;

  IconData _iconFor(String category) {
    switch (category) {
      case 'announcement':
        return Icons.campaign_outlined;
      case 'message':
        return Icons.chat_outlined;
      case 'attendance':
        return Icons.event_available_outlined;
      case 'performance':
        return Icons.bar_chart;
      case 'invoice':
        return Icons.receipt_long_outlined;
      case 'payment':
        return Icons.payments_outlined;
      case 'lead':
        return Icons.person_search_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(child: Icon(_iconFor(n.category))),
      title: Text(
        n.title,
        style: TextStyle(
          fontWeight: n.isUnread ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
      subtitle: n.body == null ? null : Text(n.body!),
      trailing: Text(_short(n.createdAt)),
      onTap: () async {
        if (n.isUnread) {
          await ref.read(notificationsRepoProvider).markRead(n.id);
        }
        if (n.deepLink != null && context.mounted) {
          context.push(n.deepLink!);
        }
      },
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

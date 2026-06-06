import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/notifications/data/notification.dart';
import 'package:playhub/features/notifications/data/notification_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class NotificationCenterPage extends ConsumerWidget {
  const NotificationCenterPage({super.key, this.embedded = false});

  /// When embedded in a shell that already provides an AppBar, this page drops
  /// its own AppBar; its mark-all-read + preferences actions move into a compact
  /// in-body toolbar so nothing is lost (coach/parent shells have no Settings
  /// tab to reach preferences otherwise).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsStreamProvider);
    final repo = ref.watch(notificationsRepoProvider);
    final content = async.when(
      loading: () => const AppLoading(),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(notificationsStreamProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const AppEmptyState(
            icon: Icons.notifications_none_outlined,
            title: "You're all caught up",
          );
        }
        final sections = _groupByDate(list);
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          itemCount: sections.length,
          itemBuilder: (_, i) {
            final section = sections[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    0,
                  ),
                  child: AppSectionHeader(title: section.label),
                ),
                for (final n in section.items) _Tile(n: n),
              ],
            );
          },
        );
      },
    );
    return Scaffold(
      appBar: embedded
          ? null
          : AppBar(
              title: const Text('Notifications'),
              actions: [
                IconButton(
                  tooltip: 'Mark all read',
                  icon: const Icon(Icons.done_all),
                  onPressed: () => _confirmMarkAllRead(context, repo),
                ),
                IconButton(
                  tooltip: 'Preferences',
                  icon: const Icon(Icons.tune),
                  onPressed: () => context.push('/settings/notifications'),
                ),
              ],
            ),
      // Embedded: no AppBar, so surface mark-all-read + preferences in a thin
      // in-body toolbar above the list.
      body: embedded
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    0,
                  ),
                  child: Row(
                    children: [
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.done_all),
                        label: const Text('Mark all read'),
                        onPressed: () => _confirmMarkAllRead(context, repo),
                      ),
                      IconButton(
                        tooltip: 'Preferences',
                        icon: const Icon(Icons.tune),
                        onPressed: () =>
                            context.push('/settings/notifications'),
                      ),
                    ],
                  ),
                ),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }

  Future<void> _confirmMarkAllRead(
    BuildContext context,
    NotificationsRepo repo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark all as read?'),
        content: const Text(
          'All notifications will be marked as read.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Mark all read'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await repo.markAllRead();
    }
  }

  /// Splits the (already newest-first) list into Today / Earlier sections,
  /// preserving order and dropping empty groups.
  static List<_NotificationSection> _groupByDate(List<AppNotification> list) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayItems = <AppNotification>[];
    final earlierItems = <AppNotification>[];
    for (final n in list) {
      final created = n.createdAt;
      final createdDay = DateTime(created.year, created.month, created.day);
      if (!createdDay.isBefore(today)) {
        todayItems.add(n);
      } else {
        earlierItems.add(n);
      }
    }
    return [
      if (todayItems.isNotEmpty)
        _NotificationSection(label: 'Today', items: todayItems),
      if (earlierItems.isNotEmpty)
        _NotificationSection(label: 'Earlier', items: earlierItems),
    ];
  }
}

class _NotificationSection {
  const _NotificationSection({required this.label, required this.items});
  final String label;
  final List<AppNotification> items;
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppListTile(
      leading: _LeadingIcon(
        icon: _iconFor(n.category),
        unread: n.isUnread,
      ),
      title: Text(
        n.title,
        style: n.isUnread
            ? null
            : theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
      ),
      subtitle: n.body == null
          ? null
          : Text(
              n.body!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _relative(n.createdAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _absolute(n.createdAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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

  static String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  static String _absolute(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final period = d.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}

/// Category icon with an unread dot affordance overlaid on the top-right.
class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.icon, required this.unread});

  final IconData icon;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (unread)
          Positioned(
            top: -AppSpacing.xs,
            right: -AppSpacing.xs,
            child: Container(
              width: AppSpacing.sm,
              height: AppSpacing.sm,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

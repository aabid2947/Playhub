import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/notifications/data/notification.dart';
import 'package:playhub/features/notifications/data/notification_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Notification center — v1 "Sports-Light", archetype B (list), date-grouped.
///
/// Rows are tinted-icon [AppCard]/[AppListTile]s grouped under
/// [AppSectionHeader] date buckets (Today / Yesterday / Earlier); unread rows
/// carry a subtle brand tint and a "New" badge. Presentation only — every
/// provider read, the mark-read / mark-all-read mutations, and the preferences
/// entry point are preserved exactly.
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          itemCount: sections.length,
          itemBuilder: (_, i) {
            final section = sections[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSectionHeader(
                  title: section.label,
                  icon: Icons.notifications_active_outlined,
                ),
                for (final n in section.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _Tile(n: n),
                  ),
                const SizedBox(height: AppSpacing.sm),
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

  /// Splits the (already newest-first) list into Today / Yesterday / Earlier
  /// sections, preserving order and dropping empty groups.
  static List<_NotificationSection> _groupByDate(List<AppNotification> list) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final todayItems = <AppNotification>[];
    final yesterdayItems = <AppNotification>[];
    final earlierItems = <AppNotification>[];
    for (final n in list) {
      final created = n.createdAt;
      final createdDay = DateTime(created.year, created.month, created.day);
      if (!createdDay.isBefore(today)) {
        todayItems.add(n);
      } else if (createdDay == yesterday) {
        yesterdayItems.add(n);
      } else {
        earlierItems.add(n);
      }
    }
    return [
      if (todayItems.isNotEmpty)
        _NotificationSection(label: 'Today', items: todayItems),
      if (yesterdayItems.isNotEmpty)
        _NotificationSection(label: 'Yesterday', items: yesterdayItems),
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

/// Per-category icon + accent tint. Status-flavoured categories (invoice,
/// payment, lead) borrow the semantic tones; the rest pull a stable accent
/// from the shared category swatch so each type reads with a consistent tile.
({IconData icon, Color tint}) _styleFor(
  String category,
  AppSemanticColors semantics,
) {
  switch (category) {
    case 'announcement':
      return (icon: Icons.campaign_outlined, tint: AppPalette.brandPrimary);
    case 'message':
      return (icon: Icons.chat_bubble_outline, tint: AppPalette.accent);
    case 'attendance':
      return (
        icon: Icons.event_available_outlined,
        tint: semantics.success,
      );
    case 'performance':
      return (icon: Icons.insights_outlined, tint: AppPalette.categorySwatch[3]);
    case 'invoice':
      return (icon: Icons.receipt_long_outlined, tint: semantics.warning);
    case 'payment':
      return (icon: Icons.payments_outlined, tint: semantics.success);
    case 'lead':
      return (icon: Icons.person_search_outlined, tint: AppPalette.accent);
    default:
      return (
        icon: Icons.notifications_outlined,
        tint: AppPalette.categorySwatch[1],
      );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.n});
  final AppNotification n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantics = AppSemanticColors.of(context);
    final style = _styleFor(n.category, semantics);
    final unread = n.isUnread;

    return AppCard(
      padding: EdgeInsets.zero,
      // Unread rows lift with a soft brand tint; read rows stay on surface.
      color: unread
          ? scheme.primary.withValues(alpha: 0.06)
          : scheme.surface,
      onTap: () async {
        if (n.isUnread) {
          await ref.read(notificationsRepoProvider).markRead(n.id);
        }
        if (n.deepLink != null && context.mounted) {
          unawaited(context.push(n.deepLink!));
        }
      },
      child: AppListTile(
        wrapLeading: false,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: style.tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(style.icon, color: style.tint, size: 20),
        ),
        title: Text(
          n.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: unread
              ? null
              : theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: AppType.regular,
                ),
        ),
        subtitle: n.body == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  n.body!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _relative(n.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (unread) ...[
              const SizedBox(height: AppSpacing.xs),
              const AppBadge(text: 'New', tone: AppBadgeTone.brand),
            ],
          ],
        ),
      ),
    );
  }

  static String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

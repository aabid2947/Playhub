import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/announcements/data/announcement.dart';
import 'package:playhub/features/announcements/data/announcement_providers.dart';
import 'package:playhub/features/announcements/presentation/announcement_composer_page.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

final _absoluteFmt = DateFormat('dd MMM yyyy · HH:mm');

/// Admin sees ALL announcements (history + drafts); other roles see their
/// targeted feed (with read receipts).
class AnnouncementsPage extends ConsumerWidget {
  const AnnouncementsPage({super.key, this.embedded = false});

  /// When embedded in a shell that already provides an AppBar, suppress this
  /// page's own AppBar to avoid a second bar.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    return profileAsync.when(
      loading: () => const Scaffold(body: AppLoading()),
      error: (e, _) => Scaffold(
        body: AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(currentProfileProvider),
        ),
      ),
      data: (profile) {
        final isAdmin = profile?.role == 'academy_owner' ||
            profile?.role == 'academy_admin';
        return Scaffold(
          appBar: embedded
              ? null
              : AppBar(title: const Text('Announcements')),
          floatingActionButton: isAdmin
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AnnouncementComposerPage(),
                    ),
                  ),
                )
              : null,
          body: isAdmin ? const _AdminList() : const _Feed(),
        );
      },
    );
  }
}

/// Admin compose/history view: every announcement in the academy with a
/// Draft/Sent badge and (for sent ones) a delivery count.
class _AdminList extends ConsumerWidget {
  const _AdminList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(announcementsListProvider);
    return async.when(
      loading: () => const AppSkeletonList(),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(announcementsListProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const AppEmptyState(
            icon: Icons.campaign_outlined,
            title: 'No announcements yet',
            subtitle: 'Tap "New" to broadcast to roles, batches, or centers.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(announcementsListProvider),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final a = list[i];
              return AppListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: Text(a.subject),
                subtitle: Text(
                  _adminSubtitle(a),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: a.isDraft
                    ? const AppBadge(text: 'Draft', tone: AppBadgeTone.warning)
                    : const AppBadge(text: 'Sent', tone: AppBadgeTone.success),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _AnnouncementDetailPage(announcement: a),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// One tight line: delivery count for sent items, sent date for drafts.
  static String _adminSubtitle(Announcement a) {
    if (a.isDraft) return 'Not sent yet';
    final sent = '${a.sentCount ?? 0} delivered';
    final failed = (a.failedCount ?? 0) > 0 ? ' · ${a.failedCount} failed' : '';
    return '$sent$failed';
  }
}

/// Recipient feed: announcements actually targeted at this user, newest first,
/// with an unread affordance. Tapping opens a real detail surface and marks
/// the item read before navigating.
class _Feed extends ConsumerWidget {
  const _Feed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(announcementFeedProvider);
    final scheme = Theme.of(context).colorScheme;
    return async.when(
      loading: () => const AppSkeletonList(),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(announcementFeedProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const AppEmptyState(
            icon: Icons.campaign_outlined,
            title: 'No announcements',
            subtitle: 'Updates from your academy will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(announcementFeedProvider),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final it = items[i];
              final ann = it.announcement;
              final unread = it.readAt == null;
              final theme = Theme.of(context);
              return AppListTile(
                wrapLeading: false,
                leading: Icon(
                  unread
                      ? Icons.fiber_manual_record
                      : Icons.fiber_manual_record_outlined,
                  size: 14,
                  color: unread ? scheme.primary : scheme.outline,
                ),
                title: Text(
                  ann.subject,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: unread ? AppType.bold : AppType.regular,
                  ),
                ),
                subtitle: Text(
                  ann.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: unread
                    ? const AppBadge(text: 'New', tone: AppBadgeTone.brand)
                    : Text(
                        _relative(ann.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                onTap: () => _open(context, ref, it),
              );
            },
          ),
        );
      },
    );
  }

  /// Mark read (so the feed updates predictably), then open the detail page.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    AnnouncementFeedItem it,
  ) async {
    if (it.readAt == null) {
      final repo = await ref.read(announcementsRepoProvider.future);
      await repo?.markRead(it.announcement.id);
      ref.invalidate(announcementFeedProvider);
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AnnouncementDetailPage(announcement: it.announcement),
      ),
    );
  }

  static String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'just now';
  }
}

/// Full-page detail surface for an announcement (§3.2): a header card with the
/// subject + status/timestamp, then the message body in its own section.
class _AnnouncementDetailPage extends StatelessWidget {
  const _AnnouncementDetailPage({required this.announcement});

  final Announcement announcement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = announcement;
    final timestamp = a.sentAt ?? a.createdAt;
    final statusBadge = a.isDraft
        ? const AppBadge(text: 'Draft', tone: AppBadgeTone.warning)
        : const AppBadge(text: 'Sent', tone: AppBadgeTone.success);
    return Scaffold(
      appBar: AppBar(title: Text(a.subject)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        a.subject,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    statusBadge,
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      _absoluteFmt.format(timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const AppSectionHeader(title: 'Message'),
          AppCard(
            child: Text(
              a.body,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

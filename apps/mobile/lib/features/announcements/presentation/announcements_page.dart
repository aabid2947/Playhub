import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/announcements/data/announcement_providers.dart';
import 'package:playhub/features/announcements/presentation/announcement_composer_page.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Admin sees ALL announcements (history + drafts); other roles see their
/// targeted feed (with read receipts).
class AnnouncementsPage extends ConsumerWidget {
  const AnnouncementsPage({super.key});

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
          appBar: AppBar(
            title: const Text('Announcements'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: () {
                  ref
                    ..invalidate(announcementsListProvider)
                    ..invalidate(announcementFeedProvider);
                },
              ),
            ],
          ),
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
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final a = list[i];
              return AppListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: Text(a.subject),
                subtitle: Text(
                  a.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: a.isDraft
                    ? const AppBadge(text: 'Draft', tone: AppBadgeTone.warning)
                    : Text('${a.sentCount ?? 0} sent'),
              );
            },
          ),
        );
      },
    );
  }
}

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
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final it = items[i];
              final unread = it.readAt == null;
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
                  it.announcement.subject,
                  style: TextStyle(
                    fontWeight:
                        unread ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  it.announcement.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  _dt(it.announcement.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                onTap: () async {
                  final repo =
                      await ref.read(announcementsRepoProvider.future);
                  await repo?.markRead(it.announcement.id);
                  ref.invalidate(announcementFeedProvider);
                  if (context.mounted) {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(it.announcement.subject),
                        content: SingleChildScrollView(
                          child: Text(it.announcement.body),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  }
                },
              );
            },
          ),
        );
      },
    );
  }

  static String _dt(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'just now';
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/announcements/data/announcement.dart';
import 'package:playhub/features/announcements/data/announcement_providers.dart';
import 'package:playhub/features/announcements/presentation/announcement_composer_page.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

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
        // Composers (admin tier + center_admin + head_coach + coach) get the
        // compose FAB and a history/compose list (RLS scopes it to rows they
        // created + were delivered). Pure recipients get the read-receipt feed.
        final canCompose = ref.watch(capabilitiesProvider).composeAnnouncements;
        return Scaffold(
          appBar: embedded
              ? null
              : AppBar(title: const Text('Announcements')),
          floatingActionButton: canCompose
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
          body: canCompose ? const _AdminList() : const _Feed(),
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
/// subject + status/timestamp, then the message body in its own section, then
/// any attached photos/videos.
class _AnnouncementDetailPage extends ConsumerWidget {
  const _AnnouncementDetailPage({required this.announcement});

  final Announcement announcement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = announcement;
    final timestamp = a.sentAt ?? a.createdAt;
    final statusBadge = a.isDraft
        ? const AppBadge(text: 'Draft', tone: AppBadgeTone.warning)
        : const AppBadge(text: 'Sent', tone: AppBadgeTone.success);
    return Scaffold(
      // Generic title — the subject is the prominent heading in the body now.
      appBar: AppBar(title: const Text('Announcement')),
      body: ListView(
        // No outer padding — the hero image runs edge-to-edge at the top; the
        // text content below is padded. Reads as one cohesive post.
        padding: EdgeInsets.zero,
        children: [
          if (a.media.isNotEmpty) _HeroMedia(media: a.media.first),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.subject,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: AppType.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    statusBadge,
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      Icons.schedule_outlined,
                      size: 14,
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
                const SizedBox(height: AppSpacing.lg),
                Text(
                  a.body,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                ),
                // Extra images (beyond the hero) shown as a strip below the body.
                if (a.media.length > 1) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const AppSectionHeader(title: 'More photos'),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: a.media.length - 1,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: AppSpacing.sm),
                      itemBuilder: (_, i) =>
                          _DetailMediaThumb(media: a.media[i + 1]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width hero for the first attachment, at the top of the detail post.
/// Tapping opens the file externally via a fresh signed URL (private bucket).
class _HeroMedia extends ConsumerWidget {
  const _HeroMedia({required this.media});
  final AnnouncementMedia media;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final storage = ref.read(storageServiceProvider);
    try {
      final url = await storage.signedAnnouncementMediaUrl(media.path);
      final ok = await launcher.launchUrl(
        Uri.parse(url),
        mode: launcher.LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        AppSnackbar.error(context, 'Could not open file.');
      }
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    final Widget inner;
    if (media.isVideo) {
      inner = ColoredBox(
        color: fill,
        child: const Center(child: Icon(Icons.play_circle_outline, size: 56)),
      );
    } else {
      inner = FutureBuilder<String>(
        future: ref
            .read(storageServiceProvider)
            .signedAnnouncementMediaUrl(media.path),
        builder: (_, snap) {
          if (snap.data == null) {
            return ColoredBox(
              color: fill,
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return CachedNetworkImage(
            imageUrl: snap.data!,
            fit: BoxFit.cover,
            placeholder: (_, __) => ColoredBox(color: fill),
            errorWidget: (_, __, ___) => ColoredBox(
              color: fill,
              child: const Icon(Icons.broken_image_outlined),
            ),
          );
        },
      );
    }
    return GestureDetector(
      onTap: () => _open(context, ref),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: SizedBox.expand(child: inner),
      ),
    );
  }
}

/// A tappable thumbnail in the detail view — opens the file externally via a
/// fresh signed URL (the bucket is private).
class _DetailMediaThumb extends ConsumerWidget {
  const _DetailMediaThumb({required this.media});
  final AnnouncementMedia media;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final storage = ref.read(storageServiceProvider);
    try {
      final url = await storage.signedAnnouncementMediaUrl(media.path);
      final ok = await launcher.launchUrl(
        Uri.parse(url),
        mode: launcher.LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        AppSnackbar.error(context, 'Could not open file.');
      }
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    final Widget inner;
    if (media.isVideo) {
      inner = ColoredBox(
        color: fill,
        child: const Center(child: Icon(Icons.play_circle_outline, size: 30)),
      );
    } else {
      inner = FutureBuilder<String>(
        future:
            ref.read(storageServiceProvider).signedAnnouncementMediaUrl(media.path),
        builder: (_, snap) {
          if (snap.data == null) return ColoredBox(color: fill);
          return CachedNetworkImage(
            imageUrl: snap.data!,
            fit: BoxFit.cover,
            placeholder: (_, __) => ColoredBox(color: fill),
            errorWidget: (_, __, ___) => ColoredBox(
              color: fill,
              child: const Icon(Icons.broken_image_outlined),
            ),
          );
        },
      );
    }
    return GestureDetector(
      onTap: () => _open(context, ref),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(width: 96, height: 96, child: inner),
      ),
    );
  }
}

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

/// Announcements — v1 "Sports-Light", archetype B (list).
///
/// Composers (admin tier + center_admin + head_coach + coach) see the full
/// history/compose list (RLS scopes it to rows they created + were delivered)
/// with a Draft/Sent badge; pure recipients see their targeted feed with an
/// unread affordance. Both render the **same tile anatomy** (a campaign-iconed
/// [AppCard] → subject → one subtitle → trailing status/metric), differing only
/// in the trailing chip and whether tapping marks the item read first.
class AnnouncementsPage extends ConsumerWidget {
  const AnnouncementsPage({super.key, this.embedded = false});

  /// When embedded in a shell that already provides an AppBar, suppress this
  /// page's own AppBar (an in-body header carries the title instead).
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
        final canCompose = ref.watch(capabilitiesProvider).composeAnnouncements;
        return Scaffold(
          appBar:
              embedded ? null : AppBar(title: const Text('Announcements')),
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
          body: canCompose
              ? _AdminList(embedded: embedded)
              : _Feed(embedded: embedded),
        );
      },
    );
  }
}

/// Admin compose/history view: every announcement in the academy with a
/// Draft/Sent badge and (for sent ones) a delivery count.
class _AdminList extends ConsumerWidget {
  const _AdminList({required this.embedded});

  final bool embedded;

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
          return _ListScaffold(
            embedded: embedded,
            title: 'Announcements',
            subtitle: 'Broadcasts you send',
            count: 0,
            onRefresh: () async => ref.invalidate(announcementsListProvider),
            child: const AppEmptyState(
              icon: Icons.campaign_outlined,
              title: 'No announcements yet',
              subtitle: 'Tap "New" to broadcast to roles, batches, or centers.',
            ),
          );
        }
        return _ListScaffold(
          embedded: embedded,
          title: 'Announcements',
          subtitle: 'Broadcasts you send',
          count: list.length,
          onRefresh: () async => ref.invalidate(announcementsListProvider),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              // Clear the FAB.
              AppSpacing.xxl + AppSpacing.xl,
            ),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) {
              final a = list[i];
              return _AnnouncementTile(
                subject: a.subject,
                preview: _adminSubtitle(a),
                hasMedia: a.media.isNotEmpty,
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
  const _Feed({required this.embedded});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(announcementFeedProvider);
    return async.when(
      loading: () => const AppSkeletonList(),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(announcementFeedProvider),
      ),
      data: (items) {
        final unreadCount = items.where((it) => it.readAt == null).length;
        if (items.isEmpty) {
          return _ListScaffold(
            embedded: embedded,
            title: 'Announcements',
            subtitle: 'Updates from your academy',
            count: 0,
            onRefresh: () async => ref.invalidate(announcementFeedProvider),
            child: const AppEmptyState(
              icon: Icons.campaign_outlined,
              title: 'No announcements',
              subtitle: 'Updates from your academy will appear here.',
            ),
          );
        }
        return _ListScaffold(
          embedded: embedded,
          title: 'Announcements',
          subtitle: unreadCount > 0
              ? '$unreadCount unread'
              : 'Updates from your academy',
          count: items.length,
          onRefresh: () async => ref.invalidate(announcementFeedProvider),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) {
              final it = items[i];
              final ann = it.announcement;
              final unread = it.readAt == null;
              return _AnnouncementTile(
                subject: ann.subject,
                preview: ann.body,
                hasMedia: ann.media.isNotEmpty,
                unread: unread,
                trailing: unread
                    ? const AppBadge(text: 'New', tone: AppBadgeTone.brand)
                    : _TimeLabel(ann.createdAt),
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
}

/// Shared chrome for both views: an in-body header (title + subtitle + count
/// badge) when embedded in a shell, then the pull-to-refresh body. When the
/// page owns an AppBar (pushed standalone), the title there carries the name,
/// so the in-body header collapses to just the count strip.
class _ListScaffold extends StatelessWidget {
  const _ListScaffold({
    required this.embedded,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onRefresh,
    required this.child,
  });

  final bool embedded;
  final String title;
  final String subtitle;
  final int count;
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (embedded)
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: AppType.heavy,
                          color: scheme.onSurface,
                        ),
                      ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (count > 0) AppBadge(text: '$count'),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: child,
          ),
        ),
      ],
    );
  }
}

/// The unified announcement tile shared by the admin list and the recipient
/// feed: a campaign-iconed [AppCard] with the subject, one preview line, an
/// optional media glyph, and a trailing status/metric. Unread feed items lift
/// to a brand-tinted icon and a bold subject.
class _AnnouncementTile extends StatelessWidget {
  const _AnnouncementTile({
    required this.subject,
    required this.preview,
    required this.hasMedia,
    required this.trailing,
    required this.onTap,
    this.unread = false,
  });

  final String subject;
  final String preview;
  final bool hasMedia;
  final Widget trailing;
  final VoidCallback onTap;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iconTint = unread ? scheme.primary : scheme.onSurfaceVariant;
    final iconBg = unread
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(Icons.campaign_rounded, size: 22, color: iconTint),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: unread ? AppType.bold : AppType.semibold,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    if (hasMedia) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Icon(
                        Icons.image_outlined,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          trailing,
        ],
      ),
    );
  }
}

/// A muted relative-time label ("2d", "5h", "just now") for read feed items.
class _TimeLabel extends StatelessWidget {
  const _TimeLabel(this.when);
  final DateTime when;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      _relative(when),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
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

/// Full-page detail surface for an announcement (§3.2): an entity-colored
/// gradient hero with the subject + status/timestamp, then the message body in
/// its own section, then any attached photos/videos.
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
      body: ListView(
        // No outer padding — the hero band runs edge-to-edge at the top; the
        // text content below is padded. Reads as one cohesive post.
        padding: EdgeInsets.zero,
        children: [
          AppGradientHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppCircleIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const Spacer(),
                    const AppGlassChip('Announcement', icon: Icons.campaign),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  a.subject,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: AppType.heavy,
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
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      _absoluteFmt.format(timestamp),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (a.media.isNotEmpty) _HeroMedia(media: a.media.first),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.body,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    color: scheme.onSurface,
                  ),
                ),
                // Extra images (beyond the hero) shown as a strip below the body.
                if (a.media.length > 1) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const AppSectionHeader(
                    title: 'More photos',
                    icon: Icons.photo_library_outlined,
                  ),
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

/// Full-width hero for the first attachment, just under the gradient band.
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
        future: ref
            .read(storageServiceProvider)
            .signedAnnouncementMediaUrl(media.path),
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

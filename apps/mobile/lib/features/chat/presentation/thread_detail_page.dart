import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/storage_service.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/chat/data/attachment.dart';
import 'package:playhub/features/chat/data/chat.dart';
import 'package:playhub/features/chat/data/chat_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

final _timeFmt = DateFormat('HH:mm');
final _dayFmt = DateFormat('EEE, dd MMM yyyy');

/// Realtime chat view. Subscribes to messages stream for this thread,
/// renders day-grouped bubbles (text + attachments + timestamp), and posts
/// new ones via `chatRepo.send()`. Marks the thread read on entry.
class ThreadDetailPage extends ConsumerStatefulWidget {
  const ThreadDetailPage({required this.threadId, super.key});
  final String threadId;

  @override
  ConsumerState<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends ConsumerState<ThreadDetailPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatAttachment> _pending = [];
  bool _sending = false;

  /// Tracks the last rendered message count so we only auto-scroll when new
  /// messages actually arrive (not on every rebuild), and only if the user is
  /// already pinned near the bottom — scrolling up to read history is sticky.
  int _lastCount = 0;
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = await ref.read(chatRepoProvider.future);
      await repo?.markRead(widget.threadId);
    });
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // Within a bubble's height of the end counts as "at the bottom".
    final atBottom = pos.pixels >= pos.maxScrollExtent - 80;
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
  }

  void _scrollToLatest({bool animate = false}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (animate) {
      _scroll.animateTo(
        target,
        duration: AppDuration.normal,
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  /// Called after the message list rebuilds. Jumps to the latest only when the
  /// count grew and the user was already at the bottom, so incoming realtime
  /// messages don't yank the viewport away from someone reading older history.
  void _maybeAutoScroll(int count) {
    final grew = count > _lastCount;
    _lastCount = count;
    if (!grew) return;
    if (!_atBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _pending.isEmpty) return;
    setState(() => _sending = true);
    try {
      final repo = await ref.read(chatRepoProvider.future);
      await repo?.send(
        widget.threadId,
        text,
        attachments: List.unmodifiable(_pending),
      );
      _ctrl.clear();
      setState(_pending.clear);
      // The sender always wants to see their own message land.
      _atBottom = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToLatest(animate: true));
    } on Object catch (e) {
      // Without this the send error (e.g. an RLS 42501 when the sender isn't a
      // thread participant) escapes as an uncaught zoned error. Surface a
      // friendly message and keep the draft so the user can retry.
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAttachment() async {
    final profile = await ref.read(currentProfileProvider.future);
    final academyId = profile?.academyId;
    if (academyId == null) return;
    final kind = await showModalBottomSheet<_AttachKind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                'Attach',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Photo'),
              onTap: () => Navigator.of(ctx).pop(_AttachKind.image),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Video'),
              onTap: () => Navigator.of(ctx).pop(_AttachKind.video),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Document'),
              onTap: () => Navigator.of(ctx).pop(_AttachKind.doc),
            ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final storage = ref.read(storageServiceProvider);
      ChatAttachment? picked;
      switch (kind) {
        case _AttachKind.image:
          picked = await storage.pickChatImage(
            academyId: academyId,
            threadId: widget.threadId,
          );
        case _AttachKind.video:
          picked = await storage.pickChatVideo(
            academyId: academyId,
            threadId: widget.threadId,
          );
        case _AttachKind.doc:
          picked = await storage.pickChatDocument(
            academyId: academyId,
            threadId: widget.threadId,
          );
      }
      if (picked != null && mounted) {
        setState(() => _pending.add(picked!));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _removePending(int i) async {
    final removed = _pending[i];
    setState(() => _pending.removeAt(i));
    // Best-effort cleanup so we don't orphan an unused object.
    final storage = ref.read(storageServiceProvider);
    await storage.deleteChatAttachment(removed.path);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(supabaseClientProvider).auth.currentUser?.id ?? '';
    final messagesAsync = ref.watch(threadMessagesProvider(widget.threadId));
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const AppLoading(),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () =>
                    ref.invalidate(threadMessagesProvider(widget.threadId)),
              ),
              data: (msgs) {
                if (msgs.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.forum_outlined,
                    title: 'No messages yet',
                    subtitle: 'Say hi to get the conversation started.',
                  );
                }
                _maybeAutoScroll(msgs.length);
                return _MessageList(
                  messages: msgs,
                  me: me,
                  controller: _scroll,
                  showJumpToLatest: !_atBottom,
                  onJumpToLatest: () => _scrollToLatest(animate: true),
                );
              },
            ),
          ),
          _Composer(
            controller: _ctrl,
            pending: _pending,
            sending: _sending,
            onPick: _pickAttachment,
            onRemovePending: _removePending,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

enum _AttachKind { image, video, doc }

IconData _iconFor(ChatAttachment a) {
  if (a.isImage) return Icons.image_outlined;
  if (a.isVideo) return Icons.videocam_outlined;
  return Icons.description_outlined;
}

/// Returns a friendly day label for a message timestamp ("Today",
/// "Yesterday", or an absolute date) used for the day-separator headers.
String _dayLabel(DateTime when) {
  final now = DateTime.now();
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final delta = today.difference(day).inDays;
  if (delta == 0) return 'Today';
  if (delta == 1) return 'Yesterday';
  return _dayFmt.format(when);
}

/// The scrolling message area: day-grouped bubbles plus a floating
/// "jump to latest" affordance when the user has scrolled up.
class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.me,
    required this.controller,
    required this.showJumpToLatest,
    required this.onJumpToLatest,
  });

  final List<Message> messages;
  final String me;
  final ScrollController controller;
  final bool showJumpToLatest;
  final VoidCallback onJumpToLatest;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView.builder(
          controller: controller,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          itemCount: messages.length,
          itemBuilder: (_, i) {
            final m = messages[i];
            final prev = i == 0 ? null : messages[i - 1];
            final showDay = prev == null ||
                !_sameDay(prev.createdAt, m.createdAt);
            final mine = m.senderId == me;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDay) _DayDivider(label: _dayLabel(m.createdAt)),
                _MessageBubble(message: m, mine: mine),
              ],
            );
          },
        ),
        if (showJumpToLatest)
          Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: FloatingActionButton.small(
              heroTag: 'chatJumpToLatest',
              tooltip: 'Jump to latest',
              onPressed: onJumpToLatest,
              child: const Icon(Icons.keyboard_double_arrow_down),
            ),
          ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// A centered pill marking the start of a new day in the transcript.
class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});
  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasText = message.content.isNotEmpty;
    final edited = message.editedAt != null;
    final time = _timeFmt.format(message.createdAt);
    final metaColor = (mine ? scheme.onPrimaryContainer : scheme.onSurface)
        .withValues(alpha: 0.6);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final a in message.attachments) ...[
              _AttachmentPreview(attachment: a),
              if (a != message.attachments.last || hasText)
                const SizedBox(height: AppSpacing.sm),
            ],
            if (hasText)
              Text(
                message.content,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: mine ? scheme.onPrimaryContainer : scheme.onSurface,
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (edited) ...[
                  Text(
                    'edited',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: metaColor,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  time,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: metaColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom input bar: a bounded horizontal tray of pending attachments above a
/// single-row composer. The tray is height-bounded so it never crowds the
/// growing multiline text field.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.pending,
    required this.sending,
    required this.onPick,
    required this.onRemovePending,
    required this.onSend,
  });

  final TextEditingController controller;
  final List<ChatAttachment> pending;
  final bool sending;
  final VoidCallback onPick;
  final void Function(int index) onRemovePending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pending.isNotEmpty)
              _PendingTray(
                pending: pending,
                enabled: !sending,
                onRemove: onRemovePending,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'Attach',
                    onPressed: sending ? null : onPick,
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton.filled(
                    tooltip: 'Send',
                    icon: sending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: sending ? null : onSend,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontally scrolling, height-bounded list of removable attachment chips
/// staged for the next send.
class _PendingTray extends StatelessWidget {
  const _PendingTray({
    required this.pending,
    required this.enabled,
    required this.onRemove,
  });

  final List<ChatAttachment> pending;
  final bool enabled;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          0,
        ),
        itemCount: pending.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) => InputChip(
          avatar: Icon(_iconFor(pending[i]), size: 16),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              pending[i].name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          onDeleted: enabled ? () => onRemove(i) : null,
        ),
      ),
    );
  }
}

class _AttachmentPreview extends ConsumerWidget {
  const _AttachmentPreview({required this.attachment});
  final ChatAttachment attachment;

  Future<void> _open(WidgetRef ref) async {
    final storage = ref.read(storageServiceProvider);
    final url = await storage.signedChatAttachmentUrl(attachment.path);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (attachment.isImage) {
      return _ImagePreview(attachment: attachment, onTap: () => _open(ref));
    }
    final theme = Theme.of(context);
    final icon = attachment.isVideo
        ? Icons.play_circle_outline
        : Icons.insert_drive_file_outlined;
    final label = attachment.isVideo ? 'Video' : 'Document';
    return InkWell(
      onTap: () => _open(ref),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  Text(
                    attachment.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Image preview backed by a signed URL (private bucket). Cached on success
/// so the URL is only fetched once per session.
class _ImagePreview extends ConsumerStatefulWidget {
  const _ImagePreview({required this.attachment, required this.onTap});
  final ChatAttachment attachment;
  final VoidCallback onTap;

  @override
  ConsumerState<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends ConsumerState<_ImagePreview> {
  Future<String>? _url;

  @override
  void initState() {
    super.initState();
    _url = ref
        .read(storageServiceProvider)
        .signedChatAttachmentUrl(widget.attachment.path);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<String>(
      future: _url,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            width: 220,
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || !snap.hasData) {
          return const Icon(Icons.broken_image_outlined);
        }
        return GestureDetector(
          onTap: widget.onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: CachedNetworkImage(
              imageUrl: snap.data!,
              fit: BoxFit.cover,
              width: 220,
              height: 140,
              placeholder: (_, __) => Container(
                color: scheme.surfaceContainer,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (_, __, ___) => Container(
                color: scheme.surfaceContainer,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        );
      },
    );
  }
}

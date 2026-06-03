import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/storage_service.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/chat/data/attachment.dart';
import 'package:playhub/features/chat/data/chat.dart';
import 'package:playhub/features/chat/data/chat_providers.dart';
import 'package:url_launcher/url_launcher.dart';

/// Realtime chat view. Subscribes to messages stream for this thread,
/// renders bubbles (text + attachments), and posts new ones via
/// `chatRepo.send()`. Marks the thread read on entry.
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = await ref.read(chatRepoProvider.future);
      await repo?.markRead(widget.threadId);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
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
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              academyId: academyId, threadId: widget.threadId);
        case _AttachKind.video:
          picked = await storage.pickChatVideo(
              academyId: academyId, threadId: widget.threadId);
        case _AttachKind.doc:
          picked = await storage.pickChatDocument(
              academyId: academyId, threadId: widget.threadId);
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
    final messagesAsync =
        ref.watch(threadMessagesProvider(widget.threadId));
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(friendlyError(e))),
              data: (msgs) {
                if (msgs.isEmpty) {
                  return const Center(child: Text('Say hi 👋'));
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scroll.hasClients) {
                    _scroll.jumpTo(_scroll.position.maxScrollExtent);
                  }
                });
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m = msgs[i];
                    final mine = m.senderId == me;
                    return _MessageBubble(message: m, mine: mine);
                  },
                );
              },
            ),
          ),
          if (_pending.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < _pending.length; i++)
                      InputChip(
                        avatar: Icon(_iconFor(_pending[i]), size: 16),
                        label: Text(
                          _pending[i].name,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onDeleted: _sending ? null : () => _removePending(i),
                      ),
                  ],
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'Attach',
                    onPressed: _sending ? null : _pickAttachment,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    icon: _sending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});
  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final a in message.attachments) ...[
              _AttachmentPreview(attachment: a),
              if (a != message.attachments.last || message.content.isNotEmpty)
                const SizedBox(height: 6),
            ],
            if (message.content.isNotEmpty) Text(message.content),
          ],
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
    final icon = attachment.isVideo
        ? Icons.play_circle_outline
        : Icons.insert_drive_file_outlined;
    final label = attachment.isVideo ? 'Video' : 'Document';
    return InkWell(
      onTap: () => _open(ref),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.labelMedium),
                  Text(
                    attachment.name,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
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
    _url = ref.read(storageServiceProvider)
        .signedChatAttachmentUrl(widget.attachment.path);
  }

  @override
  Widget build(BuildContext context) {
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
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: snap.data!,
              fit: BoxFit.cover,
              width: 220,
              height: 140,
              placeholder: (_, __) => Container(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (_, __, ___) => Container(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        );
      },
    );
  }
}

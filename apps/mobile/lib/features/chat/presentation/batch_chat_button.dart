import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/chat/data/chat_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Opens (or creates) the batch's group chat thread. The
/// ensure_batch_thread RPC handles participant sync — every active
/// enrolled student's parent + the batch coach + students with their
/// own login are added.
class BatchChatButton extends ConsumerStatefulWidget {
  const BatchChatButton({
    required this.batchId,
    this.label = 'Batch chat',
    this.compact = false,
    super.key,
  });

  final String batchId;
  final String label;
  final bool compact;

  @override
  ConsumerState<BatchChatButton> createState() => _BatchChatButtonState();
}

class _BatchChatButtonState extends ConsumerState<BatchChatButton> {
  bool _busy = false;

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final repo = await ref.read(chatRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      final threadId = await repo.ensureBatchThread(widget.batchId);
      if (mounted) context.push('/threads/$threadId');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return IconButton(
        tooltip: widget.label,
        icon: _busy
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.forum_outlined),
        onPressed: _busy ? null : _open,
      );
    }
    return FilledButton.tonalIcon(
      icon: _busy
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.forum_outlined),
      label: Text(widget.label),
      onPressed: _busy ? null : _open,
    );
  }
}

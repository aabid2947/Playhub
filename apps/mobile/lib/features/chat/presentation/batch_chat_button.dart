import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/chat/data/chat_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Edge length of the inline busy spinner — sits inside a standard 24px icon
/// slot without resizing the button.
const double _kSpinnerSize = 16;

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
        // The tooltip carries the busy state for the icon-only variant.
        tooltip: _busy ? 'Opening chat…' : widget.label,
        icon: _busy
            ? const _BusySpinner()
            : const Icon(Icons.forum_outlined),
        onPressed: _busy ? null : _open,
      );
    }
    return FilledButton.tonalIcon(
      // Swap the leading icon for a spinner and reword the label so the
      // disabled state reads as "working", not just greyed-out.
      icon: _busy
          ? const _BusySpinner()
          : const Icon(Icons.forum_outlined),
      label: Text(_busy ? 'Opening…' : widget.label),
      onPressed: _busy ? null : _open,
    );
  }
}

/// A small determinate-feeling spinner sized to slot in where an icon would
/// sit, so the button keeps a stable footprint while busy.
class _BusySpinner extends StatelessWidget {
  const _BusySpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: _kSpinnerSize,
      width: _kSpinnerSize,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

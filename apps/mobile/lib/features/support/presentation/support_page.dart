import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart'
    show SupportTicketRow, ticketMessagesProvider;
import 'package:playhub/features/support/data/support_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Maps a ticket priority to a badge tone. One mapping helper for the domain,
/// reused by the list and the thread header (no hand-coloured indicators).
/// Mirrors the super-tickets reference so both surfaces read identically.
AppBadgeTone _priorityTone(String priority) {
  switch (priority) {
    case 'urgent':
      return AppBadgeTone.danger;
    case 'high':
      return AppBadgeTone.warning;
    case 'low':
      return AppBadgeTone.neutral;
    case 'normal':
    default:
      return AppBadgeTone.info;
  }
}

/// Maps a ticket status to a badge tone.
AppBadgeTone _statusTone(String status) {
  switch (status) {
    case 'open':
      return AppBadgeTone.info;
    case 'in_progress':
      return AppBadgeTone.brand;
    case 'waiting_on_user':
      return AppBadgeTone.warning;
    case 'resolved':
      return AppBadgeTone.success;
    case 'closed':
    default:
      return AppBadgeTone.neutral;
  }
}

/// Human label for an enum-ish status/priority token (`in_progress` → `In
/// progress`). Display only — the underlying value is never mutated.
String _humanize(String token) {
  if (token.isEmpty) return token;
  final spaced = token.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

class SupportPage extends ConsumerWidget {
  const SupportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myAcademyTicketsProvider);
    final df = DateFormat('dd MMM · HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(myAcademyTicketsProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New ticket'),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const _NewTicketSheet(),
        ),
      ),
      body: async.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(myAcademyTicketsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const AppEmptyState(
              icon: Icons.support_agent_outlined,
              title: 'No tickets yet',
              subtitle: "Tap 'New ticket' to reach out.",
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myAcademyTicketsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final t = rows[i];
                return AppListTile(
                  leading: const Icon(Icons.confirmation_number_outlined),
                  title: Text(
                    t.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppBadge(
                          text: _humanize(t.priority),
                          tone: _priorityTone(t.priority),
                        ),
                        Text(df.format(t.createdAt)),
                      ],
                    ),
                  ),
                  trailing: AppBadge(
                    text: _humanize(t.status),
                    tone: _statusTone(t.status),
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _TicketThreadPage(ticket: t),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _NewTicketSheet extends ConsumerStatefulWidget {
  const _NewTicketSheet();

  @override
  ConsumerState<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends ConsumerState<_NewTicketSheet> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String _priority = 'normal';
  String? _category;
  bool _saving = false;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_subject.text.trim().isEmpty || _body.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(supportRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.createTicket(
        subject: _subject.text.trim(),
        body: _body.text.trim(),
        category: _category,
        priority: _priority,
      );
      ref.invalidate(myAcademyTicketsProvider);
      if (!mounted) return;
      AppSnackbar.success(context, 'Ticket created.');
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Title row + scrollable body + keyboard insets so the sheet never clips
    // behind the keyboard (the previous Column-min layout did). Height bounded
    // so a long description stays scrollable rather than pushing the sheet off.
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      child: Text(
                        'New support ticket',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  children: [
                    AppFormField(controller: _subject, label: 'Subject'),
                    const SizedBox(height: AppSpacing.md),
                    AppFormField(
                      controller: _body,
                      label: 'Describe the issue',
                      maxLines: 6,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppDropdownField<String?>(
                      label: 'Category',
                      value: _category,
                      items: const [
                        DropdownMenuItem<String?>(child: Text('— None —')),
                        DropdownMenuItem(
                          value: 'billing',
                          child: Text('Billing'),
                        ),
                        DropdownMenuItem(value: 'bug', child: Text('Bug')),
                        DropdownMenuItem(
                          value: 'feature',
                          child: Text('Feature'),
                        ),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (v) => setState(() => _category = v),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppDropdownField<String>(
                      label: 'Priority',
                      value: _priority,
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Low')),
                        DropdownMenuItem(
                          value: 'normal',
                          child: Text('Normal'),
                        ),
                        DropdownMenuItem(value: 'high', child: Text('High')),
                        DropdownMenuItem(
                          value: 'urgent',
                          child: Text('Urgent'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _priority = v ?? 'normal'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Submit'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketThreadPage extends ConsumerStatefulWidget {
  const _TicketThreadPage({required this.ticket});
  final SupportTicketRow ticket;

  @override
  ConsumerState<_TicketThreadPage> createState() => _TicketThreadPageState();
}

class _TicketThreadPageState extends ConsumerState<_TicketThreadPage> {
  final _reply = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(supportRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.postReply(ticketId: widget.ticket.id, body: body);
      _reply.clear();
      ref.invalidate(ticketMessagesProvider(widget.ticket.id));
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('dd MMM yyyy · HH:mm');
    final msgsAsync = ref.watch(ticketMessagesProvider(widget.ticket.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.ticket.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const AppSectionHeader(title: 'Original ticket'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          AppBadge(
                            text: _humanize(widget.ticket.status),
                            tone: _statusTone(widget.ticket.status),
                          ),
                          AppBadge(
                            text: _humanize(widget.ticket.priority),
                            tone: _priorityTone(widget.ticket.priority),
                          ),
                          if (widget.ticket.category != null)
                            AppBadge(
                              text: _humanize(widget.ticket.category!),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        widget.ticket.body,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Raised ${df.format(widget.ticket.createdAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const AppSectionHeader(title: 'Replies'),
                msgsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    child: AppLoading(),
                  ),
                  error: (e, _) => AppErrorView(
                    message: friendlyError(e),
                    onRetry: () => ref.invalidate(
                      ticketMessagesProvider(widget.ticket.id),
                    ),
                  ),
                  data: (msgs) {
                    if (msgs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        child: Text(
                          'No replies yet.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final m in msgs)
                          _ReplyBubble(
                            body: m.body,
                            isStaff: m.isStaff,
                            timestamp: df.format(m.createdAt),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      decoration: const InputDecoration(
                        hintText: 'Your reply…',
                      ),
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send reply',
                    icon: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: _busy ? null : _send,
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

/// A single reply in the thread, matching the super-tickets `_ReplyBubble`.
/// Support staff sit on the left (neutral); the academy's own replies sit on
/// the right with a brand tint. Each shows an author label + timestamp so the
/// conversation is unambiguous.
class _ReplyBubble extends StatelessWidget {
  const _ReplyBubble({
    required this.body,
    required this.isStaff,
    required this.timestamp,
  });

  final String body;
  final bool isStaff;
  final String timestamp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // From the academy's side, "us" is the academy (non-staff) reply, so it
    // takes the brand tint on the right; staff replies are neutral on the left.
    final isOwn = !isStaff;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            color: isOwn ? theme.colorScheme.primaryContainer : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isStaff ? 'Support staff' : 'You',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: AppType.semibold,
                        color: isOwn
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      timestamp,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isOwn
                            ? theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.7)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isOwn
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

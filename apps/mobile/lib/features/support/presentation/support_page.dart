import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
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

/// Support tickets — v1 "Sports-Light", archetype B (list). Pushed/standalone
/// page, so it keeps its own [AppBar]. A column of ticket [AppCard] rows (each a
/// brand-tinted icon tile → subject → priority · date → status badge) sits over
/// a visible result count; the create FAB opens the v1 [_NewTicketSheet].
class SupportPage extends ConsumerWidget {
  const SupportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myAcademyTicketsProvider);
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
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                // Leave room so the last card clears the FAB.
                AppSpacing.xxl + AppSpacing.xl,
              ),
              itemCount: rows.length + 1,
              separatorBuilder: (_, i) => i == 0
                  ? const SizedBox.shrink()
                  : const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) {
                if (i == 0) return _ResultCount(count: rows.length);
                final t = rows[i - 1];
                return _TicketCard(
                  ticket: t,
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

/// Visible result count above the list, e.g. "12 tickets".
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        count == 1 ? '1 ticket' : '$count tickets',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// One ticket row: a brand-tinted icon tile → subject → priority · date line →
/// status [AppBadge]. Fixed-height single-line subtitle so the card height never
/// varies; tones come from the shared [_priorityTone] / [_statusTone] mappers.
class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onTap});
  final SupportTicketRow ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('dd MMM · HH:mm');
    final tint = theme.colorScheme.primary;
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: AppListTile(
        wrapLeading: false,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(
            Icons.confirmation_number_outlined,
            color: tint,
            size: 20,
          ),
        ),
        title: Text(
          ticket.subject,
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
              Text(
                ticket.reference,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: AppType.semibold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              AppBadge(
                text: _humanize(ticket.priority),
                tone: _priorityTone(ticket.priority),
              ),
              Text(df.format(ticket.createdAt)),
            ],
          ),
        ),
        trailing: AppBadge(
          text: _humanize(ticket.status),
          tone: _statusTone(ticket.status),
        ),
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
  final _body = TextEditingController();
  bool _urgent = false;
  bool _saving = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _body.text.trim();
    if (body.isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = await ref.read(supportRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      // The user types once — derive a subject from the first line so they
      // don't have to fill a separate field.
      final firstLine = body.split('\n').first.trim();
      final subject = firstLine.isEmpty
          ? 'Support request'
          : (firstLine.length <= 80
              ? firstLine
              : '${firstLine.substring(0, 77)}…');
      final ticket = await repo.createTicket(
        subject: subject,
        body: body,
        priority: _urgent ? 'urgent' : 'normal',
      );
      ref.invalidate(myAcademyTicketsProvider);
      if (!mounted) return;
      // Show the ticket number prominently so the user can quote it, then close.
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline),
          title: Text('Ticket ${ticket.reference} raised'),
          content: const Text(
            "We've received your request and will get back to you. "
            'Note this number to follow up.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
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
              // v1 grab handle so the sheet reads as a draggable surface.
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Raise a ticket',
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
                    // One field — just describe the problem. Staff triage the
                    // category/priority on their side, so a normal academy user
                    // can raise a ticket in seconds.
                    AppFormField(
                      controller: _body,
                      label: "What's the problem?",
                      maxLines: 6,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('This is urgent'),
                      subtitle: const Text(
                        'Flag it so support picks it up first.',
                      ),
                      value: _urgent,
                      onChanged: (v) => setState(() => _urgent = v),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Send'),
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
  // Local status mirror so a "Mark resolved" reflects immediately without
  // re-fetching the whole thread.
  late String _status = widget.ticket.status;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  bool get _isClosedOrResolved => _status == 'resolved' || _status == 'closed';

  Future<void> _setStatus(String status) async {
    setState(() => _busy = true);
    try {
      final repo = await ref.read(supportRepoProvider.future);
      if (repo == null) throw StateError('no academy');
      await repo.setStatus(ticketId: widget.ticket.id, status: status);
      ref.invalidate(myAcademyTicketsProvider);
      if (!mounted) return;
      setState(() => _status = status);
      AppSnackbar.success(context, 'Marked ${_humanize(status)}.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final role = ref.watch(currentProfileProvider).valueOrNull?.role;
    // Only the academy's owner/admin resolve tickets (RLS enforces it too).
    final canResolve = role == 'academy_owner' || role == 'academy_admin';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.ticket.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (canResolve && !_isClosedOrResolved)
            TextButton.icon(
              onPressed: _busy ? null : () => _setStatus('resolved'),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Resolve'),
            ),
          if (canResolve && _isClosedOrResolved)
            TextButton.icon(
              onPressed: _busy ? null : () => _setStatus('open'),
              icon: const Icon(Icons.refresh),
              label: const Text('Reopen'),
            ),
        ],
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
                            text: _humanize(_status),
                            tone: _statusTone(_status),
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
                        'Ticket ${widget.ticket.reference} · '
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

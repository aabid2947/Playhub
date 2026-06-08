import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Maps a ticket priority to a badge tone. One mapping helper for the domain,
/// reused by the list and detail header (no hand-coloured indicators).
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
/// progress`). Keeps the underlying value (sent to [updateTicket]) untouched.
String _humanize(String token) {
  if (token.isEmpty) return token;
  final spaced = token.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// The status transitions a staff member can apply, in workflow order.
const _statusOptions = <String>[
  'open',
  'in_progress',
  'waiting_on_user',
  'resolved',
  'closed',
];

/// Selectable priorities (low → urgent).
const _priorityOptions = <String>['low', 'normal', 'high', 'urgent'];

class SuperTicketsPage extends ConsumerWidget {
  const SuperTicketsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allTicketsProvider);
    final df = DateFormat('dd MMM · HH:mm');
    return async.when(
      loading: () => const AppSkeletonList(),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(allTicketsProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const AppEmptyState(
            icon: Icons.support_agent_outlined,
            title: 'No tickets',
            subtitle: 'Academy support requests will show up here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(allTicketsProvider),
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
                    builder: (_) => _TicketDetailPage(ticket: t),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TicketDetailPage extends ConsumerStatefulWidget {
  const _TicketDetailPage({required this.ticket});
  final SupportTicketRow ticket;

  @override
  ConsumerState<_TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends ConsumerState<_TicketDetailPage> {
  final _reply = TextEditingController();
  bool _busy = false;

  // Tracks status/priority/assignee locally so the controls reflect a
  // just-applied change without popping the page (the list still re-reads on
  // invalidate).
  late String _status = widget.ticket.status;
  late String _priority = widget.ticket.priority;
  late String? _assignedTo = widget.ticket.assignedTo;

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
      await ref
          .read(superAdminRepoProvider)
          .postStaffReply(
            ticketId: widget.ticket.id,
            academyId: widget.ticket.academyId,
            body: body,
          );
      _reply.clear();
      ref.invalidate(ticketMessagesProvider(widget.ticket.id));
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(String status) async {
    if (status == _status) return;
    try {
      await ref
          .read(superAdminRepoProvider)
          .updateTicket(widget.ticket.id, status: status);
      ref.invalidate(allTicketsProvider);
      if (!mounted) return;
      setState(() => _status = status);
      AppSnackbar.success(context, 'Marked ${_humanize(status)}.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _setPriority(String priority) async {
    if (priority == _priority) return;
    try {
      await ref
          .read(superAdminRepoProvider)
          .updateTicket(widget.ticket.id, priority: priority);
      ref.invalidate(allTicketsProvider);
      if (!mounted) return;
      setState(() => _priority = priority);
      AppSnackbar.success(context, 'Priority set to ${_humanize(priority)}.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  Future<void> _toggleAssign() async {
    final myId = ref.read(currentUserIdProvider);
    if (myId == null) return;
    final mineNow = _assignedTo == myId;
    final next = mineNow ? null : myId;
    try {
      await ref
          .read(superAdminRepoProvider)
          .setTicketAssignee(widget.ticket.id, next);
      ref.invalidate(allTicketsProvider);
      if (!mounted) return;
      setState(() => _assignedTo = next);
      AppSnackbar.success(context, mineNow ? 'Unassigned.' : 'Assigned to you.');
    } on Object catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('dd MMM yyyy · HH:mm');
    final msgsAsync = ref.watch(ticketMessagesProvider(widget.ticket.id));
    final myId = ref.watch(currentUserIdProvider);
    final assignedToMe = _assignedTo != null && _assignedTo == myId;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.ticket.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Status control that SHOWS the current state (badge), and on tap
          // offers the transitions with the active one ticked.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: PopupMenuButton<String>(
              tooltip: 'Change status',
              onSelected: _setStatus,
              itemBuilder: (_) => [
                for (final s in _statusOptions)
                  PopupMenuItem<String>(
                    value: s,
                    child: Row(
                      children: [
                        Icon(
                          s == _status
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: s == _status
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(_humanize(s)),
                      ],
                    ),
                  ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppBadge(
                    text: _humanize(_status),
                    tone: _statusTone(_status),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
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
                            AppBadge(text: _humanize(widget.ticket.category!)),
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
                const AppSectionHeader(title: 'Manage'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Priority',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Change priority',
                            onSelected: _setPriority,
                            itemBuilder: (_) => [
                              for (final p in _priorityOptions)
                                PopupMenuItem<String>(
                                  value: p,
                                  child: Row(
                                    children: [
                                      Icon(
                                        p == _priority
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_unchecked,
                                        size: 18,
                                        color: p == _priority
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Text(_humanize(p)),
                                    ],
                                  ),
                                ),
                            ],
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppBadge(
                                  text: _humanize(_priority),
                                  tone: _priorityTone(_priority),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Divider(height: 1),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Icon(
                            Icons.assignment_ind_outlined,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              assignedToMe
                                  ? 'Assigned to you'
                                  : (_assignedTo == null
                                      ? 'Unassigned'
                                      : 'Assigned to another staffer'),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          OutlinedButton(
                            onPressed: myId == null ? null : _toggleAssign,
                            child: Text(assignedToMe ? 'Unassign' : 'Assign to me'),
                          ),
                        ],
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
                        hintText: 'Staff reply…',
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

/// A single reply in the thread. Staff replies sit on the right with a brand
/// tint; academy replies sit on the left. Each shows an author label + time so
/// the conversation is unambiguous.
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: isStaff ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            color: isStaff ? theme.colorScheme.primaryContainer : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isStaff ? 'Support staff' : 'Academy',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: AppType.semibold,
                        color: isStaff
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      timestamp,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isStaff
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
                    color: isStaff
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

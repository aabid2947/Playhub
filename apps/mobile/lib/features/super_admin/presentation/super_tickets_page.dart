import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class SuperTicketsPage extends ConsumerWidget {
  const SuperTicketsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allTicketsProvider);
    final df = DateFormat('dd MMM · HH:mm');
    return async.when(
      loading: () => const AppLoading(),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(allTicketsProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const AppEmptyState(
            icon: Icons.support_agent_outlined,
            title: 'No tickets',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(allTicketsProvider),
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final t = rows[i];
              // Kept as a bare ListTile because the leading CircleAvatar is a
              // priority-coloured indicator that must not be re-tinted by
              // AppListTile's primaryContainer wrapper.
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: _priorityColor(context, t.priority),
                  child: Text(t.priority[0].toUpperCase()),
                ),
                title: Text(
                  t.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${t.status} · ${df.format(t.createdAt)}'),
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

  Color _priorityColor(BuildContext c, String p) {
    switch (p) {
      case 'urgent':
        return Theme.of(c).colorScheme.error;
      case 'high':
        return Colors.orange;
      case 'low':
        return Colors.blueGrey;
    }
    return Theme.of(c).colorScheme.primaryContainer;
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
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, '$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(String status) async {
    await ref
        .read(superAdminRepoProvider)
        .updateTicket(widget.ticket.id, status: status);
    ref.invalidate(allTicketsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final msgsAsync = ref.watch(ticketMessagesProvider(widget.ticket.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.ticket.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: _setStatus,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'open', child: Text('Mark open')),
              PopupMenuItem(value: 'in_progress', child: Text('In progress')),
              PopupMenuItem(
                value: 'waiting_on_user',
                child: Text('Waiting on user'),
              ),
              PopupMenuItem(value: 'resolved', child: Text('Resolved')),
              PopupMenuItem(value: 'closed', child: Text('Close')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: ${widget.ticket.status} · '
                        'Priority: ${widget.ticket.priority}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Text(widget.ticket.body),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                msgsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(friendlyError(e)),
                  data: (msgs) => Column(
                    children: [
                      for (final m in msgs)
                        Align(
                          alignment: m.isStaff
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: AppCard(
                            padding: const EdgeInsets.all(AppSpacing.sm + 2),
                            color: m.isStaff
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            child: Text(m.body),
                          ),
                        ),
                    ],
                  ),
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
                    icon: const Icon(Icons.send),
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

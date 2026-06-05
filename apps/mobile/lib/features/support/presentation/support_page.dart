import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart'
    show SupportTicketRow, ticketMessagesProvider;
import 'package:playhub/features/support/data/support_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
        loading: () => const AppLoading(),
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
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final t = rows[i];
              return AppListTile(
                title: Text(
                  t.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${t.status} · ${df.format(t.createdAt)}'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _TicketThreadPage(ticket: t),
                  ),
                ),
              );
            },
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'New support ticket',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppFormField(controller: _subject, label: 'Subject'),
          const SizedBox(height: AppSpacing.md),
          AppFormField(
            controller: _body,
            label: 'Describe the issue',
            maxLines: 10,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppDropdownField<String?>(
                  label: 'Category',
                  value: _category,
                  items: const [
                    DropdownMenuItem<String?>(child: Text('— None —')),
                    DropdownMenuItem(value: 'billing', child: Text('Billing')),
                    DropdownMenuItem(value: 'bug', child: Text('Bug')),
                    DropdownMenuItem(value: 'feature', child: Text('Feature')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) => setState(() => _category = v),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppDropdownField<String>(
                  label: 'Priority',
                  value: _priority,
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                  ],
                  onChanged: (v) => setState(() => _priority = v ?? 'normal'),
                ),
              ),
            ],
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
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: ${widget.ticket.status} · '
                        'Priority: ${widget.ticket.priority}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(widget.ticket.body),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                msgsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(
                    friendlyError(e),
                    style: TextStyle(
                      color: AppSemanticColors.of(context).danger,
                    ),
                  ),
                  data: (msgs) => Column(
                    children: [
                      for (final m in msgs)
                        Align(
                          alignment: m.isStaff
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Card(
                            color: m.isStaff
                                ? null
                                : Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Text(m.body),
                            ),
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
                        hintText: 'Your reply…',
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

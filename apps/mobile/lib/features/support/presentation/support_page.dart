import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/features/super_admin/data/super_admin_providers.dart'
    show SupportTicketRow, ticketMessagesProvider;
import 'package:playhub/features/support/data/support_providers.dart';
import 'package:playhub/core/error_messages.dart';

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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "No tickets yet. Tap 'New ticket' to reach out.",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final t = rows[i];
              return ListTile(
                title: Text(t.subject,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
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
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
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
          Text('New support ticket',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _subject,
            decoration: const InputDecoration(labelText: 'Subject'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(labelText: 'Describe the issue'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
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
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'normal', child: Text('Normal')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                    DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                  ],
                  onChanged: (v) =>
                      setState(() => _priority = v ?? 'normal'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgsAsync = ref.watch(ticketMessagesProvider(widget.ticket.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ticket.subject,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
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
                ),
                const SizedBox(height: 8),
                msgsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(friendlyError(e)),
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
                                : Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(10),
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
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      decoration:
                          const InputDecoration(hintText: 'Your reply…'),
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

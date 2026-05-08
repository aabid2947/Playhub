import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/leads/data/lead.dart';
import 'package:playhub/features/leads/data/lead_providers.dart';
import 'package:playhub/features/leads/presentation/lead_convert_sheet.dart';

class LeadDetailPage extends ConsumerWidget {
  const LeadDetailPage({required this.leadId, super.key});
  final String leadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leadAsync = ref.watch(leadByIdProvider(leadId));
    final actsAsync = ref.watch(leadActivitiesProvider(leadId));
    return Scaffold(
      appBar: AppBar(title: const Text('Lead')),
      body: leadAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (lead) {
          if (lead == null) return const Center(child: Text('Not found'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(lead: lead),
              const SizedBox(height: 16),
              _StatusActions(lead: lead),
              const SizedBox(height: 16),
              _Contact(lead: lead),
              const Divider(height: 32),
              Text('Activity',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _AddNoteRow(leadId: lead.id),
              const SizedBox(height: 8),
              actsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Error: $e'),
                data: (acts) => Column(
                  children: [for (final a in acts) _ActivityTile(a: a)],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(lead.displayName,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text(lead.status.label)),
                Chip(label: Text(lead.source.label)),
                if (lead.sport != null) Chip(label: Text(lead.sport!)),
              ],
            ),
            if (lead.notes != null) ...[
              const SizedBox(height: 8),
              Text(lead.notes!),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusActions extends ConsumerWidget {
  const _StatusActions({required this.lead});
  final Lead lead;

  Future<void> _setStatus(WidgetRef ref, LeadStatus s) async {
    final repo = await ref.read(leadsRepoProvider.future);
    await repo?.updateStatus(lead.id, s);
    ref.invalidate(leadByIdProvider(lead.id));
    ref.invalidate(leadActivitiesProvider(lead.id));
    ref.invalidate(leadsListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in LeadStatus.kanbanOrder)
          if (s != LeadStatus.converted)
            ChoiceChip(
              label: Text(s.label),
              selected: lead.status == s,
              onSelected: (sel) {
                if (sel) _setStatus(ref, s);
              },
            ),
        FilledButton.icon(
          icon: const Icon(Icons.person_add),
          label: const Text('Convert to student'),
          onPressed: lead.status == LeadStatus.converted
              ? null
              : () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => LeadConvertSheet(lead: lead),
                  );
                },
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: const Text('Schedule trial'),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate:
                  DateTime.now().add(const Duration(days: 1)),
              firstDate: DateTime.now(),
              lastDate:
                  DateTime.now().add(const Duration(days: 60)),
            );
            if (picked == null) return;
            final time = await showTimePicker(
              context: context,
              initialTime: const TimeOfDay(hour: 17, minute: 0),
            );
            if (time == null) return;
            final dt = DateTime(picked.year, picked.month, picked.day,
                time.hour, time.minute);
            final repo = await ref.read(leadsRepoProvider.future);
            await repo?.scheduleTrial(lead.id, dt);
            ref.invalidate(leadByIdProvider(lead.id));
            ref.invalidate(leadActivitiesProvider(lead.id));
            ref.invalidate(leadsListProvider);
          },
        ),
      ],
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lead.phone != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone),
                title: Text(lead.phone!),
              ),
            if (lead.email != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.email),
                title: Text(lead.email!),
              ),
            if (lead.parentName != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.family_restroom),
                title: Text(lead.parentName!),
              ),
            if (lead.trialScheduledAt != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available),
                title: Text(
                    'Trial scheduled for ${lead.trialScheduledAt!.toLocal()}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddNoteRow extends ConsumerStatefulWidget {
  const _AddNoteRow({required this.leadId});
  final String leadId;

  @override
  ConsumerState<_AddNoteRow> createState() => _AddNoteRowState();
}

class _AddNoteRowState extends ConsumerState<_AddNoteRow> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    final repo = await ref.read(leadsRepoProvider.future);
    await repo?.addNote(widget.leadId, text);
    _ctrl.clear();
    if (mounted) setState(() => _busy = false);
    ref.invalidate(leadActivitiesProvider(widget.leadId));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            decoration: const InputDecoration(
              hintText: 'Add a note',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _busy ? null : _add,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.a});
  final LeadActivity a;

  @override
  Widget build(BuildContext context) {
    final iconFor = <String, IconData>{
      'note': Icons.note_outlined,
      'status_change': Icons.swap_horiz,
      'call_logged': Icons.call,
      'email_sent': Icons.outgoing_mail,
      'sms_sent': Icons.sms,
      'trial_scheduled': Icons.event,
      'reminder_sent': Icons.alarm,
    };
    return ListTile(
      dense: true,
      leading: Icon(iconFor[a.kind] ?? Icons.event_note),
      title: Text(a.content ?? a.kind),
      subtitle: Text('${a.createdAt}'),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/leads/data/lead.dart';
import 'package:playhub/features/leads/data/lead_providers.dart';
import 'package:playhub/features/leads/presentation/lead_convert_sheet.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

final _dateFmt = DateFormat('dd MMM yyyy · HH:mm');

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
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(leadByIdProvider(leadId)),
        ),
        data: (lead) {
          if (lead == null) {
            return const AppEmptyState(
              icon: Icons.person_search_outlined,
              title: 'Lead not found',
              subtitle: 'It may have been converted or removed.',
            );
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              _Header(lead: lead),
              const SizedBox(height: AppSpacing.lg),
              _StatusActions(lead: lead),
              const SizedBox(height: AppSpacing.lg),
              _Contact(lead: lead),
              const SizedBox(height: AppSpacing.xl),
              const AppSectionHeader(title: 'Activity'),
              const SizedBox(height: AppSpacing.sm),
              _AddNoteRow(leadId: lead.id),
              const SizedBox(height: AppSpacing.sm),
              actsAsync.when(
                loading: () => const AppSkeletonList(count: 3),
                error: (e, _) => Text(
                  friendlyError(e),
                  style: TextStyle(color: AppSemanticColors.of(context).danger),
                ),
                data: (acts) {
                  if (acts.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Text(
                        'No activity yet.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    );
                  }
                  return Column(
                    children: [for (final a in acts) _ActivityTile(a: a)],
                  );
                },
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lead.displayName,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Consumer(builder: (_, ref, __) {
            final sportLabel = ref.watch(sportDisplayProvider((
              sportId: lead.sportId,
            )));
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                AppBadge(text: lead.status.label, tone: AppBadgeTone.info),
                AppBadge(text: lead.source.label),
                if (sportLabel != '—') AppBadge(text: sportLabel),
              ],
            );
          }),
          if (lead.notes != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              lead.notes!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
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
    ref
      ..invalidate(leadByIdProvider(lead.id))
      ..invalidate(leadActivitiesProvider(lead.id))
      ..invalidate(leadsListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
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
            if (picked == null || !context.mounted) return;
            final time = await showTimePicker(
              context: context,
              initialTime: const TimeOfDay(hour: 17, minute: 0),
            );
            if (time == null) return;
            final dt = DateTime(picked.year, picked.month, picked.day,
                time.hour, time.minute);
            final repo = await ref.read(leadsRepoProvider.future);
            await repo?.scheduleTrial(lead.id, dt);
            ref
              ..invalidate(leadByIdProvider(lead.id))
              ..invalidate(leadActivitiesProvider(lead.id))
              ..invalidate(leadsListProvider);
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lead.phone != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone_outlined),
              title: Text(lead.phone!),
            ),
          if (lead.email != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.email_outlined),
              title: Text(lead.email!),
            ),
          if (lead.parentName != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.family_restroom_outlined),
              title: Text(lead.parentName!),
            ),
          if (lead.trialScheduledAt != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_outlined),
              title: Text(
                'Trial scheduled for '
                '${_dateFmt.format(lead.trialScheduledAt!.toLocal())}',
              ),
            ),
        ],
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppFormField(
            controller: _ctrl,
            hint: 'Add a note',
            textInputAction: TextInputAction.send,
            onFieldSubmitted: (_) => _busy ? null : _add(),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
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
      contentPadding: EdgeInsets.zero,
      leading: Icon(iconFor[a.kind] ?? Icons.event_note),
      title: Text(a.content ?? a.kind),
      subtitle: Text(_dateFmt.format(a.createdAt.toLocal())),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/features/leads/data/lead.dart';
import 'package:playhub/features/leads/data/lead_providers.dart';
import 'package:playhub/features/leads/presentation/lead_form_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/core/error_messages.dart';

/// Six-column kanban scrolling horizontally. Tap a card → detail page.
class LeadsKanbanPage extends ConsumerWidget {
  const LeadsKanbanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leadsListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leads'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(leadsListProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New lead'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const LeadFormPage()),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (leads) => _Board(leads: leads),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.leads});
  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    final byStatus = <LeadStatus, List<Lead>>{
      for (final s in LeadStatus.kanbanOrder) s: <Lead>[],
    };
    for (final l in leads) {
      // Skip leads whose status isn't part of the kanban view (e.g. a new
      // enum value added on the DB side that the app doesn't render yet).
      final column = byStatus[l.status];
      if (column == null) continue;
      column.add(l);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in LeadStatus.kanbanOrder)
            _Column(status: s, leads: byStatus[s] ?? const []),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.status, required this.leads});
  final LeadStatus status;
  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(status: status, count: leads.length),
          const SizedBox(height: 8),
          for (final l in leads) _Card(lead: l),
          if (leads.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('—', textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.status, required this.count});
  final LeadStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(status.label,
              style: Theme.of(context).textTheme.titleSmall),
          Chip(
              label: Text('$count'),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ],
      ),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(top: 6),
      child: InkWell(
        onTap: () => context.push('/leads/${lead.id}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lead.displayName,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis),
              Builder(builder: (_) {
                final sportLabel = ref.watch(sportDisplayProvider((
                  sportId: lead.sportId,
                )));
                if (sportLabel == '—') return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sportLabel,
                      style: Theme.of(context).textTheme.bodySmall),
                );
              }),
              if (lead.phone != null || lead.email != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    lead.phone ?? lead.email ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.flag_outlined,
                      size: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(lead.source.label,
                      style: Theme.of(context).textTheme.labelSmall),
                  const Spacer(),
                  if (lead.nextFollowupAt != null)
                    _FollowupChip(when: lead.nextFollowupAt!),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowupChip extends StatelessWidget {
  const _FollowupChip({required this.when});
  final DateTime when;

  @override
  Widget build(BuildContext context) {
    final overdue = when.isBefore(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: overdue
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${when.day}/${when.month}',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:playhub/features/events/data/event_providers.dart';
import 'package:playhub/features/events/presentation/event_detail_page.dart';
import 'package:playhub/features/events/presentation/event_form_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';

/// Events list with status-based filtering. Tap a card → detail page.
class EventsPage extends ConsumerStatefulWidget {
  const EventsPage({super.key});

  @override
  ConsumerState<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends ConsumerState<EventsPage> {
  EventStatus? _filter;
  String? _sportFilter;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(eventsListProvider);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final canCreate = profile != null &&
        const ['academy_owner', 'academy_admin', 'center_admin', 'head_coach']
            .contains(profile.role);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(eventsListProvider),
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New event'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EventFormPage(),
                ),
              ),
            )
          : null,
      body: Column(
        children: [
          _FilterBar(
            selected: _filter,
            onChanged: (v) => setState(() => _filter = v),
          ),
          SportFilterChipBar(
            selectedId: _sportFilter,
            onSelected: (id) => setState(() => _sportFilter = id),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (events) {
                final list = events.where((e) {
                  if (_filter != null && e.status != _filter) return false;
                  if (_sportFilter != null && e.sportId != _sportFilter) {
                    return false;
                  }
                  return true;
                }).toList();
                if (list.isEmpty) {
                  return const Center(child: Text('No events'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) => _EventCard(event: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onChanged});
  final EventStatus? selected;
  final ValueChanged<EventStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => onChanged(null),
            ),
          ),
          for (final s in EventStatus.values)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
              child: ChoiceChip(
                label: Text(s.label),
                selected: selected == s,
                onSelected: (_) => onChanged(s),
              ),
            ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final EventEntry event;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, dd MMM yyyy · h:mma');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: CircleAvatar(child: Icon(_iconFor(event.kind))),
        title: Text(event.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${event.kind.label} · ${df.format(event.startsAt)}'),
            if (event.location != null && event.location!.isNotEmpty)
              Text(event.location!),
          ],
        ),
        trailing: _StatusChip(status: event.status),
        isThreeLine: event.location != null && event.location!.isNotEmpty,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EventDetailPage(eventId: event.id),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(EventKind k) {
    switch (k) {
      case EventKind.tournament:
        return Icons.emoji_events_outlined;
      case EventKind.workshop:
        return Icons.school_outlined;
      case EventKind.camp:
        return Icons.terrain_outlined;
      case EventKind.fixture:
        return Icons.sports_outlined;
      case EventKind.social:
        return Icons.celebration_outlined;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final EventStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      EventStatus.draft => Colors.grey,
      EventStatus.published => Colors.blue,
      EventStatus.registrationClosed => Colors.orange,
      EventStatus.inProgress => Colors.green,
      EventStatus.completed => Colors.purple,
      EventStatus.cancelled => Colors.red,
    };
    return Chip(
      label: Text(status.label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

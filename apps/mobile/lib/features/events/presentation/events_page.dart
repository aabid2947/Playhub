import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:playhub/features/events/data/event_providers.dart';
import 'package:playhub/features/events/presentation/event_detail_page.dart';
import 'package:playhub/features/events/presentation/event_form_page.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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
    final canCreate =
        profile != null &&
        const [
          'academy_owner',
          'academy_admin',
          'center_admin',
          'head_coach',
        ].contains(profile.role);

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
                MaterialPageRoute<void>(builder: (_) => const EventFormPage()),
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
              loading: () => const AppLoading(),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(eventsListProvider),
              ),
              data: (events) {
                final list = events.where((e) {
                  if (_filter != null && e.status != _filter) return false;
                  if (_sportFilter != null && e.sportId != _sportFilter) {
                    return false;
                  }
                  return true;
                }).toList();
                if (list.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.event_outlined,
                    title: 'No events',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.xs),
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
    final subtitleLines = <String>[
      '${event.kind.label} · ${df.format(event.startsAt)}',
      if (event.location != null && event.location!.isNotEmpty) event.location!,
    ];
    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailPage(eventId: event.id),
        ),
      ),
      child: AppListTile(
        leading: Icon(_iconFor(event.kind)),
        title: Text(event.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final line in subtitleLines) Text(line)],
        ),
        trailing: _StatusChip(status: event.status),
        isThreeLine: event.location != null && event.location!.isNotEmpty,
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
    final tone = switch (status) {
      EventStatus.draft => AppBadgeTone.neutral,
      EventStatus.published => AppBadgeTone.info,
      EventStatus.registrationClosed => AppBadgeTone.warning,
      EventStatus.inProgress => AppBadgeTone.success,
      EventStatus.completed => AppBadgeTone.brand,
      EventStatus.cancelled => AppBadgeTone.danger,
    };
    return AppBadge(text: status.label, tone: tone);
  }
}

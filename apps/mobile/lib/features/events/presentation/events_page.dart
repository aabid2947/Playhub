import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:playhub/features/events/data/event_providers.dart';
import 'package:playhub/features/events/presentation/event_detail_page.dart';
import 'package:playhub/features/events/presentation/event_form_page.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Events list with a single unified filter block (status + sport) above a
/// consistent set of event cards. Tap a card → detail page.
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
            tooltip: 'Refresh',
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
            status: _filter,
            sportId: _sportFilter,
            onStatusChanged: (v) => setState(() => _filter = v),
            onSportChanged: (id) => setState(() => _sportFilter = id),
          ),
          Expanded(
            child: async.when(
              loading: () => const AppSkeletonList(),
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
                    subtitle: 'Events matching these filters will show here.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(eventsListProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      AppSpacing.xs,
                      AppSpacing.sm,
                      AppSpacing.sm,
                    ),
                    itemCount: list.length + 1,
                    separatorBuilder: (_, i) => i == 0
                        ? const SizedBox.shrink()
                        : const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (_, i) {
                      if (i == 0) return _ResultCount(count: list.length);
                      return _EventCard(event: list[i - 1]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One coherent filter surface: the status chip row sits directly above the
/// sport chip bar in the same [Material], so the two never read as orphaned
/// controls.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.status,
    required this.sportId,
    required this.onStatusChanged,
    required this.onSportChanged,
  });

  final EventStatus? status;
  final String? sportId;
  final ValueChanged<EventStatus?> onStatusChanged;
  final ValueChanged<String?> onSportChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.sm,
                  ),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: status == null,
                    onSelected: (_) => onStatusChanged(null),
                  ),
                ),
                for (final s in EventStatus.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.sm,
                    ),
                    child: ChoiceChip(
                      label: Text(s.label),
                      selected: status == s,
                      onSelected: (_) => onStatusChanged(s),
                    ),
                  ),
              ],
            ),
          ),
          SportFilterChipBar(
            selectedId: sportId,
            onSelected: onSportChanged,
          ),
        ],
      ),
    );
  }
}

/// Visible result count above the list, e.g. "12 events".
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        count == 1 ? '1 event' : '$count events',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Consistent, fixed-height event card: kind icon → title → one tight
/// kind · date (· location) line → status [AppBadge]. The subtitle is a
/// single ellipsised line so the card height never varies with location.
class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final EventEntry event;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, dd MMM · h:mma');
    final hasLocation =
        event.location != null && event.location!.isNotEmpty;
    final subtitle = [
      '${event.kind.label} · ${df.format(event.startsAt)}',
      if (hasLocation) event.location!,
    ].join('  •  ');

    return AppCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailPage(eventId: event.id),
        ),
      ),
      child: AppListTile(
        leading: Icon(_iconFor(event.kind)),
        title: Text(
          event.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _StatusChip(status: event.status),
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

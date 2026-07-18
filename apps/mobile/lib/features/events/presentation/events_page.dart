import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/events/data/event.dart';
import 'package:playhub/features/events/data/event_providers.dart';
import 'package:playhub/features/events/presentation/event_detail_page.dart';
import 'package:playhub/features/events/presentation/event_form_page.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Events list — v1 "Sports-Light", archetype B (list).
///
/// One coherent in-body filter surface (status chips + sport chip bar) sits
/// above a column of fixed-height, kind-iconed event [AppCard]s. Tap a card →
/// detail page. The create FAB is gated on [Capabilities.manageEvents] (RLS is
/// the real gate; this just hides the entry point for roles that can't create).
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
    final canCreate = ref.watch(capabilitiesProvider).manageEvents;

    return Scaffold(
      // Pushed/standalone page — keeps its own AppBar (not a shell body tab).
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
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      // Leave room so the last tile clears the FAB.
                      AppSpacing.xxl + AppSpacing.xl,
                    ),
                    itemCount: list.length + 1,
                    separatorBuilder: (_, i) => i == 0
                        ? const SizedBox.shrink()
                        : const SizedBox(height: AppSpacing.sm),
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
/// controls. The status set has 7 options (All + 6 [EventStatus]), so it stays
/// a horizontally scrolling chip row styled to match the sport bar rather than
/// an equal-width [AppPillTabs] (which would be unusable that cramped).
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
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              children: [
                _StatusChoice(
                  label: 'All',
                  selected: status == null,
                  onTap: () => onStatusChanged(null),
                ),
                for (final s in EventStatus.values)
                  _StatusChoice(
                    label: s.label,
                    selected: status == s,
                    onTap: () => onStatusChanged(s),
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

/// A single status filter pill, brand-colored when selected. Stays a real
/// [ChoiceChip] so widget-type finders keep resolving.
class _StatusChoice extends StatelessWidget {
  const _StatusChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        backgroundColor: scheme.primary.withValues(alpha: 0.10),
        selectedColor: scheme.primary,
        side: BorderSide(
          color: selected
              ? scheme.primary
              : scheme.primary.withValues(alpha: 0.20),
        ),
        labelStyle: TextStyle(
          color: selected ? Colors.white : scheme.primary,
          fontWeight: AppType.bold,
          fontSize: 13,
        ),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        count == 1 ? '1 event' : '$count events',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Consistent, fixed-height event card: a kind-colored icon tile → title → one
/// tight kind · date (· location) line → status [AppBadge]. The subtitle is a
/// single ellipsised line so the card height never varies with location.
class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final EventEntry event;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, dd MMM · h:mma');
    final hasLocation = event.location != null && event.location!.isNotEmpty;
    final subtitle = [
      '${event.kind.label} · ${df.format(event.startsAt)}',
      if (hasLocation) event.location!,
    ].join('  •  ');
    final tint = _tintFor(event.kind);

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventDetailPage(eventId: event.id),
        ),
      ),
      child: AppListTile(
        wrapLeading: false,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(_iconFor(event.kind), color: tint, size: 20),
        ),
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
        trailing: _StatusBadge(status: event.status),
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

  /// A stable per-kind accent drawn from the shared category swatch, so each
  /// event type reads with a consistent colored icon tile.
  Color _tintFor(EventKind k) {
    switch (k) {
      case EventKind.tournament:
        return AppPalette.categorySwatch[3];
      case EventKind.workshop:
        return AppPalette.accent;
      case EventKind.camp:
        return AppPalette.categorySwatch[5];
      case EventKind.fixture:
        return AppPalette.brandPrimary;
      case EventKind.social:
        return AppPalette.categorySwatch[1];
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
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

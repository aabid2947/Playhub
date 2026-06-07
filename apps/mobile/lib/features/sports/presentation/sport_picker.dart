import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/sports/data/sport.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';

/// Looks up the right list of sports for a picker:
///   - centerId given → that center's enabled sports
///   - centerId null  → union of every center in the academy
List<CenterSport> _resolveSports(WidgetRef ref, String? centerId) {
  if (centerId != null) {
    return ref.watch(centerSportsProvider(centerId)).valueOrNull ?? const [];
  }
  return ref.watch(academyCenterSportsProvider).valueOrNull ?? const [];
}

/// The single "no sports configured" message used by every picker. Scopes
/// the wording to whether we're looking at a specific center or the academy
/// union so the user knows exactly where to go fix it.
String _emptyHint(String? centerId) => centerId == null
    ? 'No sports configured yet — add them in Settings → Sports'
    : 'This center has no sports yet — add them in Settings → Sports';

/// One shared inline fallback for all three pickers when no sports exist.
///
/// Lives inline (not the centered [AppEmptyState], which is for full-page
/// surfaces): a muted hint with a leading icon, optionally wrapped in a
/// field-style border + label so it reads as a disabled input within a form.
class _SportPickerEmpty extends StatelessWidget {
  const _SportPickerEmpty({
    required this.centerId,
    this.label,
    this.framed = false,
  });

  /// Center scope, only used to pick the wording.
  final String? centerId;

  /// When set, shown above the hint as a section/field label.
  final String? label;

  /// When true, renders inside an [InputDecorator] so the empty single-select
  /// picker still looks like the form field it replaces.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final hint = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.sports_outlined,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            _emptyHint(centerId),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );

    if (framed) {
      return InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: hint,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
        ],
        hint,
      ],
    );
  }
}

/// Returns a copy of [sports] de-duplicated by sport_id (a sport offered
/// at multiple centers should appear once in the picker / chip bar). The
/// first-seen `displayName` wins for ties on custom_name.
List<CenterSport> _dedup(List<CenterSport> sports) {
  final seen = <String, CenterSport>{};
  for (final s in sports) {
    seen.putIfAbsent(s.sport.id, () => s);
  }
  final list = seen.values.toList()
    ..sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  return list;
}

/// Single-select sport picker.
///
/// When [centerId] is given, the picker shows only that center's enabled
/// sports. When null, it shows the union across the whole academy. Hides
/// (or shows a hint) when the relevant scope has no sports.
class SportPicker extends ConsumerWidget {
  const SportPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Sport',
    this.centerId,
    this.restrictToSportIds,
  });

  /// Current `sport_id`. Pass null when nothing is selected.
  final String? value;

  /// Called with the selected `sport_id`, or null when the user picks
  /// "— select —" to clear.
  final ValueChanged<String?> onChanged;

  final String label;

  /// Optional center to scope the picker to. When null, the picker shows
  /// the union of every center's sports in the academy.
  final String? centerId;

  /// When non-null, the picker only offers sports whose id is in this set —
  /// used so a head_coach can only tag a batch with a sport they own (RLS
  /// rejects the rest). An empty set therefore shows the "no sports" hint.
  final Set<String>? restrictToSportIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var sports = _dedup(_resolveSports(ref, centerId));
    final restrict = restrictToSportIds;
    if (restrict != null) {
      sports = sports.where((s) => restrict.contains(s.sport.id)).toList();
    }
    if (sports.isEmpty) {
      return _SportPickerEmpty(centerId: centerId, label: label, framed: true);
    }
    return DropdownButtonFormField<String?>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String?>(child: Text('— select —')),
        for (final s in sports)
          DropdownMenuItem<String?>(
            value: s.sport.id,
            child: Text(s.displayName),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Single-select chip bar — used on list pages as a sport filter.
/// Renders an "All" chip first, then one chip per enabled sport. Hides
/// itself when the academy hasn't configured any sports.
class SportFilterChipBar extends ConsumerWidget {
  const SportFilterChipBar({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.centerId,
  });

  final String? selectedId;

  /// Called with the selected sport_id, or null when the user picks "All".
  final ValueChanged<String?> onSelected;

  /// Optional center to scope the chip bar to.
  final String? centerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sports = _dedup(_resolveSports(ref, centerId));
    // A filter chip bar with nothing to filter is pure noise, so it stays
    // collapsed rather than showing the shared `_SportPickerEmpty` hint —
    // the empty wording belongs on the (visible) form pickers, not on a
    // filter that would otherwise occupy a list page's header. The other two
    // pickers surface `_emptyHint(centerId)` for the same root condition.
    if (sports.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
            child: ChoiceChip(
              label: const Text('All'),
              selected: selectedId == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final s in sports)
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
              child: ChoiceChip(
                label: Text(s.displayName),
                selected: selectedId == s.sport.id,
                onSelected: (_) => onSelected(s.sport.id),
              ),
            ),
        ],
      ),
    );
  }
}

/// Multi-select picker rendered as filter chips. Used on the coach form
/// (which sports does this coach teach). Always sourced from the academy-
/// wide union — coaches can be qualified for sports across centers.
class SportMultiSelect extends ConsumerWidget {
  const SportMultiSelect({
    super.key,
    required this.selectedIds,
    required this.onToggle,
    this.label,
  });

  final Set<String> selectedIds;
  final void Function(String sportId, bool selected) onToggle;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sports =
        _dedup(ref.watch(academyCenterSportsProvider).valueOrNull ?? const []);
    if (sports.isEmpty) {
      // Always academy-wide here, so pass a null center scope for the wording.
      return _SportPickerEmpty(centerId: null, label: label);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(label!,
                style: Theme.of(context).textTheme.titleSmall),
          ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final s in sports)
              FilterChip(
                label: Text(s.displayName),
                selected: selectedIds.contains(s.sport.id),
                onSelected: (sel) => onToggle(s.sport.id, sel),
              ),
          ],
        ),
      ],
    );
  }
}

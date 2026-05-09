import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';

/// Single-select sport picker driven by the academy's enabled sports list.
///
/// If the academy hasn't enabled any sports yet, falls back to a disabled
/// row that points the user at Settings → Sports.
class SportPicker extends ConsumerWidget {
  const SportPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Sport',
  });

  /// Current `sport_id`. Pass null when nothing is selected.
  final String? value;

  /// Called with the selected `sport_id`, or null when the user picks
  /// "— select —" to clear.
  final ValueChanged<String?> onChanged;

  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(academySportsProvider);
    return async.when(
      loading: () => InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: const LinearProgressIndicator(minHeight: 2),
      ),
      error: (e, _) => InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text('Error: $e'),
      ),
      data: (sports) {
        if (sports.isEmpty) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              helperText: 'Add sports under Settings → Sports',
            ),
            child: const Text('— no sports configured —'),
          );
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
      },
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
  });

  final String? selectedId;

  /// Called with the selected sport_id, or null when the user picks "All".
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(academySportsProvider);
    final sports = async.valueOrNull ?? const [];
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
/// (which sports does this coach teach) and as the filter bar on list pages.
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
    final async = ref.watch(academySportsProvider);
    return async.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (e, _) => Text('Error: $e'),
      data: (sports) {
        if (sports.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(label!,
                    style: Theme.of(context).textTheme.titleSmall),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
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
      },
    );
  }
}

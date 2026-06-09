import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// A segmented pill selector — the v1 in-body filter (invoice status, event
/// kind, …). The selected segment lifts to a white pill on the inset track,
/// its label in the brand orange.
///
/// For a *sport* filter use the sport-colored chip bar (`SportFilterChipBar`)
/// instead; this is for short, fixed status/category sets.
class AppPillTabs extends StatelessWidget {
  const AppPillTabs({
    required this.tabs,
    required this.index,
    required this.onChanged,
    super.key,
  });

  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final selected = i == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: AppDuration.fast,
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? scheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: selected ? AppShadows.card : null,
                ),
                child: Text(
                  tabs[i],
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 13,
                    fontWeight: AppType.bold,
                    letterSpacing: 0,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

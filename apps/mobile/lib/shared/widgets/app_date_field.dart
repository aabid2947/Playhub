import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// Labeled, tappable date field that mirrors `AppFormField`'s label-above
/// style, so a form mixing text inputs, selects, and dates reads consistently.
///
/// The caller owns the [value] and the picker — this just renders the field
/// and fires [onTap]. Renders a real [InputDecorator] so it inherits the
/// input theme's filled box.
class AppDateField extends StatelessWidget {
  const AppDateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = 'Tap to pick',
    super.key,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: AppType.semibold,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InputDecorator(
            decoration: const InputDecoration(),
            child: Text(
              v == null ? placeholder : v.toIso8601String().substring(0, 10),
            ),
          ),
        ),
      ],
    );
  }
}

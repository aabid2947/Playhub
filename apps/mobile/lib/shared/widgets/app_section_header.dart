import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// Small uppercase section heading with an optional trailing action.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.title,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: AppType.bold,
                letterSpacing: AppType.trackingWider,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

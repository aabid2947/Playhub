import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// Thin wrapper over [ListTile] with consistent padding, a tinted leading
/// icon container, and an automatic chevron when [onTap] is provided.
///
/// Set [wrapLeading] to `false` when [leading] is already a self-contained
/// visual (e.g. an avatar / `CircleAvatar`) that shouldn't sit inside the
/// tinted icon box.
///
/// Renders an actual [ListTile] so `find.byType(ListTile)` still works.
class AppListTile extends StatelessWidget {
  const AppListTile({
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isThreeLine = false,
    this.wrapLeading = true,
    super.key,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isThreeLine;
  final bool wrapLeading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget? wrappedLeading;
    if (leading != null) {
      wrappedLeading = wrapLeading
          ? Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child: IconTheme(
                data:
                    IconThemeData(color: scheme.onPrimaryContainer, size: 20),
                child: leading!,
              ),
            )
          : leading;
    }

    Widget? wrappedTitle;
    if (title != null) {
      wrappedTitle = DefaultTextStyle.merge(
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        child: title!,
      );
    }

    final resolvedTrailing = trailing ??
        (onTap != null
            ? Icon(
                Icons.chevron_right,
                color: scheme.onSurfaceVariant,
              )
            : null);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      leading: wrappedLeading,
      title: wrappedTitle,
      subtitle: subtitle,
      trailing: resolvedTrailing,
      onTap: onTap,
      isThreeLine: isThreeLine,
    );
  }
}

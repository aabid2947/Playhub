import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// Outlined, low-chrome card. Thin wrapper over Material [Card] so that
/// `find.byType(Card)` still resolves in widget tests.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedPadding =
        padding ?? const EdgeInsets.all(AppSpacing.lg);

    Widget content = Padding(
      padding: resolvedPadding,
      child: child,
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: content,
      );
    }

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Card(
        elevation: AppElevation.none,
        margin: EdgeInsets.zero,
        color: color ?? scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}

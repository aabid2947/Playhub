import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// The base surface for everything — a white card with a hairline border and a
/// soft v1 shadow ([AppShadows.card]). Thin wrapper over Material [Card] so that
/// `find.byType(Card)` still resolves in widget tests.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.color,
    this.shadow,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;

  /// Whether to cast the soft lift shadow. Defaults to the v1 look (a gentle
  /// shadow). Set `false` for cards that sit on a colored hero, inside another
  /// card, or anywhere a flat outline reads better.
  final bool? shadow;

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

    Widget card = Card(
      elevation: AppElevation.none,
      margin: EdgeInsets.zero,
      color: color ?? scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    if (shadow ?? true) {
      card = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.card,
        ),
        child: card,
      );
    }

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: card,
    );
  }
}

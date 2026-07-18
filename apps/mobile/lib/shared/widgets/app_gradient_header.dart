import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// The v1 hero band — a gradient header that anchors the top of dashboards,
/// detail pages, and finance/profile landings. Content is white-on-gradient.
///
/// Defaults to the orange [AppPalette.brandGradient]; pass
/// `colors: AppPalette.navyGradient` for finance/profile/"more" surfaces, or a
/// sport-derived pair for an entity detail hero.
///
/// Pair with [AppHeroStatRow] (a translucent summary card) and let the body
/// overlap upward with `Transform.translate(offset: Offset(0, -AppSpacing.lg))`.
class AppGradientHeader extends StatelessWidget {
  const AppGradientHeader({
    required this.child,
    this.colors = AppPalette.brandGradient,
    this.height,
    this.padding,
    super.key,
  });

  final Widget child;
  final List<Color> colors;
  final double? height;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      height: height,
      padding: padding ??
          EdgeInsets.fromLTRB(
            AppSpacing.lg,
            topInset + AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl + AppSpacing.md,
          ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.xxl),
        ),
      ),
      child: child,
    );
  }
}

/// A translucent summary strip placed inside an [AppGradientHeader] — 2–3
/// headline metrics separated by hairline dividers (revenue · attendance ·
/// sessions). White text on the gradient.
class AppHeroStatRow extends StatelessWidget {
  const AppHeroStatRow({required this.stats, super.key});

  /// Each entry is a (value, label) pair, e.g. `('₹3.1L', 'Revenue · Jun')`.
  final List<(String value, String label)> stats;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < stats.length; i++) {
      children.add(Expanded(child: _stat(context, stats[i])));
      if (i != stats.length - 1) children.add(_divider());
    }
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(children: children),
    );
  }

  Widget _stat(BuildContext context, (String, String) s) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          s.$1,
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: AppType.heavy,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          s.$2,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: AppType.semibold,
          ),
        ),
      ],
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 34,
        color: Colors.white.withValues(alpha: 0.22),
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      );
}

/// A frosted pill chip for use on a gradient hero (status / batch / sport tags).
class AppGlassChip extends StatelessWidget {
  const AppGlassChip(this.label, {this.icon, super.key});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: AppType.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// A circular translucent icon button for a gradient hero (back, edit, more,
/// notifications). Shows an optional unread dot.
class AppCircleIconButton extends StatelessWidget {
  const AppCircleIconButton({
    required this.icon,
    this.onTap,
    this.badge = false,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool badge;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Stack(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        if (badge)
          Positioned(
            right: 9,
            top: 9,
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: Color(0xFFFFE08A),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
    final wrapped = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: button),
    );
    final tip = tooltip;
    if (tip != null) return Tooltip(message: tip, child: wrapped);
    return wrapped;
  }
}

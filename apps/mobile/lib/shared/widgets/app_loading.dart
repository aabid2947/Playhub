import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// Centered circular progress with optional caption.
class AppLoading extends StatelessWidget {
  const AppLoading({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              label!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A shimmering placeholder box used while content is loading. A highlight
/// band sweeps left-to-right across a neutral base every 1.4s.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    this.width,
    this.height = 16,
    this.radius = AppRadius.sm,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    final isDark = theme.brightness == Brightness.dark;
    // A highlight lighter than the base — subtle in dark, brighter in light.
    final highlight = Color.alphaBlend(
      Colors.white.withValues(alpha: isDark ? 0.10 : 0.55),
      base,
    );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlidingGradient(_controller.value * 2 - 1),
            ),
          ),
        );
      },
    );
  }
}

/// Translates a gradient horizontally by a fraction of the bounds width.
class _SlidingGradient extends GradientTransform {
  const _SlidingGradient(this.slidePercent);

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
  }
}

/// Vertical list of skeleton rows — convenience for list-style screens.
class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({
    this.count = 6,
    this.rowHeight = 72,
    this.spacing = AppSpacing.md,
    super.key,
  });

  final int count;
  final double rowHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < count; i++) ...[
            AppSkeleton(height: rowHeight, radius: AppRadius.md),
            if (i < count - 1) SizedBox(height: spacing),
          ],
        ],
      ),
    );
  }
}

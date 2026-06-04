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

/// A shimmering placeholder box used while content is loading. Animates
/// opacity between 0.5 and 1.0 over 1.2s.
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
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.5, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
          ),
        );
      },
    );
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

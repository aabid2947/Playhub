import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/shared/widgets/app_card.dart';

/// A colorful quick-action tile — the v1 "feature card". A gradient-filled icon
/// chip, a title, a one-line subtitle, and an optional count [badge]. Built on
/// [AppCard], so it inherits the soft shadow + tap ripple.
///
/// Used in dashboard "Quick actions" grids and settings "Manage" grids. **Gate
/// it** with `caps.*` exactly like any other entry point — a pretty tile is
/// still an action.
class AppFeatureCard extends StatelessWidget {
  const AppFeatureCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    this.onTap,
    this.badge,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final VoidCallback? onTap;

  /// Optional short count/label (e.g. "4" pending) shown top-right.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [tint.withValues(alpha: 0.95), tint],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 23),
              ),
              const Spacer(),
              if (badge != null) _MiniBadge(text: badge!, color: tint),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: AppType.heavy,
          color: color,
        ),
      ),
    );
  }
}

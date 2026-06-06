import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// The two-tone "PlayHub" wordmark — `Play` in the on-surface ink, `Hub` in the
/// brand violet. Single source of truth for the wordmark across the auth header
/// and the primary app-bar branding.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({this.style, super.key});

  /// Base text style for both spans; defaults to `titleLarge`.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = (style ?? theme.textTheme.titleLarge)?.copyWith(
      fontWeight: AppType.bold,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'Play',
            style: base?.copyWith(color: theme.colorScheme.onSurface),
          ),
          TextSpan(
            text: 'Hub',
            style: base?.copyWith(color: theme.colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

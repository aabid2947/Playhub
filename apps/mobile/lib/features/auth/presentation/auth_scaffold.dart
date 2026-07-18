import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/shared/widgets/brand_wordmark.dart';

/// Auth content never grows wider than this — keeps forms readable on tablet
/// and web while staying full-bleed on a phone.
const double _maxContentWidth = 440;

/// Shared shell for the auth screens (login / signup / forgot password).
///
/// Centers a max-width column that stays keyboard-safe (scrolls when the
/// keyboard shrinks the viewport), renders the [BrandMark], a [title] +
/// [subtitle], then the page's own [children] (fields, buttons, links).
/// Pass [onBack] to pin a back button top-left.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
    this.onBack,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: AppSpacing.xl,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _maxContentWidth,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const BrandMark(),
                              const SizedBox(height: AppSpacing.xxl),
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineMedium,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxl),
                              ...children,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (onBack != null)
              Positioned(
                top: AppSpacing.xs,
                left: AppSpacing.xs,
                child: IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Brand lockup for the auth screens — a gradient monogram tile + the PlayHub
/// wordmark. Sport-agnostic so it fits a multi-sport academy product.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  /// Fixed brand-mark tile size — a lockup dimension, not a spacing/layout
  /// value, so it lives here rather than in the spacing scale.
  static const double _tileSize = 64;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _tileSize,
          height: _tileSize,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: AppPalette.brandGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            // A soft orange glow lifts the monogram off the calm auth canvas
            // without resorting to a hero band.
            boxShadow: AppShadows.raised,
          ),
          alignment: Alignment.center,
          // White is the gradient's "on" color and reads correctly in both
          // brightnesses — this is a brand surface, not a theme surface.
          child: const Text(
            'P',
            style: TextStyle(
              color: Colors.white,
              fontSize: AppFontSize.display,
              fontWeight: AppType.bold,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const BrandWordmark(),
      ],
    );
  }
}

/// Inline status banner for auth screens — a soft danger/success tint with an
/// icon. Replaces ad-hoc `Colors.red`/`Colors.green` message text.
class AuthMessage extends StatelessWidget {
  const AuthMessage({
    required this.message,
    required this.isError,
    super.key,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantics = AppSemanticColors.of(context);
    final fg = isError ? semantics.danger : semantics.success;
    final bg = isError ? semantics.dangerContainer : semantics.successContainer;
    final icon = isError ? Icons.error_outline : Icons.check_circle_outline;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/presentation/auth_scaffold.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    unawaited(_decide());
  }

  Future<void> _decide() async {
    // Give Supabase a tick to restore the session from secure storage.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    context.go(session == null ? '/login' : '/home');
  }

  /// Fixed splash-progress dimension — a brand-lockup size, not a spacing-scale
  /// value, so it lives here rather than in [AppSpacing].
  static const double _progressSize = 24;

  /// Diameter of the faint brand halo behind the lockup — a fixed decorative
  /// dimension keyed to the brand mark, not a layout spacing value.
  static const double _haloSize = 220;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A faint orange halo lifts the centered lockup off the calm
            // surface — a single soft brand touch, no hero band.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    AppPalette.brandPrimary.withValues(alpha: 0.10),
                    AppPalette.brandPrimary.withValues(alpha: 0),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const SizedBox(
                width: _haloSize,
                height: _haloSize,
                child: Center(child: BrandMark()),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: _progressSize,
              height: _progressSize,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';

/// Circular avatar for the **signed-in user** — their profile photo, or their
/// initials on a tinted disc as a fallback. Reads [currentProfileProvider]
/// itself, so it can be dropped into any header (greeting cards, app bars)
/// without threading the profile through.
class AppUserAvatar extends ConsumerWidget {
  const AppUserAvatar({this.size = 40, this.onGradient = false, super.key});

  /// Diameter in logical pixels.
  final double size;

  /// Set when placed on the brand gradient (white foreground): draws a
  /// translucent white ring and a light fallback disc so it reads cleanly.
  final bool onGradient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final url =
        ref.watch(storageServiceProvider).publicAvatarUrl(profile?.profilePhoto);

    final bg =
        onGradient ? Colors.white.withValues(alpha: 0.22) : scheme.primaryContainer;
    final fg = onGradient ? Colors.white : scheme.onPrimaryContainer;

    Widget fallback() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          color: bg,
          child: Text(
            _initials(profile),
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w600,
              fontSize: size * 0.4,
            ),
          ),
        );

    final inner = url == null
        ? fallback()
        : CachedNetworkImage(
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, __) => fallback(),
            errorWidget: (_, __, ___) => fallback(),
          );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: onGradient
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.6),
                width: 1.5,
              )
            : null,
      ),
      child: ClipOval(child: inner),
    );
  }

  String _initials(Profile? p) {
    if (p == null) return '?';
    final f = (p.firstName ?? '').trim();
    final l = (p.lastName ?? '').trim();
    final init =
        ((f.isNotEmpty ? f[0] : '') + (l.isNotEmpty ? l[0] : '')).toUpperCase();
    if (init.isNotEmpty) return init;
    final e = (p.email ?? '').trim();
    return e.isNotEmpty ? e[0].toUpperCase() : '?';
  }
}

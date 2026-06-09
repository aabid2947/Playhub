import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/shared/widgets/ui_helpers.dart';

/// Gradient-initials avatar for an **arbitrary named entity** (student, coach,
/// lead, roster row) — no network photo. The disc color is deterministic from
/// the name via [colorFromName], so the same person is always the same color.
///
/// For the **signed-in user's** photo+initials avatar, use `AppUserAvatar`.
class AppAvatar extends StatelessWidget {
  const AppAvatar(
    this.name, {
    this.size = 44,
    this.color,
    super.key,
  });

  final String name;
  final double size;

  /// Override the deterministic color (e.g. white on a colored hero, or a
  /// sport color to tie the avatar to a sport).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? colorFromName(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.withValues(alpha: 0.85), c],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Text(
        initials(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: AppType.heavy,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

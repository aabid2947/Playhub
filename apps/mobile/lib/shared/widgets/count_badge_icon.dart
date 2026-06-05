import 'package:flutter/material.dart';

/// An icon with a notification-count badge. Shows a plain icon when [count] is
/// zero, and caps the label at `[max]+` so large counts don't overflow the
/// badge (e.g. `9+` instead of `147`). Wraps Material [Badge].
class CountBadgeIcon extends StatelessWidget {
  const CountBadgeIcon({
    required this.icon,
    required this.count,
    this.max = 9,
    super.key,
  });

  final IconData icon;
  final int count;
  final int max;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return Icon(icon);
    return Badge(
      label: Text(count > max ? '$max+' : '$count'),
      child: Icon(icon),
    );
  }
}

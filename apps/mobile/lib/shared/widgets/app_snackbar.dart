import 'dart:async';

import 'package:flutter/material.dart';
import 'package:playhub/core/design_tokens.dart';

/// Static helpers for showing toned toasts consistently. Tones resolve through
/// [AppSemanticColors] so they adapt to light/dark.
///
/// Toasts render as a **top overlay** (not a bottom SnackBar) and are inserted
/// into the root overlay, so they stay visible above bottom navigation bars and
/// modal bottom sheets instead of being hidden underneath them.
class AppSnackbar {
  const AppSnackbar._();

  static void success(BuildContext context, String message) {
    final semantics = AppSemanticColors.of(context);
    _show(
      context,
      message,
      icon: Icons.check_circle_outline,
      color: semantics.success,
      onColor: semantics.onSuccess,
    );
  }

  static void error(BuildContext context, String message) {
    final semantics = AppSemanticColors.of(context);
    _show(
      context,
      message,
      icon: Icons.error_outline,
      color: semantics.danger,
      onColor: semantics.onDanger,
    );
  }

  static void info(BuildContext context, String message) {
    final semantics = AppSemanticColors.of(context);
    _show(
      context,
      message,
      icon: Icons.info_outline,
      color: semantics.info,
      onColor: semantics.onInfo,
    );
  }

  static void _show(
    BuildContext context,
    String message, {
    required IconData icon,
    required Color color,
    required Color onColor,
  }) {
    // rootOverlay: true → insert above any modal bottom sheet / dialog so the
    // toast is never hidden beneath them.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    TopToast.show(
      overlay,
      message: message,
      icon: icon,
      color: color,
      onColor: onColor,
    );
  }
}

/// Inserts a single, auto-dismissing toast at the top of the given overlay,
/// replacing any toast already showing. Shared by [AppSnackbar] and the error
/// handler (which passes the root navigator's overlay).
class TopToast {
  TopToast._();

  static OverlayEntry? _entry;

  static void show(
    OverlayState overlay, {
    required String message,
    required IconData icon,
    required Color color,
    required Color onColor,
  }) {
    _entry?.remove();
    _entry = null;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopToast(
        message: message,
        icon: icon,
        color: color,
        onColor: onColor,
        onDismissed: () {
          if (identical(_entry, entry)) _entry = null;
          entry.remove();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }
}

class _TopToast extends StatefulWidget {
  const _TopToast({
    required this.message,
    required this.icon,
    required this.color,
    required this.onColor,
    required this.onDismissed,
  });

  final String message;
  final IconData icon;
  final Color color;
  final Color onColor;
  final VoidCallback onDismissed;

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppDuration.normal)
      ..forward();
    _timer = Timer(const Duration(seconds: 3), _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    if (mounted) {
      try {
        await _controller.reverse();
      } on Object {
        // controller disposed mid-reverse — ignore and finish removal.
      }
    }
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    return Positioned(
      top: MediaQuery.of(context).padding.top + AppSpacing.sm,
      left: AppSpacing.md,
      right: AppSpacing.md,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(
          opacity: curve,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: widget.onColor, size: 20),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: widget.onColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/shared/widgets/app_snackbar.dart';

/// Global keys + handlers for non-breaking error reporting.
///
/// We replace Flutter's default red-screen error widget (in production) with a
/// quiet placeholder and surface the failure via a SnackBar through
/// [rootScaffoldMessengerKey]. Async + framework errors are funneled through
/// the same toast so the UI degrades gracefully instead of crashing the tree.
class AppErrorHandler {
  AppErrorHandler._();

  /// Attach this to the root [MaterialApp.scaffoldMessengerKey]. The toast
  /// helpers below resolve a messenger via this key so they work from
  /// anywhere, including outside the widget tree (zone handlers, callbacks).
  static final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Attach this to [MaterialApp.navigatorKey] so we can resolve a
  /// [BuildContext] if the messenger is briefly unmounted (e.g. during a
  /// route transition).
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>();

  static bool _installed = false;
  static DateTime? _lastToastAt;
  static String? _lastToastMessage;

  /// Install all global error hooks. Safe to call multiple times.
  ///
  /// Skipped under `flutter test` — the test framework verifies that
  /// `ErrorWidget.builder` and `FlutterError.onError` aren't mutated
  /// during a test and would fail every test if we installed our hooks.
  static void install() {
    if (_installed) return;
    if (_runningUnderTest) return;
    _installed = true;

    // Framework/build/async errors are surfaced ONLY in debug — a labeled
    // toast with the real exception so the cause is visible while developing.
    // In RELEASE these are fully silent: a quiet placeholder for build errors
    // and no toast at all (not even "Something went wrong"). The default
    // handlers still run, so crashes are written to the system log / any
    // crash-reporter — we only suppress the on-screen surface.

    // 1) Build-time errors. Debug: Flutter's red box + a toast. Release: a
    //    quiet placeholder, no toast.
    final defaultErrorBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (details) {
      if (kDebugMode) {
        _scheduleToast(_toastFor('UI build error', details.exception));
        return defaultErrorBuilder(details);
      }
      return const _QuietErrorPlaceholder();
    };

    // 2) Framework errors (synchronous widget/render failures).
    final defaultOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      defaultOnError?.call(details); // logs to console/crash-reporter
      if (kDebugMode) {
        _scheduleToast(_toastFor('Framework error', details.exception));
      }
    };

    // 3) Async errors that escape the framework (futures, streams, etc.).
    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) {
        debugPrint('Uncaught async error: $error\n$stack');
        _scheduleToast(_toastFor('Async error', error));
      }
      // Returning true marks it handled — in release it's swallowed silently
      // (no crash, no toast).
      return true;
    };
  }

  /// Debug-only toast text — only ever called from `kDebugMode` paths, so it
  /// always surfaces the real exception (truncated) for on-device diagnosis.
  static String _toastFor(String label, Object error) {
    final s = error.toString();
    return '$label: ${s.length > 400 ? '${s.substring(0, 400)}…' : s}';
  }

  /// True when running under `flutter test` (unit or integration).
  ///
  /// We can't import `flutter_test` from lib code, so we sniff the runtime
  /// type of the bound `WidgetsBinding` — under test it's
  /// `AutomatedTestWidgetsFlutterBinding` or
  /// `IntegrationTestWidgetsFlutterBinding`. Both inherit names containing
  /// "Test". On platforms with `dart:io` we also check `FLUTTER_TEST`.
  static bool get _runningUnderTest {
    try {
      final binding = WidgetsBinding.instance;
      // `runtimeType.toString()` exists on every Dart object; cheap & safe.
      final name = binding.runtimeType.toString();
      if (name.contains('Test')) return true;
    } on Object {
      // Binding not initialized yet.
    }
    if (kIsWeb) return false;
    try {
      return Platform.environment['FLUTTER_TEST'] == 'true';
    } on Object {
      return false;
    }
  }

  /// Show a transient SnackBar from anywhere. Falls back silently if no
  /// messenger is mounted yet (very early boot).
  static void showError(String message) {
    _scheduleToast(message);
  }

  static void _scheduleToast(String message) {
    // Coalesce identical bursts within a short window so a single crash
    // doesn't spam dozens of toasts.
    final now = DateTime.now();
    final last = _lastToastAt;
    if (last != null &&
        _lastToastMessage == message &&
        now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastToastAt = now;
    _lastToastMessage = message;

    // Defer to the next frame — toast may be invoked during build, layout,
    // or before the first frame is painted.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      // Prefer the top overlay toast (sits above bottom sheets / dialogs).
      // Fall back to a bottom SnackBar only if the navigator isn't mounted yet.
      final overlay = rootNavigatorKey.currentState?.overlay;
      final ctx = rootNavigatorKey.currentContext;
      if (overlay != null && ctx != null) {
        final semantics = AppSemanticColors.of(ctx);
        TopToast.show(
          overlay,
          message: message,
          icon: Icons.error_outline,
          color: semantics.danger,
          onColor: semantics.onDanger,
        );
        return;
      }
      final messenger = rootScaffoldMessengerKey.currentState;
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    });
  }
}

/// Renders nothing visible when a sub-tree fails to build in release. We pair
/// this with a SnackBar so the user knows something went wrong without the
/// whole screen turning red.
class _QuietErrorPlaceholder extends StatelessWidget {
  const _QuietErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

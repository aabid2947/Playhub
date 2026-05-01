import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/auth_recovery.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/presentation/forgot_password_page.dart';
import 'package:playhub/features/auth/presentation/login_page.dart';
import 'package:playhub/features/auth/presentation/set_new_password_page.dart';
import 'package:playhub/features/auth/presentation/signup_page.dart';
import 'package:playhub/features/auth/presentation/splash_page.dart';
import 'package:playhub/features/dashboards/role_dashboard.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _AuthRefresh(ref),
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final inRecovery = ref.read(recoveryActiveProvider);
      final loc = state.matchedLocation;
      final loggingIn = loc == '/login' ||
          loc == '/signup' ||
          loc == '/forgot-password';
      final onSplash = loc == '/splash';
      final onResetPassword = loc == '/reset-password';

      // Browser-refresh on the root URL has no route to match. Bounce
      // into the right place based on auth state.
      if (loc == '/' || loc.isEmpty) {
        if (inRecovery) return '/reset-password';
        return session == null ? '/login' : '/home';
      }

      // Recovery deep link: route to set-password regardless of where we
      // initially landed.
      if (inRecovery && !onResetPassword) return '/reset-password';
      if (!inRecovery && onResetPassword) return '/login';

      if (onSplash) return null;
      if (session == null && !loggingIn) return '/login';
      if (session != null && loggingIn) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashPage()),
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupPage()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, __) => const SetNewPasswordPage(),
      ),
      GoRoute(path: '/home', builder: (_, __) => const RoleDashboard()),
    ],
  );
});

/// Tiny adapter to make GoRouter rebuild on auth state changes — both
/// session changes and recovery-flag flips.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref
      ..listen(sessionProvider, (_, __) => notifyListeners())
      ..listen(recoveryActiveProvider, (_, __) => notifyListeners());
  }
}

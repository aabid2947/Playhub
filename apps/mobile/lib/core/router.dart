import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/presentation/forgot_password_page.dart';
import 'package:playhub/features/auth/presentation/login_page.dart';
import 'package:playhub/features/auth/presentation/signup_page.dart';
import 'package:playhub/features/auth/presentation/splash_page.dart';
import 'package:playhub/features/dashboards/role_dashboard.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _AuthRefresh(ref),
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loggingIn = state.matchedLocation == '/login' ||
          state.matchedLocation == '/signup' ||
          state.matchedLocation == '/forgot-password';
      final onSplash = state.matchedLocation == '/splash';

      if (onSplash) return null;
      if (session == null && !loggingIn) return '/login';
      if (session != null && loggingIn) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupPage()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const ForgotPasswordPage(),
      ),
      GoRoute(path: '/home', builder: (_, __) => const RoleDashboard()),
    ],
  );
});

/// Tiny adapter to make GoRouter rebuild on auth state changes.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(sessionProvider, (_, __) => notifyListeners());
  }
}

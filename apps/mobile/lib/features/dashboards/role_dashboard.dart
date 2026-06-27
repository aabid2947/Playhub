import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/push_service.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/auth/presentation/set_new_password_page.dart';
import 'package:playhub/features/coach/presentation/coach_home_shell.dart';
import 'package:playhub/features/dashboards/setup_academy_page.dart';
import 'package:playhub/features/home/center_admin_home_tab.dart';
import 'package:playhub/features/home/owner_home_shell.dart';
import 'package:playhub/features/parent/presentation/parent_home_shell.dart';
import 'package:playhub/features/student/presentation/student_home_shell.dart';
import 'package:playhub/features/subscription/data/subscription_providers.dart';
import 'package:playhub/features/subscription/presentation/paywall_page.dart';
import 'package:playhub/features/super_admin/presentation/super_admin_home_shell.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Top-level home router. Decides which shell to show based on the
/// current user's profile state.
class RoleDashboard extends ConsumerWidget {
  const RoleDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kick off FCM init the first time we render the signed-in surface.
    ref.watch(pushBootstrapProvider);

    final profileAsync = ref.watch(currentProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(body: AppLoading()),
      error: (e, _) => Scaffold(body: AppErrorView(message: e.toString())),
      data: (profile) {
        if (profile == null) {
          return const _Centered(child: Text('No profile row found.'));
        }
        // Invited users must set a password before entering the app.
        if (profile.mustChangePassword) {
          return const SetNewPasswordPage();
        }
        if (profile.role == 'super_admin') {
          return const SuperAdminHomeShell();
        }
        if (profile.needsAcademySetup) {
          return Scaffold(
            appBar: AppBar(title: const Text('Welcome')),
            body: const SetupAcademyPage(),
          );
        }
        // Owners + admins share the full academy-wide OwnerHomeShell — unless
        // the academy's subscription is frozen (suspended/cancelled/expired
        // trial), in which case they hit the paywall until they renew. While the
        // subscription is still loading we optimistically show the shell (RLS is
        // the real gate); it rebuilds to the paywall once the status resolves.
        if (profile.role == 'academy_owner' ||
            profile.role == 'academy_admin') {
          final blocked =
              ref.watch(mySubscriptionProvider).valueOrNull?.isBlocked ?? false;
          if (blocked) return const PaywallPage();
          return const OwnerHomeShell();
        }
        // center_admin gets the same management nav but a center-scoped home
        // dashboard; reads + writes are narrowed to their center by RLS.
        if (profile.role == 'center_admin') {
          return const OwnerHomeShell(home: CenterAdminHomeTab());
        }
        if (profile.role == 'parent') return const ParentHomeShell();
        if (profile.role == 'student') return const StudentHomeShell();
        // Coach, head_coach, and trainer share the same shell — the
        // queries are scoped via coaches.user_id = auth.uid().
        if (profile.role == 'coach' ||
            profile.role == 'head_coach' ||
            profile.role == 'trainer') {
          return const CoachHomeShell();
        }
        return _RoleStub(profile: profile);
      },
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: child));
}

class _RoleStub extends ConsumerWidget {
  const _RoleStub({required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('PlayHub'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => client.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Hello, ${profile.displayName}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Chip(label: Text(profile.role)),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'Per-role experience lands in later sprints.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

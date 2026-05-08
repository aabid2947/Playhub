import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/push_service.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/auth/presentation/set_new_password_page.dart';
import 'package:playhub/features/dashboards/setup_academy_page.dart';
import 'package:playhub/features/home/owner_home_shell.dart';
import 'package:playhub/features/parent/presentation/parent_home_shell.dart';
import 'package:playhub/features/student/presentation/student_home_shell.dart';

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
      loading: () => const _Centered(child: CircularProgressIndicator()),
      error: (e, _) => _Centered(child: Text('Error: $e')),
      data: (profile) {
        if (profile == null) {
          return const _Centered(child: Text('No profile row found.'));
        }
        // Invited users must set a password before entering the app.
        if (profile.mustChangePassword) {
          return const SetNewPasswordPage();
        }
        if (profile.needsAcademySetup) {
          return Scaffold(
            appBar: AppBar(title: const Text('Welcome')),
            body: const SetupAcademyPage(),
          );
        }
        if (profile.role == 'academy_owner' ||
            profile.role == 'academy_admin') {
          return const OwnerHomeShell();
        }
        if (profile.role == 'parent') return const ParentHomeShell();
        if (profile.role == 'student') return const StudentHomeShell();
        // Other roles get the Sprint-0 stub for now; full per-role shells in
        // later sprints.
        return _RoleStub(profile: profile);
      },
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: child));
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
            const SizedBox(height: 8),
            Chip(label: Text(profile.role)),
            const SizedBox(height: 24),
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

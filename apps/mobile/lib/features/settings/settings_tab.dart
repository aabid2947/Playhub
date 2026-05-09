import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/academy/presentation/academy_settings_page.dart';
import 'package:playhub/features/audit/presentation/audit_log_page.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/centers/presentation/centers_page.dart';
import 'package:playhub/features/subscription/presentation/subscription_page.dart';
import 'package:playhub/features/support/presentation/support_page.dart';
import 'package:playhub/features/users/presentation/team_page.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
    final role = ref.watch(currentProfileProvider).valueOrNull?.role ?? '';
    final isOwnerOrAdmin =
        role == 'academy_owner' || role == 'academy_admin';
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.business_outlined),
          title: const Text('Academy settings'),
          subtitle: const Text('Name, contact, address, branding'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const AcademySettingsPage()),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: const Text('Centers'),
          subtitle: const Text('Physical locations of your academy'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const CentersPage()),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.history_outlined),
          title: const Text('Activity log'),
          subtitle: const Text('Who changed what, recently'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const AuditLogPage()),
          ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.group_outlined),
          title: const Text('Team'),
          subtitle: const Text('Invite admins, coaches, and trainers'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const TeamPage()),
          ),
        ),
        if (isOwnerOrAdmin) ...[
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('Subscription'),
            subtitle: const Text('Plan, billing cycle, past invoices'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const SubscriptionPage()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text('Support'),
            subtitle: const Text('Tickets to PlayHub support'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const SupportPage()),
            ),
          ),
        ],
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => client.auth.signOut(),
        ),
      ],
    );
  }
}

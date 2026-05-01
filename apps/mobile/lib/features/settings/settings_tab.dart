import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/academy/presentation/academy_settings_page.dart';
import 'package:playhub/features/centers/presentation/centers_page.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(supabaseClientProvider);
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
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => client.auth.signOut(),
        ),
      ],
    );
  }
}

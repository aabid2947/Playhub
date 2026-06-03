import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/notifications/data/notification_providers.dart';
import 'package:playhub/core/error_messages.dart';

class NotificationPreferencesPage extends ConsumerWidget {
  const NotificationPreferencesPage({super.key});

  static const _categories = <(String, String)>[
    ('announcement', 'Announcements'),
    ('message', 'Messages'),
    ('attendance', 'Attendance'),
    ('performance', 'Performance updates'),
    ('invoice', 'Invoices'),
    ('payment', 'Payments'),
    ('lead', 'Leads'),
    ('system', 'System'),
  ];
  static const _channels = ['push', 'in_app', 'email'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationPreferencesProvider);
    final repo = ref.watch(notificationsRepoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notification preferences')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (prefs) {
          // Build a quick lookup. Default to enabled when no row exists.
          bool isOn(String cat, String ch) {
            for (final p in prefs) {
              if (p.category == cat && p.channel == ch) return p.enabled;
            }
            return true;
          }

          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final c in _categories) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
                  child: Text(
                    c.$2,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final ch in _channels)
                  SwitchListTile(
                    title: Text(_chLabel(ch)),
                    value: isOn(c.$1, ch),
                    onChanged: (v) async {
                      await repo.setPreference(
                          category: c.$1, channel: ch, enabled: v);
                      ref.invalidate(notificationPreferencesProvider);
                    },
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  String _chLabel(String c) =>
      const {'push': 'Push', 'in_app': 'In-app', 'email': 'Email'}[c] ?? c;
}

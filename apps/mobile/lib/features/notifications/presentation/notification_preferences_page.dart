import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/notifications/data/notification_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

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

  /// Fixed width reserved for each channel switch column so the header labels
  /// line up vertically with the switches in every category row.
  static const double _channelColumnWidth = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationPreferencesProvider);
    final repo = ref.watch(notificationsRepoProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Notification preferences')),
      body: async.when(
        loading: () => const AppLoading(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(notificationPreferencesProvider),
        ),
        data: (prefs) {
          // Build a quick lookup. Default to enabled when no row exists.
          bool isOn(String cat, String ch) {
            for (final p in prefs) {
              if (p.category == cat && p.channel == ch) return p.enabled;
            }
            return true;
          }

          Future<void> setPref(String cat, String ch, {required bool on}) async {
            await repo.setPreference(category: cat, channel: ch, enabled: on);
            ref.invalidate(notificationPreferencesProvider);
          }

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                'Choose how you want to be notified for each type of activity.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  children: [
                    _ChannelHeaderRow(channelWidth: _channelColumnWidth),
                    for (var i = 0; i < _categories.length; i++) ...[
                      const Divider(height: 1),
                      _CategoryRow(
                        label: _categories[i].$2,
                        channelWidth: _channelColumnWidth,
                        values: [
                          for (final ch in _channels)
                            isOn(_categories[i].$1, ch),
                        ],
                        onChanged: (channelIndex, on) => setPref(
                          _categories[i].$1,
                          _channels[channelIndex],
                          on: on,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The header row labelling the three channel columns (Push / In-app / Email).
class _ChannelHeaderRow extends StatelessWidget {
  const _ChannelHeaderRow({required this.channelWidth});

  final double channelWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: AppType.bold,
      letterSpacing: AppType.trackingWide,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Expanded(child: SizedBox.shrink()),
          for (final ch in NotificationPreferencesPage._channels)
            SizedBox(
              width: channelWidth,
              child: Text(
                _chLabel(ch),
                textAlign: TextAlign.center,
                style: labelStyle,
              ),
            ),
        ],
      ),
    );
  }
}

/// One category row: the category name plus a switch under each channel column.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.channelWidth,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final double channelWidth;
  final List<bool> values;
  final void Function(int channelIndex, bool on) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          for (var i = 0; i < values.length; i++)
            SizedBox(
              width: channelWidth,
              child: Center(
                child: Switch(
                  value: values[i],
                  onChanged: (on) => onChanged(i, on),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _chLabel(String c) =>
    const {'push': 'Push', 'in_app': 'In-app', 'email': 'Email'}[c] ?? c;

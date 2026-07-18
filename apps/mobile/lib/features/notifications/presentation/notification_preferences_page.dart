import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/notifications/data/notification_providers.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Settings → Notification preferences. A category × channel toggle matrix —
/// for each activity category the user opts in/out of push, in-app and email.
///
/// v1 "Sports-Light" — archetype H (settings): a navy hero frames the page,
/// then the body overlaps upward into one [AppCard] per category, each grouped
/// under an [AppSectionHeader] with three real [SwitchListTile] rows (one per
/// channel). Toggling a switch persists through the existing
/// [NotificationsRepo.setPreference] write and invalidates the preferences
/// provider — presentation only; the data path is unchanged.
class NotificationPreferencesPage extends ConsumerWidget {
  const NotificationPreferencesPage({super.key});

  /// (category key, display label, leading icon) — the icon ties each card's
  /// section header to the kind of activity it governs.
  static const _categories = <(String, String, IconData)>[
    ('announcement', 'Announcements', Icons.campaign_outlined),
    ('message', 'Messages', Icons.forum_outlined),
    ('attendance', 'Attendance', Icons.fact_check_outlined),
    ('performance', 'Performance updates', Icons.insights_outlined),
    ('invoice', 'Invoices', Icons.receipt_long_outlined),
    ('payment', 'Payments', Icons.payments_outlined),
    ('lead', 'Leads', Icons.person_search_outlined),
    ('system', 'System', Icons.settings_suggest_outlined),
  ];
  static const _channels = ['push', 'in_app', 'email'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationPreferencesProvider);
    final repo = ref.watch(notificationsRepoProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: [
          // Navy hero (archetype H) with a back button + a one-line summary of
          // what the toggles below do.
          AppGradientHeader(
            colors: AppPalette.navyGradient,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppCircleIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Back',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Notifications',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: AppType.heavy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Choose how you want to be notified for each type of '
                  'activity.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    AppGlassChip(
                      'Push',
                      icon: Icons.notifications_active_outlined,
                    ),
                    AppGlassChip('In-app', icon: Icons.inbox_outlined),
                    AppGlassChip('Email', icon: Icons.mail_outline),
                  ],
                ),
              ],
            ),
          ),
          // Body overlaps the hero band upward, v1-style.
          Transform.translate(
            offset: const Offset(0, -AppSpacing.lg),
            child: async.when(
              loading: () => const AppLoading(),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () =>
                    ref.invalidate(notificationPreferencesProvider),
              ),
              data: (prefs) {
                // Build a quick lookup. Default to enabled when no row exists.
                bool isOn(String cat, String ch) {
                  for (final p in prefs) {
                    if (p.category == cat && p.channel == ch) return p.enabled;
                  }
                  return true;
                }

                Future<void> setPref(
                  String cat,
                  String ch, {
                  required bool on,
                }) async {
                  await repo.setPreference(
                    category: cat,
                    channel: ch,
                    enabled: on,
                  );
                  ref.invalidate(notificationPreferencesProvider);
                }

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (cat, label, icon) in _categories)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: _CategoryCard(
                            label: label,
                            icon: icon,
                            values: [
                              for (final ch in _channels) isOn(cat, ch),
                            ],
                            onChanged: (channelIndex, on) => setPref(
                              cat,
                              _channels[channelIndex],
                              on: on,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One category's preferences: a section header naming the activity, then a
/// real [SwitchListTile] per channel (Push / In-app / Email). Active switches
/// pick up the brand orange from `colorScheme.primary` via the theme.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.label,
    required this.icon,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final List<bool> values;
  final void Function(int channelIndex, bool on) onChanged;

  @override
  Widget build(BuildContext context) {
    const channels = NotificationPreferencesPage._channels;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: AppSectionHeader(title: label, icon: icon),
          ),
          for (var i = 0; i < values.length; i++) ...[
            if (i != 0) const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(_chIcon(channels[i])),
              title: Text(_chLabel(channels[i])),
              value: values[i],
              onChanged: (on) => onChanged(i, on),
            ),
          ],
        ],
      ),
    );
  }
}

String _chLabel(String c) =>
    const {'push': 'Push', 'in_app': 'In-app', 'email': 'Email'}[c] ?? c;

IconData _chIcon(String c) =>
    const {
      'push': Icons.notifications_active_outlined,
      'in_app': Icons.inbox_outlined,
      'email': Icons.mail_outline,
    }[c] ??
    Icons.notifications_outlined;

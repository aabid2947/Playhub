import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/core/supabase_providers.dart';
import 'package:playhub/features/auth/data/profile.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/auth/presentation/profile_page.dart';
import 'package:playhub/features/batches/presentation/batches_tab.dart';
import 'package:playhub/features/coaches/presentation/coaches_tab.dart';
import 'package:playhub/features/home/home_tab.dart';
import 'package:playhub/features/settings/settings_tab.dart';
import 'package:playhub/features/students/presentation/students_tab.dart';
import 'package:playhub/shared/widgets/verification_banner.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Bottom-nav scaffold for academy owners (and later, admins).
/// Each tab keeps its own state via IndexedStack. The Home tab is injected so
/// center_admin can get a center-scoped dashboard while sharing the rest of
/// the management nav (students/coaches/batches/settings).
///
/// This shell defines the **canonical shell contract** reused by every role
/// shell: a single top AppBar that shows the brand wordmark (the bottom nav
/// labels the active tab, so the header never repeats it), a single
/// [AccountAction] entry point (avatar → Profile + Sign out), and a compact,
/// dismissible [VerificationBanner] strip that doesn't permanently shove the
/// body down.
class OwnerHomeShell extends StatefulWidget {
  const OwnerHomeShell({super.key, this.home = const HomeTab()});

  /// Widget shown on the first ("Home") tab.
  final Widget home;

  @override
  State<OwnerHomeShell> createState() => _OwnerHomeShellState();
}

class _OwnerHomeShellState extends State<OwnerHomeShell> {
  int _index = 0;
  bool _bannerDismissed = false;

  static const _tabs = <_TabSpec>[
    _TabSpec('Home', Icons.home_outlined, Icons.home),
    _TabSpec('Students', Icons.group_outlined, Icons.group),
    _TabSpec('Coaches', Icons.sports_outlined, Icons.sports),
    _TabSpec('Batches', Icons.schedule_outlined, Icons.schedule),
    _TabSpec('Settings', Icons.settings_outlined, Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // The brand wordmark is the only top-header title. The bottom nav
        // already labels the active tab, so a per-tab title would just repeat
        // it — keep the header as "PlayHub" on every tab.
        title: const BrandWordmark(),
        actions: const [
          AccountAction(),
          SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Column(
        children: [
          if (!_bannerDismissed)
            _DismissibleBanner(
              onDismiss: () => setState(() => _bannerDismissed = true),
            ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                widget.home,
                const StudentsTab(),
                const CoachesTab(),
                const BatchesTab(),
                const SettingsTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.activeIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Wraps the shared [VerificationBanner] in a compact strip with a dismiss
/// affordance so it isn't a permanent body-shover. The banner already renders
/// nothing when the user is verified; this only adds the close control beside
/// it (without touching the banner's own API), gated on the same
/// "unverified email" condition so the dismiss button never appears alone.
class _DismissibleBanner extends ConsumerWidget {
  const _DismissibleBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider)?.user;
    final unverified =
        user != null && user.emailConfirmedAt == null && user.email != null;
    if (!unverified) return const SizedBox.shrink();
    // Place the dismiss control as a sibling *beside* the banner (not overlaid
    // in a Stack, which would collide with the banner's own "Resend" button).
    // The banner's inner row uses Expanded, so wrap it in Expanded here too.
    return Row(
      children: [
        const Expanded(child: VerificationBanner()),
        IconButton(
          tooltip: 'Dismiss',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close),
          onPressed: onDismiss,
        ),
      ],
    );
  }
}

/// The single account entry point shared by every role shell: an avatar button
/// in the AppBar that opens a sheet exposing Profile + Sign out. Sign-out used
/// to be buried at the bottom of the Settings tab; this surfaces it everywhere
/// the shell is shown.
class AccountAction extends ConsumerWidget {
  const AccountAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final photoUrl =
        ref.watch(storageServiceProvider).publicAvatarUrl(profile?.profilePhoto);
    return IconButton(
      tooltip: 'Account',
      iconSize: 32,
      icon: _AccountAvatar(profile: profile, photoUrl: photoUrl, radius: 16),
      onPressed: () => _openAccountSheet(context),
    );
  }

  void _openAccountSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _AccountSheet(),
    );
  }
}

/// Bottom sheet listing the account actions. Kept short and single-purpose per
/// the sheet anatomy: a header identity row, then Profile + Sign out.
class _AccountSheet extends ConsumerWidget {
  const _AccountSheet();

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    Navigator.of(context).pop();
    try {
      await ref.read(supabaseClientProvider).auth.signOut();
    } on Object catch (e) {
      if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final photoUrl =
        ref.watch(storageServiceProvider).publicAvatarUrl(profile?.profilePhoto);
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                _AccountAvatar(
                  profile: profile,
                  photoUrl: photoUrl,
                  radius: 24,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile?.displayName ?? 'Account',
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (profile?.email != null)
                        Text(
                          profile!.email!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          AppListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Profile'),
            subtitle: const Text('Your name, photo, and contact'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const ProfilePage()),
              );
            },
          ),
          const Divider(height: 1),
          AppListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            trailing: const SizedBox.shrink(),
            onTap: () => _signOut(context, ref),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// Circular avatar showing the user's photo, falling back to their initial.
/// Used both in the AppBar action and the account sheet header.
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.profile,
    required this.photoUrl,
    required this.radius,
  });

  final Profile? profile;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = profile?.firstName;
    final fallback = (first != null && first.isNotEmpty)
        ? first[0].toUpperCase()
        : '?';
    final placeholder = CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Text(
        fallback,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
    if (photoUrl == null) return placeholder;
    final diameter = radius * 2;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: photoUrl!,
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }
}

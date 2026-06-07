import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/announcements/presentation/announcements_page.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/chat/presentation/threads_page.dart';
import 'package:playhub/features/coach/presentation/coach_batches_tab.dart';
import 'package:playhub/features/coach/presentation/coach_home_tab.dart';
import 'package:playhub/features/home/owner_home_shell.dart';
import 'package:playhub/features/notifications/data/notification_providers.dart';
import 'package:playhub/features/notifications/presentation/notification_center_page.dart';
import 'package:playhub/features/users/presentation/invite_user_sheet.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Shell for coach / head_coach / trainer roles. Five-tab nav:
/// Home, My batches, Announcements, Messages, Alerts.
///
/// Canonical shell contract (shared with [OwnerHomeShell]): ONE persistent top
/// AppBar showing the brand wordmark + a single [AccountAction] (Profile + Sign
/// out). The bottom nav labels the active tab, so the header never repeats it.
/// The hosted tab pages render app-bar-less (the shared pages take
/// `embedded: true`) so there is never a second bar.
class CoachHomeShell extends ConsumerStatefulWidget {
  const CoachHomeShell({super.key});

  @override
  ConsumerState<CoachHomeShell> createState() => _CoachHomeShellState();
}

class _CoachHomeShellState extends ConsumerState<CoachHomeShell> {
  int _index = 0;

  Future<void> _openInvite() async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const InviteUserSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider);
    // head_coach → coach/trainer, coach → trainer: surface the invite entry
    // when this user may provision anyone (RLS + the invite-user fn enforce the
    // ladder; this only shows the button).
    final canInvite = ref.watch(capabilitiesProvider).canProvisionAnyone;
    const pages = [
      CoachHomeTab(),
      CoachBatchesTab(),
      AnnouncementsPage(embedded: true),
      ThreadsPage(embedded: true),
      NotificationCenterPage(embedded: true),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const BrandWordmark(),
        actions: [
          if (canInvite)
            IconButton(
              tooltip: 'Invite staff',
              icon: const Icon(Icons.person_add_outlined),
              onPressed: _openInvite,
            ),
          const AccountAction(),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            selectedIcon: Icon(Icons.schedule),
            label: 'Batches',
          ),
          const NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: 'Notices',
          ),
          const NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: CountBadgeIcon(
              icon: Icons.notifications_outlined,
              count: unread,
            ),
            selectedIcon: CountBadgeIcon(
              icon: Icons.notifications,
              count: unread,
            ),
            label: 'Alerts',
          ),
        ],
      ),
    );
  }
}

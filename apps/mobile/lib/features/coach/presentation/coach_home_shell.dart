import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/announcements/presentation/announcements_page.dart';
import 'package:playhub/features/chat/presentation/threads_page.dart';
import 'package:playhub/features/coach/presentation/coach_batches_tab.dart';
import 'package:playhub/features/coach/presentation/coach_home_tab.dart';
import 'package:playhub/features/home/owner_home_shell.dart';
import 'package:playhub/features/notifications/data/notification_providers.dart';
import 'package:playhub/features/notifications/presentation/notification_center_page.dart';
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

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider);
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
        actions: const [
          AccountAction(),
          SizedBox(width: AppSpacing.xs),
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

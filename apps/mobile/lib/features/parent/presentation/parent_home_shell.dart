import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/announcements/presentation/announcements_page.dart';
import 'package:playhub/features/chat/presentation/threads_page.dart';
import 'package:playhub/features/home/owner_home_shell.dart';
import 'package:playhub/features/notifications/data/notification_providers.dart';
import 'package:playhub/features/notifications/presentation/notification_center_page.dart';
import 'package:playhub/features/parent/presentation/parent_dashboard_tab.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Shell for the parent role (and, via subclass, the student role). Four-tab
/// nav: Home, Notices, Messages, Alerts.
///
/// Canonical shell contract (shared with [OwnerHomeShell]): ONE persistent top
/// AppBar showing the brand wordmark + a single [AccountAction] (Profile + Sign
/// out); the bottom nav labels the active tab. Hosted pages render app-bar-less
/// (the shared pages take `embedded: true`) so there is never a second bar.
class ParentHomeShell extends ConsumerStatefulWidget {
  const ParentHomeShell({super.key});

  @override
  ConsumerState<ParentHomeShell> createState() => _ParentHomeShellState();
}

class _ParentHomeShellState extends ConsumerState<ParentHomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadNotificationCountProvider);
    const pages = [
      ParentDashboardTab(),
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

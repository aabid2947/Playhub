import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/announcements/presentation/announcements_page.dart';
import 'package:playhub/features/chat/presentation/threads_page.dart';
import 'package:playhub/features/coach/presentation/coach_batches_tab.dart';
import 'package:playhub/features/coach/presentation/coach_home_tab.dart';
import 'package:playhub/features/notifications/data/notification_providers.dart';
import 'package:playhub/features/notifications/presentation/notification_center_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Shell for coach / head_coach / trainer roles. Five-tab nav:
/// Home, My batches, Announcements, Messages, Alerts.
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
    final pages = const [
      CoachHomeTab(),
      CoachBatchesTab(),
      AnnouncementsPage(),
      ThreadsPage(),
      NotificationCenterPage(),
    ];
    return Scaffold(
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/features/home/owner_home_shell.dart';
import 'package:playhub/features/super_admin/presentation/academies_page.dart';
import 'package:playhub/features/super_admin/presentation/global_health_page.dart';
import 'package:playhub/features/super_admin/presentation/plans_page.dart';
import 'package:playhub/features/super_admin/presentation/super_tickets_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Top-level shell for super_admin role. Lives on its own routes (separate
/// from per-academy shells per PLAN.md §3.10).
///
/// Follows the canonical shell contract (see [OwnerHomeShell]): a single,
/// constant AppBar (brand wordmark + an "Admin" badge — never per-tab, since
/// the bottom nav already labels the active tab) and one [AccountAction] entry
/// point exposing Profile + Sign out. The four hosted tabs are app-bar-less
/// bodies in an [IndexedStack]; do not give them their own Scaffold AppBar.
class SuperAdminHomeShell extends ConsumerStatefulWidget {
  const SuperAdminHomeShell({super.key});

  @override
  ConsumerState<SuperAdminHomeShell> createState() =>
      _SuperAdminHomeShellState();
}

class _SuperAdminHomeShellState extends ConsumerState<SuperAdminHomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Constant title on every tab: brand wordmark + an "Admin" badge. The
        // bottom nav labels the active tab, so the header never changes.
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandWordmark(),
            SizedBox(width: AppSpacing.sm),
            AppBadge(text: 'Admin', tone: AppBadgeTone.brand),
          ],
        ),
        actions: const [
          AccountAction(),
          SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          GlobalHealthPage(),
          AcademiesPage(),
          PlansPage(),
          SuperTicketsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.health_and_safety_outlined),
            selectedIcon: Icon(Icons.health_and_safety),
            label: 'Health',
          ),
          NavigationDestination(
            icon: Icon(Icons.business_outlined),
            selectedIcon: Icon(Icons.business),
            label: 'Academies',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: 'Plans',
          ),
          NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent),
            label: 'Tickets',
          ),
        ],
      ),
    );
  }
}

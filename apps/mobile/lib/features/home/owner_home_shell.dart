import 'package:flutter/material.dart';
import 'package:playhub/features/auth/presentation/profile_page.dart';
import 'package:playhub/features/batches/presentation/batches_tab.dart';
import 'package:playhub/features/coaches/presentation/coaches_tab.dart';
import 'package:playhub/features/home/home_tab.dart';
import 'package:playhub/features/settings/settings_tab.dart';
import 'package:playhub/features/students/presentation/students_tab.dart';
import 'package:playhub/shared/widgets/verification_banner.dart';

/// Bottom-nav scaffold for academy owners (and later, admins).
/// Each tab keeps its own state via IndexedStack. The Home tab is injected so
/// center_admin can get a center-scoped dashboard while sharing the rest of
/// the management nav (students/coaches/batches/settings).
class OwnerHomeShell extends StatefulWidget {
  const OwnerHomeShell({super.key, this.home = const HomeTab()});

  /// Widget shown on the first ("Home") tab.
  final Widget home;

  @override
  State<OwnerHomeShell> createState() => _OwnerHomeShellState();
}

class _OwnerHomeShellState extends State<OwnerHomeShell> {
  int _index = 0;

  static const _tabs = <_TabSpec>[
    _TabSpec('Home', Icons.home_outlined, Icons.home),
    _TabSpec('Students', Icons.group_outlined, Icons.group),
    _TabSpec('Coaches', Icons.sports_outlined, Icons.sports),
    _TabSpec('Batches', Icons.schedule_outlined, Icons.schedule),
    _TabSpec('Settings', Icons.settings_outlined, Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final titles = ['PlayHub', 'Students', 'Coaches', 'Batches', 'Settings'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Profile',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const ProfilePage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const VerificationBanner(),
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

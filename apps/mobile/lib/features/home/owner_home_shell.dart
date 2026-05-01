import 'package:flutter/material.dart';
import 'package:playhub/features/batches/presentation/batches_tab.dart';
import 'package:playhub/features/coaches/presentation/coaches_tab.dart';
import 'package:playhub/features/home/home_tab.dart';
import 'package:playhub/features/settings/settings_tab.dart';
import 'package:playhub/features/students/presentation/students_tab.dart';

/// Bottom-nav scaffold for academy owners (and later, admins).
/// Each tab keeps its own state via IndexedStack.
class OwnerHomeShell extends StatefulWidget {
  const OwnerHomeShell({super.key});

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
      appBar: AppBar(title: Text(titles[_index])),
      body: IndexedStack(
        index: _index,
        children: const [
          HomeTab(),
          StudentsTab(),
          CoachesTab(),
          BatchesTab(),
          SettingsTab(),
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

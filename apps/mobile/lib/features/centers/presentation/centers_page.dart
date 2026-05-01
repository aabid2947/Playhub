import 'package:flutter/material.dart';
import 'package:playhub/features/centers/presentation/centers_tab.dart';

/// Wraps [CentersTab] in its own Scaffold for use as a pushed route from
/// Settings (since the tab variant assumes the parent shell provides the
/// AppBar).
class CentersPage extends StatelessWidget {
  const CentersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Centers')),
      body: const CentersTab(),
    );
  }
}

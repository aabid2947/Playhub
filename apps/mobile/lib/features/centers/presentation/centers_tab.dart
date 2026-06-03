import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/centers/presentation/center_form_page.dart';
import 'package:playhub/core/error_messages.dart';

class CentersTab extends ConsumerWidget {
  const CentersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final centersAsync = ref.watch(centersProvider);

    return Scaffold(
      body: centersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (centers) {
          if (centers.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(centersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: centers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = centers[i];
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(c.name),
                  subtitle: Text(
                    [
                      if (c.city != null) c.city,
                      if (!c.isActive) 'inactive',
                    ].whereType<String>().join(' • '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => CenterFormPage(existing: c),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const CenterFormPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New center'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_city_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              'No centers yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap "New center" to add the first physical location for your academy.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

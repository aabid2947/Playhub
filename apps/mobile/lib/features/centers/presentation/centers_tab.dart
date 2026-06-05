import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/centers/presentation/center_form_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class CentersTab extends ConsumerWidget {
  const CentersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final centersAsync = ref.watch(centersProvider);

    return Scaffold(
      body: centersAsync.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(centersProvider),
        ),
        data: (centers) {
          if (centers.isEmpty) {
            return AppEmptyState(
              icon: Icons.location_city_outlined,
              title: 'No centers yet',
              subtitle:
                  'Add the first physical location for your academy.',
              actionLabel: 'New center',
              onAction: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const CenterFormPage()),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(centersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: centers.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = centers[i];
                return AppListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(c.name),
                  subtitle: Text(
                    [
                      if (c.city != null) c.city!,
                      if (!c.isActive) 'Inactive',
                    ].join(' • '),
                  ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/centers/data/center.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/centers/presentation/center_form_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

class CentersTab extends ConsumerWidget {
  const CentersTab({super.key});

  void _openForm(BuildContext context, {Centre? existing}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => CenterFormPage(existing: existing)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final centersAsync = ref.watch(centersProvider);
    // Centers are an org-level record; managing them rides the admin-tier
    // gate (mirrors team/org management). center_admin is center-scoped and
    // does not create centers.
    final caps = ref.watch(capabilitiesProvider);

    return Scaffold(
      body: centersAsync.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(centersProvider),
        ),
        data: (centers) {
          if (centers.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(centersProvider),
            child: ListView.separated(
              itemCount: centers.length + 1,
              separatorBuilder: (_, i) => i == 0
                  ? const SizedBox.shrink()
                  : const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _ResultCount(count: centers.length);
                }
                final centre = centers[i - 1];
                return _CentreTile(
                  centre: centre,
                  onTap: () => _openForm(context, existing: centre),
                );
              },
            ),
          );
        },
      ),
      // Single create path, gated. The empty state no longer carries its own
      // CTA, so create lives in exactly one place.
      floatingActionButton: caps.manageTeam
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add),
              label: const Text('New center'),
            )
          : null,
    );
  }
}

/// Visible result count above the list, e.g. "3 centers".
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        count == 1 ? '1 center' : '$count centers',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CentreTile extends StatelessWidget {
  const _CentreTile({required this.centre, required this.onTap});
  final Centre centre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // One tight subtitle line: city (the locating fact) plus state when there
    // is no city to anchor on. Status moved out to the trailing badge.
    final locality = <String>[
      if (centre.city != null && centre.city!.isNotEmpty) centre.city!,
      if (centre.state != null && centre.state!.isNotEmpty) centre.state!,
    ].join(', ');

    return AppListTile(
      leading: const Icon(Icons.location_on_outlined),
      title: Text(centre.name),
      subtitle: Text(
        locality.isEmpty ? 'No location set' : locality,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _StatusBadge(isActive: centre.isActive),
      onTap: onTap,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return AppBadge(
      text: isActive ? 'Active' : 'Inactive',
      tone: isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.location_city_outlined,
      title: 'No centers yet',
      subtitle: 'Tap "New center" to add your first location.',
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/centers/data/center.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/centers/presentation/center_form_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Full-page centers list, pushed from Settings.
///
/// Owns a single [Scaffold] (AppBar + body + FAB) and renders the list inline
/// rather than nesting `CentersTab`'s own Scaffold — that double-Scaffold was
/// the source of the stacked-header smell. The list mirrors `CentersTab` and
/// reads the same `centersProvider`, so behaviour is unchanged.
class CentersPage extends ConsumerWidget {
  const CentersPage({super.key});

  void _openForm(BuildContext context, {Centre? existing}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => CenterFormPage(existing: existing)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final centersAsync = ref.watch(centersProvider);
    // Centers are an org-level record; managing them rides the admin-tier gate
    // (mirrors team/org management). center_admin is center-scoped and does not
    // create centers, so the create path is hidden for them. RLS is the real
    // gate; this only hides the entry point.
    final caps = ref.watch(capabilitiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Centers')),
      // Single create path, gated. Mirrors CentersTab so behaviour matches.
      floatingActionButton: caps.manageTeam
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(context),
              icon: const Icon(Icons.add),
              label: const Text('New center'),
            )
          : null,
      body: centersAsync.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(centersProvider),
        ),
        data: (centers) {
          if (centers.isEmpty) {
            // No empty-state CTA: the FAB is the single create path.
            return const AppEmptyState(
              icon: Icons.location_city_outlined,
              title: 'No centers yet',
              subtitle: 'Add the first physical location for your academy.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(centersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
              // +1 leading row for the result-count header.
              itemCount: centers.length + 1,
              separatorBuilder: (_, i) =>
                  i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == 0) return _CountHeader(count: centers.length);
                final center = centers[i - 1];
                // Editing a center rides the same admin-tier gate as creating
                // (centers_admin_write = has_admin_or_higher). For center_admin
                // and other non-managers the row is read-only info — no tap to
                // an edit form RLS would reject.
                return _CenterRow(
                  center: center,
                  onTap: caps.manageTeam
                      ? () => _openForm(context, existing: center)
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Thin overline showing how many centers are listed.
class _CountHeader extends StatelessWidget {
  const _CountHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noun = count == 1 ? 'center' : 'centers';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        '$count $noun',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _CenterRow extends StatelessWidget {
  const _CenterRow({required this.center, this.onTap});

  final Centre center;

  /// Null for read-only viewers (e.g. center_admin) — the row then shows
  /// center info without a tap-to-edit affordance.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Subtitle stays one tight line (city, or a fallback when none is set);
    // active/inactive moves out of the subtitle into a trailing badge.
    final subtitle = center.city ?? 'No city set';
    return AppListTile(
      leading: const Icon(Icons.location_on_outlined),
      title: Text(center.name),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: center.isActive
          ? null
          : const AppBadge(text: 'Inactive'),
      onTap: onTap,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/centers/data/center.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/centers/presentation/center_form_page.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Local active/inactive filter for the centers list. `null` = all.
enum _CenterStatusFilter { all, active, inactive }

/// Full-page centers list, pushed from Settings.
///
/// A standalone pushed page, so it keeps its own [AppBar] (this is NOT a shell
/// body tab) — the title lives there, not in an in-body header. It owns a single
/// [Scaffold] and renders the list inline rather than nesting `CentersTab`'s
/// Scaffold; that double-Scaffold was the old stacked-header smell. The list
/// mirrors `CentersTab` and reads the same `centersProvider` (archetype B).
class CentersPage extends ConsumerStatefulWidget {
  const CentersPage({super.key});

  @override
  ConsumerState<CentersPage> createState() => _CentersPageState();
}

class _CentersPageState extends ConsumerState<CentersPage> {
  final _search = TextEditingController();
  _CenterStatusFilter _status = _CenterStatusFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openForm({Centre? existing}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => CenterFormPage(existing: existing)),
    );
  }

  /// Client-side search + status filter over the already-fetched list.
  List<Centre> _filter(List<Centre> centers) {
    final query = _search.text.trim().toLowerCase();
    return centers.where((c) {
      switch (_status) {
        case _CenterStatusFilter.active:
          if (!c.isActive) return false;
        case _CenterStatusFilter.inactive:
          if (c.isActive) return false;
        case _CenterStatusFilter.all:
          break;
      }
      if (query.isEmpty) return true;
      final haystack = [
        c.name,
        if (c.city != null) c.city!,
        if (c.state != null) c.state!,
        if (c.pincode != null) c.pincode!,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
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
              heroTag: 'fab-centers-page',
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('New center'),
            )
          : null,
      body: Column(
        children: [
          _FilterBar(
            controller: _search,
            status: _status,
            onSearch: () => setState(() {}),
            onStatusChanged: (v) => setState(() => _status = v),
          ),
          Expanded(
            child: centersAsync.when(
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
                final results = _filter(centers);
                if (results.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.search_off_outlined,
                    title: 'No matches',
                    subtitle: 'Try a different name or clear the filters.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(centersProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.xxl,
                    ),
                    itemCount: results.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, i) {
                      final center = results[i];
                      // Editing rides the same admin-tier gate as creating
                      // (centers_admin_write = has_admin_or_higher). For
                      // center_admin / non-managers the row is read-only info —
                      // no tap to an edit form RLS would reject.
                      return _CentreTile(
                        centre: center,
                        onTap: caps.manageTeam
                            ? () => _openForm(existing: center)
                            : null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// In-body filter surface beneath the AppBar: a search field then a segmented
/// status pill bar (no title row here — the AppBar carries the title).
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.controller,
    required this.status,
    required this.onSearch,
    required this.onStatusChanged,
  });

  final TextEditingController controller;
  final _CenterStatusFilter status;
  final VoidCallback onSearch;
  final ValueChanged<_CenterStatusFilter> onStatusChanged;

  static const _tabs = ['All', 'Active', 'Inactive'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              onSubmitted: (_) => onSearch(),
              onChanged: (_) => onSearch(),
              decoration: InputDecoration(
                hintText: 'Search name, city…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          controller.clear();
                          onSearch();
                        },
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppPillTabs(
              tabs: _tabs,
              index: status.index,
              onChanged: (i) =>
                  onStatusChanged(_CenterStatusFilter.values[i]),
            ),
          ],
        ),
      ),
    );
  }
}

/// A center row as a soft-shadow [AppCard]: a tinted location icon → name →
/// one tight locality line → trailing active/inactive [AppBadge].
class _CentreTile extends StatelessWidget {
  const _CentreTile({required this.centre, this.onTap});
  final Centre centre;

  /// Null for read-only viewers (e.g. center_admin) — the row then shows center
  /// info without a tap-to-edit affordance RLS would reject.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locality = <String>[
      if (centre.city != null && centre.city!.isNotEmpty) centre.city!,
      if (centre.state != null && centre.state!.isNotEmpty) centre.state!,
    ].join(', ');
    final tint = colorFromName(centre.name);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.location_on_rounded, color: tint, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  centre.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  locality.isEmpty ? 'No location set' : locality,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppBadge(
            text: centre.isActive ? 'Active' : 'Inactive',
            tone: centre.isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
          ),
        ],
      ),
    );
  }
}

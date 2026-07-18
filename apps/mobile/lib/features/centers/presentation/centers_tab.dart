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

/// Body tab under `owner_home_shell`'s single AppBar — stays app-bar-less with
/// an in-body header row instead (archetype B). v1 "Sports-Light" list.
class CentersTab extends ConsumerStatefulWidget {
  const CentersTab({super.key});

  @override
  ConsumerState<CentersTab> createState() => _CentersTabState();
}

class _CentersTabState extends ConsumerState<CentersTab> {
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

  /// Client-side search + status filter over the already-fetched list. The
  /// centers provider returns the full tenant-scoped set; we narrow it here so
  /// the data layer stays untouched.
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

    // Header count reflects the filtered view (null until data lands).
    final loaded = centersAsync.valueOrNull;
    final headerCount = loaded == null ? null : _filter(loaded).length;

    return Scaffold(
      body: Column(
        children: [
          _FilterBar(
            controller: _search,
            status: _status,
            count: headerCount,
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
                  return const _EmptyState();
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
                    itemBuilder: (context, i) => _CentreTile(
                      centre: results[i],
                      // Editing rides the same admin-tier gate as creating; for
                      // read-only viewers (center_admin) the row is info-only.
                      onTap: caps.manageTeam
                          ? () => _openForm(existing: results[i])
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      // Single create path, gated. The empty state carries no CTA, so create
      // lives in exactly one place.
      floatingActionButton: caps.manageTeam
          ? FloatingActionButton.extended(
              heroTag: 'fab-centers',
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: const Text('New center'),
            )
          : null,
    );
  }
}

/// In-body header (no AppBar here — this is a shell body tab): a navy
/// `headlineSmall` title with a live count badge, the search field, then a
/// segmented status pill bar — one coherent control surface, v1-style.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.controller,
    required this.status,
    required this.count,
    required this.onSearch,
    required this.onStatusChanged,
  });

  final TextEditingController controller;
  final _CenterStatusFilter status;
  // Live count of the filtered results, shown in the header badge.
  final int? count;
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
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Centers', style: theme.textTheme.headlineSmall),
                const SizedBox(width: AppSpacing.sm),
                if (count != null)
                  AppBadge(text: '$count', tone: AppBadgeTone.brand),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
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
    // One tight subtitle line: city (the locating fact), with state when there
    // is no city to anchor on. Status moves out to the trailing badge.
    final locality = <String>[
      if (centre.city != null && centre.city!.isNotEmpty) centre.city!,
      if (centre.state != null && centre.state!.isNotEmpty) centre.state!,
    ].join(', ');
    // Deterministic accent ties the tile's icon to the center, v1-style.
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
          _StatusBadge(isActive: centre.isActive),
        ],
      ),
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

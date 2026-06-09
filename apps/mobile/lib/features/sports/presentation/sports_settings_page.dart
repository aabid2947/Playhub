import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/auth/data/profile_providers.dart';
import 'package:playhub/features/centers/data/center.dart';
import 'package:playhub/features/centers/data/center_providers.dart';
import 'package:playhub/features/sports/data/sport.dart';
import 'package:playhub/features/sports/data/sport_providers.dart';
import 'package:playhub/features/sports/presentation/sport_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Settings → Sports. The center selector is the scope control: pick a center,
/// manage which sports it offers. Defaults to the user's center_id when set;
/// falls back to the first center in the academy.
///
/// v1 "Sports-Light" — archetype H (settings) over B (list): a navy hero frames
/// the page as "Sports at <center>" with the center picker as the scope control,
/// then a sport-colored card list of enabled sports below, with an orange
/// "Add sport" FAB. Writes stay gated by `caps.manageSports` (center_admin =
/// own center; RLS is the real gate).
class SportsSettingsPage extends ConsumerStatefulWidget {
  const SportsSettingsPage({super.key});

  @override
  ConsumerState<SportsSettingsPage> createState() =>
      _SportsSettingsPageState();
}

class _SportsSettingsPageState extends ConsumerState<SportsSettingsPage> {
  String? _centerId;
  String? _sportFilterId;

  void _refresh() {
    if (_centerId != null) {
      ref.invalidate(centerSportsProvider(_centerId!));
    }
    ref.invalidate(academyCenterSportsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final centersAsync = ref.watch(centersProvider);
    final caps = ref.watch(capabilitiesProvider);
    final myCenterId = ref.watch(currentProfileProvider).valueOrNull?.centerId;
    // Enabling/renaming/removing sports writes center_sports: admin tier writes
    // any center, center_admin their OWN (can_admin_center_scope). This only
    // hides the controls; RLS is the real gate.
    final canManage = caps.manageSports;
    return Scaffold(
      body: centersAsync.when(
        loading: () => const AppSkeletonList(),
        error: (e, _) => AppErrorView(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(centersProvider),
        ),
        data: (allCenters) {
          // center_admin manages only their own center; admin tier sees all.
          // Filtering the scope picker keeps the UI from offering a center
          // whose center_sports writes RLS would reject.
          final centers = caps.isCenterScoped && myCenterId != null
              ? allCenters
                    .where((c) => c.id == myCenterId)
                    .toList(growable: false)
              : allCenters;
          if (centers.isEmpty) {
            return Column(
              children: [
                _ScopeHeader(
                  centers: const [],
                  centerId: null,
                  scopeName: 'this academy',
                  onChanged: (_) {},
                  onRefresh: _refresh,
                ),
                const Expanded(
                  child: AppEmptyState(
                    icon: Icons.location_city_outlined,
                    title: 'No centers yet',
                    subtitle:
                        'Add a center in Settings → Centers first, then come '
                        'back here to enable its sports.',
                  ),
                ),
              ],
            );
          }
          _centerId ??= centers.first.id;
          final activeCenters =
              centers.where((c) => c.isActive).toList(growable: false);
          final scopeName = centers
              .firstWhere(
                (c) => c.id == _centerId,
                orElse: () => centers.first,
              )
              .name;
          return Column(
            children: [
              _ScopeHeader(
                centers: activeCenters,
                centerId: _centerId,
                scopeName: scopeName,
                onChanged: (v) => setState(() {
                  _centerId = v;
                  _sportFilterId = null;
                }),
                onRefresh: _refresh,
              ),
              Expanded(
                child: _centerId == null
                    ? const SizedBox.shrink()
                    : _CenterSportsList(
                        centerId: _centerId!,
                        filterId: _sportFilterId,
                        onFilter: (v) => setState(() => _sportFilterId = v),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: (_centerId == null || !canManage)
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add sport'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _AddSportSheet(centerId: _centerId!),
              ),
            ),
    );
  }
}

/// Navy hero (archetype H) — frames the page as "Sports at <center>" and
/// exposes the center picker as the scope control that drives the list below.
/// Back + refresh circle buttons sit on the gradient.
class _ScopeHeader extends StatelessWidget {
  const _ScopeHeader({
    required this.centers,
    required this.centerId,
    required this.scopeName,
    required this.onChanged,
    required this.onRefresh,
  });

  final List<Centre> centers;
  final String? centerId;
  final String scopeName;
  final ValueChanged<String?> onChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppGradientHeader(
      colors: AppPalette.navyGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppCircleIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              AppCircleIconButton(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                onTap: onRefresh,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Sports',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: AppType.heavy,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(
                Icons.place_outlined,
                size: 15,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Sports at $scopeName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
          if (centers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _CenterScopePicker(
              centers: centers,
              centerId: centerId,
              onChanged: onChanged,
            ),
          ],
        ],
      ),
    );
  }
}

/// White-on-navy center dropdown used inside the hero as the scope control.
/// A bespoke frosted pill (the form-styled [AppDropdownField] is built for
/// light surfaces, not a gradient hero), but it stays a real [DropdownButton].
class _CenterScopePicker extends StatelessWidget {
  const _CenterScopePicker({
    required this.centers,
    required this.centerId,
    required this.onChanged,
  });

  final List<Centre> centers;
  final String? centerId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: centerId,
          isExpanded: true,
          dropdownColor: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          icon: Icon(
            Icons.expand_more,
            color: Colors.white.withValues(alpha: 0.85),
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          selectedItemBuilder: (_) => [
            for (final c in centers)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: AppType.semibold,
                  ),
                ),
              ),
          ],
          items: [
            for (final c in centers)
              DropdownMenuItem(
                value: c.id,
                child: Text(c.name),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _CenterSportsList extends ConsumerWidget {
  const _CenterSportsList({
    required this.centerId,
    required this.filterId,
    required this.onFilter,
  });

  final String centerId;
  final String? filterId;
  final ValueChanged<String?> onFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(centerSportsProvider(centerId));
    return async.when(
      loading: () => const AppSkeletonList(),
      error: (e, _) => AppErrorView(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(centerSportsProvider(centerId)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const AppEmptyState(
            icon: Icons.sports_outlined,
            title: 'No sports here yet',
            subtitle: 'Tap "Add sport" to enable one for this center.',
          );
        }
        final visible = filterId == null
            ? rows
            : rows.where((r) => r.sport.id == filterId).toList(growable: false);
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(centerSportsProvider(centerId)),
          child: ListView(
            // Pull the body up so the cards overlap the navy hero, v1-style.
            padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
            children: [
              Transform.translate(
                offset: const Offset(0, -AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sport filter chips (scoped to this center) — visual filter
                    // only; an "All" pill clears it.
                    SportFilterChipBar(
                      centerId: centerId,
                      selectedId: filterId,
                      onSelected: onFilter,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: AppSectionHeader(
                        title: 'Enabled sports',
                        icon: Icons.sports_outlined,
                        trailing: AppBadge(
                          text: '${visible.length}',
                          tone: AppBadgeTone.brand,
                        ),
                      ),
                    ),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.lg,
                          0,
                        ),
                        child: Text(
                          'No sports match this filter.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        child: Column(
                          children: [
                            for (final row in visible)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: _SportRow(row: row),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SportRow extends ConsumerWidget {
  const _SportRow({required this.row});
  final CenterSport row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isRenamed =
        row.customName != null && row.customName!.trim().isNotEmpty;
    final tint = colorFromName(row.displayName);
    // Rename/remove write center_sports (can_admin_center_scope): admin tier +
    // center_admin (own center, enforced by the scope filter above + RLS).
    final canManage = ref.watch(capabilitiesProvider).manageSports;

    final subtitle = isRenamed
        ? 'Renamed from ${row.sport.name}'
        : (row.sport.category != null && row.sport.category!.isNotEmpty
            ? row.sport.category!
            : null);

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      onTap: canManage ? () => _renameDialog(context, ref, row) : null,
      child: Row(
        children: [
          // Sport-colored icon disc — ties the row to the sport accent.
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(sportIcon(row.displayName), color: tint, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: AppType.semibold,
                        ),
                      ),
                    ),
                    if (isRenamed) ...[
                      const SizedBox(width: AppSpacing.sm),
                      const AppBadge(text: 'Renamed', tone: AppBadgeTone.info),
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (canManage)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _renameDialog(context, ref, row),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (v) async {
                    final repo = await ref.read(sportsRepoProvider.future);
                    if (repo == null) return;
                    if (v == 'rename') {
                      if (!context.mounted) return;
                      await _renameDialog(context, ref, row);
                    } else if (v == 'remove') {
                      if (!context.mounted) return;
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Remove ${row.displayName}?'),
                          content: const Text(
                            'Existing students / batches keep their sport '
                            'assignment until you change them. You can re-add '
                            'this sport later.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (confirm ?? false) {
                        await repo.disableCenterSport(row.id);
                        ref.invalidate(centerSportsProvider(row.centerId));
                        ref.invalidate(academyCenterSportsProvider);
                      }
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _renameDialog(
    BuildContext context,
    WidgetRef ref,
    CenterSport row,
  ) async {
    final ctrl = TextEditingController(text: row.customName ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rename ${row.sport.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppFormField(
              controller: ctrl,
              label: 'Display name',
              hint: row.sport.name,
              autofocus: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Leave blank to revert to the catalog name.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final repo = await ref.read(sportsRepoProvider.future);
    if (repo == null) return;
    await repo.updateCenterSport(
      row.id,
      customName: result.isEmpty ? '' : result,
    );
    ref.invalidate(centerSportsProvider(row.centerId));
    ref.invalidate(academyCenterSportsProvider);
  }
}

class _AddSportSheet extends ConsumerStatefulWidget {
  const _AddSportSheet({required this.centerId});
  final String centerId;

  @override
  ConsumerState<_AddSportSheet> createState() => _AddSportSheetState();
}

class _AddSportSheetState extends ConsumerState<_AddSportSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allAsync = ref.watch(allSportsProvider);
    final enabledAsync = ref.watch(centerSportsProvider(widget.centerId));

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grab handle.
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            Text(
              'Add a sport',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: AppType.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppFormField(
              label: 'Search catalog',
              hint: 'Search sports',
              prefixIcon: const Icon(Icons.search),
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.md),
            allAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: AppLoading(),
              ),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(allSportsProvider),
              ),
              data: (all) {
                final enabledIds = (enabledAsync.valueOrNull ?? const [])
                    .map((s) => s.sport.id)
                    .toSet();
                final q = _query.trim().toLowerCase();
                final candidates = all.where((s) {
                  if (enabledIds.contains(s.id)) return false;
                  if (q.isEmpty) return true;
                  final inName = s.name.toLowerCase().contains(q);
                  final inCategory =
                      s.category?.toLowerCase().contains(q) ?? false;
                  return inName || inCategory;
                }).toList(growable: false);
                if (candidates.isEmpty) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Text(
                      q.isEmpty
                          ? 'Every catalog sport is already enabled at this '
                              'center.'
                          : 'No sports match "$_query".',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: candidates.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = candidates[i];
                      final tint = colorFromName(s.name);
                      return AppListTile(
                        wrapLeading: false,
                        leading: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tint.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(sportIcon(s.name), color: tint, size: 20),
                        ),
                        title: Text(s.name),
                        subtitle:
                            s.category != null ? Text(s.category!) : null,
                        trailing: FilledButton.tonal(
                          onPressed: () async {
                            final repo =
                                await ref.read(sportsRepoProvider.future);
                            if (repo == null) return;
                            await repo.enableSportAtCenter(
                              centerId: widget.centerId,
                              sportId: s.id,
                            );
                            ref.invalidate(
                              centerSportsProvider(widget.centerId),
                            );
                            ref.invalidate(academyCenterSportsProvider);
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: const Text('Add'),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

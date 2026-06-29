import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playhub/core/design_tokens.dart';
import 'package:playhub/core/error_messages.dart';
import 'package:playhub/features/auth/data/capabilities.dart';
import 'package:playhub/features/coaches/data/coach.dart';
import 'package:playhub/features/coaches/data/coach_providers.dart';
import 'package:playhub/features/coaches/presentation/coach_bulk_import_page.dart';
import 'package:playhub/features/coaches/presentation/coach_form_page.dart';
import 'package:playhub/features/subscription/data/trial_limits.dart';
import 'package:playhub/shared/widgets/avatar_picker.dart';
import 'package:playhub/shared/widgets/widgets.dart';

/// Local active/inactive filter for the coaches list. `null` = all.
enum _CoachStatusFilter { all, active, inactive }

/// Body tab under `owner_home_shell`'s single AppBar — stays app-bar-less with
/// an in-body header row instead (archetype B). v1 "Sports-Light" list.
class CoachesTab extends ConsumerStatefulWidget {
  const CoachesTab({super.key});

  @override
  ConsumerState<CoachesTab> createState() => _CoachesTabState();
}

class _CoachesTabState extends ConsumerState<CoachesTab> {
  final _search = TextEditingController();
  _CoachStatusFilter _status = _CoachStatusFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openForm({Coach? existing}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => CoachFormPage(existing: existing)),
    );
  }

  void _openImport() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CoachBulkImportPage()),
    );
  }

  void _showTrialLimit(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Client-side search + status filter over the already-fetched list. The
  /// coaches provider returns the full tenant-scoped set; we narrow it here so
  /// the data layer stays untouched.
  List<Coach> _filter(List<Coach> coaches) {
    final query = _search.text.trim().toLowerCase();
    return coaches.where((c) {
      switch (_status) {
        case _CoachStatusFilter.active:
          if (!c.isActive) return false;
        case _CoachStatusFilter.inactive:
          if (c.isActive) return false;
        case _CoachStatusFilter.all:
          break;
      }
      if (query.isEmpty) return true;
      final haystack = [
        c.fullName,
        ...c.specialization,
        if (c.email != null) c.email!,
        if (c.phone != null) c.phone!,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final coachesAsync = ref.watch(coachesProvider);
    final caps = ref.watch(capabilitiesProvider);

    // Free-trial cap: once at the coach limit, create entry points prompt to
    // upgrade instead of opening the form (RLS is the hard backstop).
    final limits = ref.watch(trialLimitsProvider).valueOrNull;
    final coachesBlocked = limits?.coachesReached ?? false;

    // Header count reflects the filtered view (null until data lands).
    final loaded = coachesAsync.valueOrNull;
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
            // Bulk import creates NEW coaches — onboarding, so it follows the
            // same gate as the New-coach FAB. RLS rejects it regardless.
            onImport: !caps.manageCoaches
                ? null
                : coachesBlocked
                    ? () => _showTrialLimit(limits!.coachesMessage)
                    : _openImport,
          ),
          Expanded(
            child: coachesAsync.when(
              loading: () => const AppSkeletonList(),
              error: (e, _) => AppErrorView(
                message: friendlyError(e),
                onRetry: () => ref.invalidate(coachesProvider),
              ),
              data: (coaches) {
                if (coaches.isEmpty) {
                  return const _EmptyState();
                }
                final results = _filter(coaches);
                if (results.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.search_off_outlined,
                    title: 'No matches',
                    subtitle: 'Try a different name or clear the filters.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(coachesProvider),
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
                    itemBuilder: (context, i) => _CoachTile(
                      coach: results[i],
                      onTap: () => _openForm(existing: results[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: caps.manageCoaches
          ? FloatingActionButton.extended(
              heroTag: 'fab-coaches',
              onPressed: coachesBlocked
                  ? () => _showTrialLimit(limits!.coachesMessage)
                  : _openForm,
              icon: Icon(coachesBlocked ? Icons.lock_outline : Icons.add),
              label: const Text('New coach'),
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
    required this.onImport,
  });

  final TextEditingController controller;
  final _CoachStatusFilter status;
  // Live count of the filtered results, shown in the header badge.
  final int? count;
  final VoidCallback onSearch;
  final ValueChanged<_CoachStatusFilter> onStatusChanged;
  // Null hides the CSV-import action (roles that can't manage coaches).
  final VoidCallback? onImport;

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
                Text('Coaches', style: theme.textTheme.headlineSmall),
                const SizedBox(width: AppSpacing.sm),
                if (count != null)
                  AppBadge(text: '$count', tone: AppBadgeTone.brand),
                const Spacer(),
                if (onImport != null)
                  IconButton(
                    tooltip: 'Import CSV',
                    icon: const Icon(Icons.upload_file_outlined),
                    onPressed: onImport,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              onSubmitted: (_) => onSearch(),
              onChanged: (_) => onSearch(),
              decoration: InputDecoration(
                hintText: 'Search name, specialization…',
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
                  onStatusChanged(_CoachStatusFilter.values[i]),
            ),
          ],
        ),
      ),
    );
  }
}

/// A coach row as a soft-shadow [AppCard]: photo (or gradient-initials)
/// avatar → name → one tight fact line (specialization • experience) →
/// trailing active/inactive [AppBadge].
class _CoachTile extends StatelessWidget {
  const _CoachTile({required this.coach, required this.onTap});
  final Coach coach;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials =
        (coach.firstName.isNotEmpty ? coach.firstName[0] : '?') +
            (coach.lastName.isNotEmpty ? coach.lastName[0] : '');
    // Two facts that matter on a people list: what they coach and how senior.
    // Phone/email live on the detail page so the subtitle stays one tight line.
    final facts = <String>[
      if (coach.specialization.isNotEmpty) coach.specialization.first,
      if (coach.experienceYears != null) '${coach.experienceYears} yrs',
    ];
    final hasPhoto = coach.photo != null && coach.photo!.isNotEmpty;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          if (hasPhoto)
            AvatarView(url: coach.photo, fallbackInitials: initials)
          else
            AppAvatar(coach.fullName),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coach.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  facts.isEmpty ? 'Coach' : facts.join(' • '),
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
          _StatusBadge(isActive: coach.isActive),
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
      icon: Icons.sports_outlined,
      title: 'No coaches yet',
      subtitle: 'Tap "New coach" to onboard your first one.',
    );
  }
}
